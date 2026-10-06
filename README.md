# Cyber-Tiel FastMTP RunPod

Run **Cyber-Tiel-Coder 35B-A3B GGUF-MTP** with llama.cpp on RunPod/NVIDIA GPUs.

- Model: `peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP`
- Runtime: llama.cpp CUDA server
- API: OpenAI-compatible `/v1`
- Default quant: `UD-Q6_K_XL` (~32.2 GB)
- Default MTP: **OFF**
- Optional MTP: `MTP=true`
- Optional vision: `MMPROJ_FILE=mmproj-BF16.gguf`
- Optional Cyber/CTF sampling profile: `PROFILE=cyber`

The model card recommends `UD-Q4_K_XL` as the ~22 GB 4-bit tier. It also documents `--spec-type draft-mtp` for enabling the grafted MTP head and recommends keeping all layers on GPU while using `--n-cpu-moe` for partial expert offload when VRAM is tight.

## Why MTP is OFF by default

MTP is not automatically faster on every GPU/runtime. This image therefore makes it a runtime switch:

```text
MTP=false   -> normal Cyber-Tiel decode
MTP=true    -> speculative MTP decode
```

Benchmark both on your actual RunPod GPU and workload.

## Quick start on RunPod

Create a RunPod GPU pod with enough VRAM/RAM and expose TCP port `8000`.

Use this image after publishing it to GHCR:

```bash
docker pull ghcr.io/devendra2016/cybertiel-fastmtp-runpod:latest
```

Run:

```bash
docker run --gpus all \
  -p 8000:8000 \
  -v /workspace/models:/workspace/models \
  -e MTP=false \
  -e CTX_SIZE=131072 \
  ghcr.io/devendra2016/cybertiel-fastmtp-runpod:latest
```

The model is downloaded into `/workspace/models` on first start.

## Recommended first configuration

For your supplied RunPod A40-class pod (48 GB VRAM / 50 GB RAM / 9 vCPU), use:

```text
MODEL_FILE=Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf
MTP=false
CTX_SIZE=262144
GPU_LAYERS=99
N_CPU_MOE=0
FLASH_ATTN=on
CACHE_TYPE_K=q8_0
CACHE_TYPE_V=q8_0
PROFILE=coding
```

The Cyber-Tiel model card lists `UD-Q6_K_XL` at 32.2 GB and the A40 has 48 GB VRAM. This leaves room for the Q8 KV cache and runtime buffers. The model card estimates about 3.1 GB for Q8 KV at 262K context. Start with 262K; if your llama.cpp build or workload leaves less headroom than expected, drop to 131K.

For your A40, keep `-ngl 99` and `N_CPU_MOE=0`; CPU MoE offload is unnecessary unless you observe a memory constraint.

The Cyber-Tiel model card gives a 24 GB Q4 starting point of roughly `--n-cpu-moe 2–4` at 64K context with Q8 KV. Actual VRAM use depends on llama.cpp version, batch size, context, and runtime conditions, so start conservatively and watch VRAM/tokens/sec.

For larger GPUs, use:

```text
N_CPU_MOE=0
GPU_LAYERS=99
```

## MTP benchmark

Run the exact same workload twice.

### Baseline

```text
MTP=false
```

### Speculative

```text
MTP=true
MTP_N_MAX=3
```

Compare:

- prompt processing time
- generation tok/s
- total completion time
- accepted/drafted tokens
- VRAM
- GPU utilization
- agent task success

Do not optimize only for raw tok/s. For an agent, **time-to-successful-task-completion** is usually the better metric.

## Coding profile

Default sampling:

```text
temperature = 0.6
top_p       = 0.95
top_k       = 20
min_p       = 0
```

This follows the model card's agentic-coding recommendation.

## Cyber / CTF profile

Set:

```text
PROFILE=cyber
```

This changes the sampling to:

```text
top_k = 40
min_p = 0.05
```

The model card describes this as a looser configuration for more divergent/exploratory solutions on cybersecurity/CTF tasks.

Use only on systems and targets you are authorized to test.

## Vision

The repository includes `mmproj-BF16.gguf` and `mmproj-Q8_0.gguf`.

To enable vision:

```text
MMPROJ_FILE=mmproj-BF16.gguf
```

The startup script downloads the projector automatically.

Example:

```bash
docker run --gpus all \
  -p 8000:8000 \
  -v /workspace/models:/workspace/models \
  -e MMPROJ_FILE=mmproj-BF16.gguf \
  -e MTP=false \
  ghcr.io/devendra2016/cybertiel-fastmtp-runpod:latest
```

## OpenAI-compatible API

Health:

```bash
curl http://localhost:8000/health
```

Models:

```bash
curl http://localhost:8000/v1/models
```

Chat:

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "cyber-tiel",
    "messages": [
      {
        "role": "user",
        "content": "Write a Python function that parses IPv4 CIDR ranges."
      }
    ],
    "temperature": 0.6
  }'
```

If `API_KEY` is set, include:

```bash
-H "Authorization: Bearer YOUR_KEY"
```

## RunPod environment variables

| Variable | Default | Purpose |
|---|---|---|
| `MODEL_REPO` | `peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP` | HF repository |
| `MODEL_FILE` | `Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf` | GGUF |
| `MODEL_DIR` | `/workspace/models` | persistent model directory |
| `MTP` | `false` | enable MTP |
| `MTP_N_MAX` | `3` | max speculative tokens |
| `CTX_SIZE` | `131072` | context length |
| `BATCH_SIZE` | `2048` | logical batch |
| `UBATCH_SIZE` | `512` | physical batch |
| `PARALLEL` | `1` | concurrent sequences |
| `GPU_LAYERS` | `99` | GPU layers |
| `N_CPU_MOE` | `0` | routed MoE layers on CPU |
| `FLASH_ATTN` | `on` | flash attention |
| `CACHE_TYPE_K` | `q8_0` | K cache |
| `CACHE_TYPE_V` | `q8_0` | V cache |
| `TEMP` | `0.6` | temperature |
| `TOP_P` | `0.95` | top-p |
| `TOP_K` | `20` | top-k |
| `MIN_P` | `0` | min-p |
| `PROFILE` | `coding` | `coding` or `cyber` |
| `MMPROJ_FILE` | empty | vision projector |
| `API_KEY` | empty | optional API auth |
| `HF_TOKEN` | empty | optional HF token |
| `PORT` | `8000` | server port |
| `EXTRA_ARGS` | empty | extra llama-server args |

## Persistent cache

On RunPod, mount a Network Volume or persistent volume at:

```text
/workspace/models
```

This prevents the ~22.7 GB model from being downloaded again when the pod/container restarts.

## Security

Cyber-Tiel is an abliterated model and can produce content that ordinary instruction-following models may refuse. Keep the inference service private unless you intentionally configure authentication and network controls.

Do not expose an unauthenticated instance to the public Internet.

For autonomous security agents, isolate:

- model container
- filesystem
- credentials
- shell/tool execution
- outbound network access

The model itself does not make an authorization decision for you.

## Building locally

```bash
docker build -t cybertiel-fastmtp-runpod .
```

Run:

```bash
docker run --gpus all \
  -p 8000:8000 \
  -v "$PWD/models:/workspace/models" \
  cybertiel-fastmtp-runpod
```

## GitHub Actions

Pushing to `main` builds and publishes:

```text
ghcr.io/devendra2016/cybertiel-fastmtp-runpod:latest
```

A tag such as `v1.0.0` also creates a versioned image tag.

## Model license / attribution

Cyber-Tiel is released under MIT according to its Hugging Face model card. This repository is a runtime/deployment wrapper and does not redistribute the GGUF weights.

Model:

https://huggingface.co/peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP

Runtime:

https://github.com/ggml-org/llama.cpp


## RunPod template settings

Use the image:

```text
ghcr.io/devendra2016/cybertiel-fastmtp-runpod:latest
```

Expose:

```text
HTTP Port: 8000
```

RunPod's HTTP proxy then gives you:

```text
https://POD_ID-8000.proxy.runpod.net
```

Use a RunPod Secret named:

```text
HF_TOKEN
```

and map it to the container environment variable:

```text
HF_TOKEN
```

Do not put the Hugging Face token directly in this repository or hard-code it in the Dockerfile.

Recommended template environment:

```text
MODEL_REPO=peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP
MODEL_FILE=Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf
MODEL_DIR=/workspace/models

HOST=0.0.0.0
PORT=8000

HF_TOKEN={{ HF_TOKEN }}

MTP=false
MTP_N_MAX=3

CTX_SIZE=262144
BATCH_SIZE=2048
UBATCH_SIZE=512
PARALLEL=1
GPU_LAYERS=99
N_CPU_MOE=0

FLASH_ATTN=on
CACHE_TYPE_K=q8_0
CACHE_TYPE_V=q8_0

PROFILE=coding
TEMP=0.6
TOP_P=0.95
TOP_K=20
MIN_P=0
```

If your RunPod UI uses a different secret-reference syntax, select the `HF_TOKEN` secret through the template's Secrets/Environment UI rather than pasting the token value.
