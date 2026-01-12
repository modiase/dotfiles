"""FastAPI server for multi-model vLLM orchestration with OpenAI-compatible API."""

from __future__ import annotations

import logging
import os
import time
import uuid
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from vllm import SamplingParams

from model_manager import ModelConfig, ModelManager, ModelType

MODEL_ALIASES: dict[str, ModelType] = {
    "qwen-chat": ModelType.CHAT,
    "qwen-coder": ModelType.CODER,
    "QuixiAI/Qwen3-30B-A3B-AWQ": ModelType.CHAT,
    "cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit": ModelType.CODER,
}
DEFAULT_CHAT_MODEL = ModelType.CHAT


def resolve_model(model_name: str) -> ModelType:
    """Resolve model name/alias to ModelType, defaulting to CHAT."""
    return MODEL_ALIASES.get(model_name, DEFAULT_CHAT_MODEL)


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

manager: ModelManager | None = None


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatCompletionRequest(BaseModel):
    model: str
    messages: list[ChatMessage]
    temperature: float = 0.7
    top_p: float = 1.0
    max_tokens: int | None = None
    stop: list[str] | str | None = None
    stream: bool = False


class ChatCompletionChoice(BaseModel):
    index: int
    message: ChatMessage
    finish_reason: str


class Usage(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


class ChatCompletionResponse(BaseModel):
    id: str
    object: str = "chat.completion"
    created: int
    model: str
    choices: list[ChatCompletionChoice]
    usage: Usage


class EmbeddingRequest(BaseModel):
    model: str
    input: list[str] | str
    encoding_format: str = "float"


class EmbeddingData(BaseModel):
    object: str = "embedding"
    index: int
    embedding: list[float]


class EmbeddingResponse(BaseModel):
    object: str = "list"
    data: list[EmbeddingData]
    model: str
    usage: Usage


class ModelInfo(BaseModel):
    id: str
    object: str = "model"
    created: int = 1677610602
    owned_by: str = "vllm"


class ModelListResponse(BaseModel):
    object: str = "list"
    data: list[ModelInfo]


class HealthResponse(BaseModel):
    status: str
    active_model: str | None
    chat_model: str
    coder_model: str
    embed_model: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    global manager

    config = ModelConfig(
        chat_model=os.environ.get("CHAT_MODEL", "QuixiAI/Qwen3-30B-A3B-AWQ"),
        coder_model=os.environ.get(
            "CODER_MODEL", "cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit"
        ),
        embed_model=os.environ.get("EMBED_MODEL", "Qwen/Qwen3-Embedding-0.6B"),
        gpu_memory_utilization=float(os.environ.get("GPU_MEMORY_UTIL", "0.85")),
        max_model_len=int(os.environ.get("MAX_MODEL_LEN", "32768")),
        max_num_seqs=int(os.environ.get("MAX_NUM_SEQS", "256")),
        idle_timeout_s=float(os.environ.get("IDLE_TIMEOUT", "300")),
    )

    manager = ModelManager(config)
    logger.info("Starting model initialization...")
    await manager.initialize()
    logger.info("Model manager ready")

    yield

    logger.info("Shutting down...")
    await manager.shutdown()


app = FastAPI(title="LLM Orchestrator", lifespan=lifespan)


def format_messages_to_prompt(messages: list[ChatMessage]) -> str:
    """Convert chat messages to a single prompt string."""
    parts = []
    for msg in messages:
        if msg.role == "system":
            parts.append(f"<|im_start|>system\n{msg.content}<|im_end|>")
        elif msg.role == "user":
            parts.append(f"<|im_start|>user\n{msg.content}<|im_end|>")
        elif msg.role == "assistant":
            parts.append(f"<|im_start|>assistant\n{msg.content}<|im_end|>")
    parts.append("<|im_start|>assistant\n")
    return "\n".join(parts)


@app.post("/v1/chat/completions", response_model=ChatCompletionResponse)
async def chat_completions(request: ChatCompletionRequest):
    if manager is None:
        raise HTTPException(status_code=503, detail="Model manager not initialized")

    if request.stream:
        raise HTTPException(status_code=400, detail="Streaming not yet supported")

    prompt = format_messages_to_prompt(request.messages)

    stop_sequences = []
    if request.stop:
        if isinstance(request.stop, str):
            stop_sequences = [request.stop]
        else:
            stop_sequences = request.stop

    sampling_params = SamplingParams(
        temperature=request.temperature,
        top_p=request.top_p,
        max_tokens=request.max_tokens or 2048,
        stop=stop_sequences or ["<|im_end|>"],
    )

    model_type = resolve_model(request.model)
    async with manager.use_model(model_type):
        outputs = manager.generate_chat([prompt], sampling_params)

    output = outputs[0]
    generated_text = output.outputs[0].text

    prompt_tokens = len(output.prompt_token_ids)
    completion_tokens = len(output.outputs[0].token_ids)

    return ChatCompletionResponse(
        id=f"chatcmpl-{uuid.uuid4().hex[:8]}",
        created=int(time.time()),
        model=request.model,
        choices=[
            ChatCompletionChoice(
                index=0,
                message=ChatMessage(role="assistant", content=generated_text),
                finish_reason=output.outputs[0].finish_reason or "stop",
            )
        ],
        usage=Usage(
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=prompt_tokens + completion_tokens,
        ),
    )


@app.post("/v1/embeddings", response_model=EmbeddingResponse)
async def embeddings(request: EmbeddingRequest):
    if manager is None:
        raise HTTPException(status_code=503, detail="Model manager not initialized")

    texts = [request.input] if isinstance(request.input, str) else request.input

    async with manager.use_model(ModelType.EMBED):
        outputs = manager.generate_embeddings(texts)

    data = []
    total_tokens = 0
    for i, output in enumerate(outputs):
        embedding = output.outputs.embedding
        if hasattr(embedding, "tolist"):
            embedding = embedding.tolist()
        data.append(EmbeddingData(index=i, embedding=embedding))
        total_tokens += len(output.prompt_token_ids)

    return EmbeddingResponse(
        data=data,
        model=request.model,
        usage=Usage(
            prompt_tokens=total_tokens,
            completion_tokens=0,
            total_tokens=total_tokens,
        ),
    )


@app.get("/v1/models", response_model=ModelListResponse)
async def list_models():
    if manager is None:
        raise HTTPException(status_code=503, detail="Model manager not initialized")

    return ModelListResponse(
        data=[
            ModelInfo(id="qwen-chat"),
            ModelInfo(id="qwen-coder"),
            ModelInfo(id=manager.config.chat_model),
            ModelInfo(id=manager.config.coder_model),
            ModelInfo(id=manager.config.embed_model),
        ]
    )


@app.get("/health", response_model=HealthResponse)
async def health():
    if manager is None:
        return HealthResponse(
            status="initializing",
            active_model=None,
            chat_model="",
            coder_model="",
            embed_model="",
        )

    status = manager.status
    return HealthResponse(
        status="ok" if status["initialized"] else "initializing",
        active_model=status["active_model"],
        chat_model=status["chat_model"],
        coder_model=status["coder_model"],
        embed_model=status["embed_model"],
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host=os.environ.get("HOST", "0.0.0.0"),
        port=int(os.environ.get("PORT", "8000")),
    )
