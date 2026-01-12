"""Model lifecycle management with vLLM sleep mode for weight swapping."""

from __future__ import annotations

import asyncio
import logging
import time
from contextlib import asynccontextmanager
from dataclasses import dataclass
from enum import Enum
from typing import TYPE_CHECKING, Any

from vllm import LLM, SamplingParams

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

logger = logging.getLogger(__name__)


class ModelType(str, Enum):
    CHAT = "chat"
    CODER = "coder"
    EMBED = "embed"


@dataclass
class ModelConfig:
    chat_model: str
    coder_model: str
    embed_model: str
    gpu_memory_utilization: float = 0.85
    max_model_len: int = 32768
    max_num_seqs: int = 256
    idle_timeout_s: float = 300.0


class ModelManager:
    def __init__(self, config: ModelConfig) -> None:
        self.config = config
        self._models: dict[ModelType, LLM | None] = {
            ModelType.CHAT: None,
            ModelType.CODER: None,
            ModelType.EMBED: None,
        }
        self.active_model: ModelType | None = None
        self._lock = asyncio.Lock()
        self._initialized = False
        self._last_activity: float = time.time()
        self._idle_task: asyncio.Task[None] | None = None

    def _get_llm(self, model_type: ModelType) -> LLM:
        llm = self._models[model_type]
        if llm is None:
            raise RuntimeError(f"{model_type.value} model not initialised")
        return llm

    async def initialize(self) -> None:
        """Initialises all models, starting with chat model active."""
        if self._initialized:
            return

        logger.info("Initialising chat model: %s", self.config.chat_model)
        self._models[ModelType.CHAT] = LLM(
            model=self.config.chat_model,
            enable_sleep_mode=True,
            enforce_eager=True,
            gpu_memory_utilization=self.config.gpu_memory_utilization,
            max_model_len=self.config.max_model_len,
            max_num_seqs=self.config.max_num_seqs,
            trust_remote_code=True,
            enable_prefix_caching=True,
        )
        self._get_llm(ModelType.CHAT).sleep(level=1)

        logger.info("Initialising coder model: %s", self.config.coder_model)
        self._models[ModelType.CODER] = LLM(
            model=self.config.coder_model,
            enable_sleep_mode=True,
            enforce_eager=True,
            gpu_memory_utilization=self.config.gpu_memory_utilization,
            max_model_len=self.config.max_model_len,
            max_num_seqs=self.config.max_num_seqs,
            trust_remote_code=True,
            enable_prefix_caching=True,
        )
        self._get_llm(ModelType.CODER).sleep(level=1)

        logger.info("Initialising embed model: %s", self.config.embed_model)
        self._models[ModelType.EMBED] = LLM(
            model=self.config.embed_model,
            enable_sleep_mode=True,
            enforce_eager=True,
            gpu_memory_utilization=0.15,
            max_model_len=8192,
            task="embed",
            trust_remote_code=True,
        )
        self._get_llm(ModelType.EMBED).sleep(level=1)

        logger.info("Waking chat model as default")
        self._get_llm(ModelType.CHAT).wake_up()
        self.active_model = ModelType.CHAT
        self._last_activity = time.time()
        self._idle_task = asyncio.create_task(self._idle_monitor())
        self._initialized = True
        logger.info("Model manager initialised, chat model active")

    async def shutdown(self) -> None:
        logger.info("Shutting down model manager")
        if self._idle_task:
            self._idle_task.cancel()
            try:
                await self._idle_task
            except asyncio.CancelledError:
                pass
            self._idle_task = None
        self._initialized = False
        for model_type in ModelType:
            self._models[model_type] = None
        self.active_model = None

    @asynccontextmanager
    async def use_model(self, model_type: ModelType) -> AsyncIterator[None]:
        """Context manager for using a specific model with automatic swapping."""
        async with self._lock:
            self._last_activity = time.time()
            if self.active_model != model_type:
                await self._swap_to(model_type)
            yield

    async def _swap_to(self, model_type: ModelType) -> None:
        if self.active_model is not None:
            logger.info("Sleeping %s model", self.active_model.value)
            self._get_llm(self.active_model).sleep(level=1)
        logger.info("Waking %s model", model_type.value)
        self._get_llm(model_type).wake_up()
        self.active_model = model_type

    async def _idle_monitor(self) -> None:
        """Background task to offload models after idle timeout."""
        while True:
            await asyncio.sleep(60)
            async with self._lock:
                if self.active_model is None:
                    continue
                idle_time = time.time() - self._last_activity
                if idle_time > self.config.idle_timeout_s:
                    logger.info(
                        "Idle timeout (%.0fs), offloading %s to sysram",
                        idle_time,
                        self.active_model.value,
                    )
                    self._get_llm(self.active_model).sleep(level=1)
                    self.active_model = None

    def generate_chat(
        self,
        prompts: list[str],
        sampling_params: SamplingParams | None = None,
    ) -> list[Any]:
        if self.active_model not in (ModelType.CHAT, ModelType.CODER):
            raise RuntimeError("No chat/coder model active")
        if sampling_params is None:
            sampling_params = SamplingParams()
        return self._get_llm(self.active_model).generate(prompts, sampling_params)

    def generate_embeddings(self, texts: list[str]) -> list[Any]:
        if self.active_model != ModelType.EMBED:
            raise RuntimeError("Embed model not active")
        return self._get_llm(ModelType.EMBED).embed(texts)

    @property
    def status(self) -> dict[str, Any]:
        return {
            "initialized": self._initialized,
            "active_model": self.active_model.value if self.active_model else None,
            "chat_model": self.config.chat_model,
            "coder_model": self.config.coder_model,
            "embed_model": self.config.embed_model,
        }
