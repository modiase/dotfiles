# vLLM Server for Qwen3-Coder

This project sets up a vLLM server for running Qwen3-Coder-30B-A3B-Instruct with 4-bit quantization on a 24GB VRAM GPU (RTX 3090).

## Hardware

- **GPU**: NVIDIA GeForce RTX 3090 (24GB VRAM)
- **CPU**: Intel Core i7-14700K
- **RAM**: 94GB
- **CUDA**: 13.0
- **Driver**: 580.105.08

## VRAM Estimation

**Note**: Qwen3-Coder-30B-A3B-Instruct is a MoE (Mixture of Experts) model where "A3B" indicates ~3B activated parameters per token. This means actual VRAM usage may be lower than a dense 30B model.

Estimated VRAM usage with 4-bit quantization:

- **Model weights (4-bit quantized)**: ~15 GB (or less for MoE)
- **KV cache (32K context)**: ~2.5 GB
- **Overhead**: ~2 GB
- **Total**: ~19.5 GB / 24 GB (81% utilization)

If quantization is not available, the model may require more VRAM. Adjust `gpu_memory_utilization` or `max_model_len` accordingly.

## Setup

### Using Nix App (Recommended)

The easiest way to start the server:

```bash
# Start the vLLM server directly
nix run #.serve

# Or use the default app
nix run
```

You can customize settings with environment variables:

```bash
MODEL="Qwen/Qwen3-Coder-30B-A3B-Instruct" \
QUANTIZATION="awq" \
MAX_MODEL_LEN="16384" \
GPU_MEMORY_UTIL="0.85" \
PORT="8000" \
nix run #.serve
```

### Using Nix Development Shell

```bash
# Enter the development shell
nix develop

# The shell will automatically install vLLM if not present
# Test the model loading
python run_vllm.py

# Start the API server (script is internalized in the flake)
start-server
```

### Configuration Options

All scripts support environment variables for configuration:

```bash
# Customize server settings
MODEL="Qwen/Qwen3-Coder-30B-A3B-Instruct" \
QUANTIZATION="awq" \
MAX_MODEL_LEN="16384" \
GPU_MEMORY_UTIL="0.85" \
PORT="8000" \
nix run #.serve

# Or in devShell
MODEL="Qwen/Qwen3-Coder-30B-A3B-Instruct" \
QUANTIZATION="gptq" \
MAX_MODEL_LEN="16384" \
start-server

# Test model loading with custom settings
python run_vllm.py --max-model-len 16384 --gpu-memory-utilization 0.85
```

### Default Settings

- **Model**: `Qwen/Qwen3-Coder-30B-A3B-Instruct`
- **Quantization**: AWQ (4-bit)
- **Max Context Length**: 32,768 tokens
- **GPU Memory Utilization**: 90%
- **Server Port**: 8000

## API Usage

Once the server is running, it provides an OpenAI-compatible API:

```bash
# Chat completion example
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-Coder-30B-A3B-Instruct",
    "messages": [
      {"role": "user", "content": "Write a Python function to calculate fibonacci numbers"}
    ],
    "max_tokens": 512
  }'
```

## Notes

- The model will be downloaded from HuggingFace on first run
- Ensure you have sufficient disk space (~60GB for the quantized model, ~120GB for full precision)
- Monitor VRAM usage with `nvidia-smi` while the server is running
- Adjust `gpu_memory_utilization` if you encounter OOM errors
- If AWQ/GPTQ quantization is not available for this model, you may need to:
  - Use `--quantization none` and reduce `--max-model-len` to 8192-16384
  - Or use a pre-quantized model variant if available
- The MoE architecture means actual memory usage may vary based on which experts are activated
