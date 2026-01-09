"""Model lifecycle management with vLLM sleep mode for weight swapping."""

from __future__ import annotations

import asyncio
import logging
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
    EMBED = "embed"


@dataclass
class ModelConfig:
    chat_model: str
    embed_model: str
    gpu_memory_utilization: float = 0.85
    max_model_len: int = 32768
    max_num_seqs: int = 256
    swap_timeout_s: float = 30.0


class ModelManager:
    def __init__(self, config: ModelConfig) -> None:
        self.config = config
        self.chat_llm: LLM | None = None
        self.embed_llm: LLM | None = None
        self.active_model: ModelType | None = None
        self._lock = asyncio.Lock()
        self._initialized = False

    async def initialize(self) -> None:
        """Initializes both models, starting with chat model active."""
        if self._initialized:
            return

        logger.info("Initializing chat model: %s", self.config.chat_model)
        self.chat_llm = LLM(
            model=self.config.chat_model,
            enable_sleep_mode=True,
            gpu_memory_utilization=self.config.gpu_memory_utilization,
            max_model_len=self.config.max_model_len,
            max_num_seqs=self.config.max_num_seqs,
            trust_remote_code=True,
            enable_prefix_caching=True,
        )

        logger.info("Sleeping chat model to load embed model")
        self.chat_llm.sleep(
            level=1  # level=1 keeps weights in sysram rather than dropping them.
        )

        logger.info("Initializing embed model: %s", self.config.embed_model)
        self.embed_llm = LLM(
            enable_sleep_mode=True,
            gpu_memory_utilization=0.15,
            max_model_len=8192,
            model=self.config.embed_model,
            task="embed",
            trust_remote_code=True,
        )

        logger.info("Sleeping embed model, waking chat model")
        self.embed_llm.sleep(level=2)
        self.chat_llm.wake_up()
        self.active_model = ModelType.CHAT
        self._initialized = True
        logger.info("Model manager initialized, chat model active")

    async def shutdown(self) -> None:
        logger.info("Shutting down model manager")
        self._initialized = False
        self.chat_llm = None
        self.embed_llm = None
        self.active_model = None

    @asynccontextmanager
    async def use_model(self, model_type: ModelType) -> AsyncIterator[None]:
        """Context manager for using a specific model with automatic swapping."""
        async with self._lock:
            if self.active_model != model_type:
                await self._swap_to(model_type)
            yield

    async def _swap_to(self, model_type: ModelType) -> None:
        if model_type == ModelType.CHAT:
            logger.info("Swapping to chat model")
            self.embed_llm.sleep(level=2)
            self.chat_llm.wake_up()
            logger.info("Chat model woke up")
            self.active_model = ModelType.CHAT
        else:
            logger.info("Swapping to embed model")
            self.chat_llm.sleep(level=1)
            self.embed_llm.wake_up()
            logger.info("Embed model woke up")
            self.active_model = ModelType.EMBED

    def generate_chat(
        self,
        prompts: list[str],
        sampling_params: SamplingParams | None = None,
    ) -> list[Any]:
        if self.active_model != ModelType.CHAT:
            raise RuntimeError("Chat model not active")
        if sampling_params is None:
            sampling_params = SamplingParams()
        return self.chat_llm.generate(prompts, sampling_params)

    def generate_embeddings(self, texts: list[str]) -> list[Any]:
        if self.active_model != ModelType.EMBED:
            raise RuntimeError("Embed model not active")
        return self.embed_llm.embed(texts)

    @property
    def status(self) -> dict[str, Any]:
        return {
            "initialized": self._initialized,
            "active_model": self.active_model.value if self.active_model else None,
            "chat_model": self.config.chat_model,
            "embed_model": self.config.embed_model,
        }
