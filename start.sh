#!/usr/bin/env bash
set -Eeuo pipefail

# -----------------------------
# Cyber-Tiel / llama.cpp config
# -----------------------------

MODEL_REPO="${MODEL_REPO:-peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP}"
MODEL_FILE="${MODEL_FILE:-Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q6_K_XL.gguf}"

# Hugging Face cache/model location.
MODEL_DIR="${MODEL_DIR:-/workspace/models}"
MODEL_PATH="${MODEL_PATH:-${MODEL_DIR}/${MODEL_FILE}}"

# Optional multimodal projector.
# Set MMPROJ_FILE=mmproj-BF16.gguf for vision support.
MMPROJ_FILE="${MMPROJ_FILE:-}"
MMPROJ_PATH="${MODEL_DIR}/${MMPROJ_FILE}"

# -----------------------------
# Server
# -----------------------------

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
API_KEY="${API_KEY:-}"
MODEL_ALIAS="${MODEL_ALIAS:-cyber-tiel}"

# -----------------------------
# Context / batching
# -----------------------------

CTX_SIZE="${CTX_SIZE:-262144}"
BATCH_SIZE="${BATCH_SIZE:-2048}"
UBATCH_SIZE="${UBATCH_SIZE:-512}"
PARALLEL="${PARALLEL:-1}"

# -----------------------------
# GPU / MoE
# -----------------------------

GPU_LAYERS="${GPU_LAYERS:-99}"
N_CPU_MOE="${N_CPU_MOE:-0}"

# -----------------------------
# Memory / attention
# -----------------------------

FLASH_ATTN="${FLASH_ATTN:-on}"
CACHE_TYPE_K="${CACHE_TYPE_K:-q8_0}"
CACHE_TYPE_V="${CACHE_TYPE_V:-q8_0}"

# -----------------------------
# Sampling
# -----------------------------

TEMP="${TEMP:-0.6}"
TOP_P="${TOP_P:-0.95}"
TOP_K="${TOP_K:-20}"
MIN_P="${MIN_P:-0}"

# Cyber/CTF profile can be selected with PROFILE=cyber.
PROFILE="${PROFILE:-coding}"

# -----------------------------
# MTP
# -----------------------------

# OFF by default.
# Set MTP=true to enable speculative decoding.
MTP="${MTP:-false}"
MTP_N_MAX="${MTP_N_MAX:-3}"

# -----------------------------
# Download
# -----------------------------

HF_TOKEN="${HF_TOKEN:-}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-false}"

# Optional extra llama-server arguments.
EXTRA_ARGS="${EXTRA_ARGS:-}"

# -----------------------------
# Logging helpers
# -----------------------------

log() {
  echo "[cyber-tiel] $*"
}

die() {
  echo "[cyber-tiel] ERROR: $*" >&2
  exit 1
}

# -----------------------------
# Find llama-server
# -----------------------------
#
# The official llama.cpp CUDA server image normally places the
# executable at /app/llama-server.
#
# We explicitly check that location first and then provide
# fallbacks for PATH/layout changes.
# -----------------------------

LLAMA_SERVER="${LLAMA_SERVER:-/app/llama-server}"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
  log "llama-server not executable at ${LLAMA_SERVER}; searching PATH..."
  LLAMA_SERVER="$(command -v llama-server 2>/dev/null || true)"
fi

if [[ -z "${LLAMA_SERVER}" || ! -x "${LLAMA_SERVER}" ]]; then
  for candidate in \
    /app/llama-server \
    /usr/local/bin/llama-server \
    /usr/bin/llama-server
  do
    if [[ -x "${candidate}" ]]; then
      LLAMA_SERVER="${candidate}"
      break
    fi
  done
fi

if [[ -z "${LLAMA_SERVER}" || ! -x "${LLAMA_SERVER}" ]]; then
  die "llama-server not found. Checked /app/llama-server, PATH, /usr/local/bin/llama-server and /usr/bin/llama-server."
fi

log "Using llama-server: ${LLAMA_SERVER}"

# -----------------------------
# Prepare model directory
# -----------------------------

mkdir -p "${MODEL_DIR}"

# -----------------------------
# Hugging Face downloader
# -----------------------------

download_hf() {
  local repo="$1"
  local filename="$2"
  local destination="$3"

  local url="https://huggingface.co/${repo}/resolve/main/${filename}?download=true"

  if [[ "${FORCE_DOWNLOAD}" != "true" && -s "${destination}" ]]; then
    log "Using existing file: ${destination}"
    return 0
  fi

  log "Downloading:"
  log "  Repo: ${repo}"
  log "  File: ${filename}"
  log "  Destination: ${destination}"

  local auth_args=()

  if [[ -n "${HF_TOKEN}" ]]; then
    auth_args=(
      -H
      "Authorization: Bearer ${HF_TOKEN}"
    )
  fi

  curl \
    -L \
    --fail \
    --retry 5 \
    --retry-delay 3 \
    --progress-bar \
    "${auth_args[@]}" \
    -o "${destination}.partial" \
    "${url}"

  mv "${destination}.partial" "${destination}"

  log "Download complete: ${destination}"
}

# -----------------------------
# Download main model
# -----------------------------

download_hf \
  "${MODEL_REPO}" \
  "${MODEL_FILE}" \
  "${MODEL_PATH}"

[[ -s "${MODEL_PATH}" ]] || \
  die "Model download failed: ${MODEL_PATH}"

# -----------------------------
# Sampling profile
# -----------------------------

if [[ "${PROFILE}" == "cyber" ]]; then
  TOP_K="${CYBER_TOP_K:-40}"
  MIN_P="${CYBER_MIN_P:-0.05}"

  log "Profile: cyber/CTF"
  log "  top-k=${TOP_K}"
  log "  min-p=${MIN_P}"
else
  log "Profile: agentic coding"
  log "  top-k=${TOP_K}"
  log "  min-p=${MIN_P}"
fi

# -----------------------------
# Build llama-server arguments
# -----------------------------

ARGS=(
  -m "${MODEL_PATH}"

  --host "${HOST}"
  --port "${PORT}"
  --alias "${MODEL_ALIAS}"

  --jinja

  --ctx-size "${CTX_SIZE}"

  --batch-size "${BATCH_SIZE}"
  --ubatch-size "${UBATCH_SIZE}"
  --parallel "${PARALLEL}"

  -ngl "${GPU_LAYERS}"

  -fa "${FLASH_ATTN}"

  -ctk "${CACHE_TYPE_K}"
  -ctv "${CACHE_TYPE_V}"

  --temp "${TEMP}"
  --top-p "${TOP_P}"
  --top-k "${TOP_K}"
  --min-p "${MIN_P}"
)

# -----------------------------
# CPU MoE offload
# -----------------------------

if [[ "${N_CPU_MOE}" != "0" ]]; then
  ARGS+=(
    --n-cpu-moe
    "${N_CPU_MOE}"
  )

  log "CPU MoE offload: ${N_CPU_MOE}"
else
  log "CPU MoE offload: disabled"
fi

# -----------------------------
# MTP
# -----------------------------

if [[ "${MTP,,}" == "true" ||
      "${MTP}" == "1" ||
      "${MTP,,}" == "yes" ]]; then

  ARGS+=(
    --spec-type
    draft-mtp

    --spec-draft-n-max
    "${MTP_N_MAX}"
  )

  log "MTP: ENABLED"
  log "MTP draft max: ${MTP_N_MAX}"

else

  log "MTP: DISABLED"

fi

# -----------------------------
# Vision / mmproj
# -----------------------------

if [[ -n "${MMPROJ_FILE}" ]]; then

  download_hf \
    "${MODEL_REPO}" \
    "${MMPROJ_FILE}" \
    "${MMPROJ_PATH}"

  [[ -s "${MMPROJ_PATH}" ]] || \
    die "mmproj download failed: ${MMPROJ_PATH}"

  ARGS+=(
    --mmproj
    "${MMPROJ_PATH}"
  )

  log "Vision projector: ${MMPROJ_PATH}"

else

  log "Vision projector: disabled"

fi

# -----------------------------
# API authentication
# -----------------------------

if [[ -n "${API_KEY}" ]]; then

  ARGS+=(
    --api-key
    "${API_KEY}"
  )

  log "API authentication: enabled"

else

  log "API authentication: disabled"

fi

# -----------------------------
# Extra arguments
# -----------------------------

if [[ -n "${EXTRA_ARGS}" ]]; then

  # shellcheck disable=SC2206
  EXTRA_ARRAY=( ${EXTRA_ARGS} )

  ARGS+=(
    "${EXTRA_ARRAY[@]}"
  )

  log "Extra llama-server arguments: ${EXTRA_ARGS}"

fi

# -----------------------------
# Final configuration
# -----------------------------

log "=========================================="
log "Cyber-Tiel Server"
log "=========================================="
log "Model:"
log "  ${MODEL_REPO}"
log "  ${MODEL_FILE}"
log ""
log "Model path:"
log "  ${MODEL_PATH}"
log ""
log "Context:"
log "  ${CTX_SIZE}"
log ""
log "GPU layers:"
log "  ${GPU_LAYERS}"
log ""
log "CPU MoE:"
log "  ${N_CPU_MOE}"
log ""
log "Flash Attention:"
log "  ${FLASH_ATTN}"
log ""
log "KV cache:"
log "  K=${CACHE_TYPE_K}"
log "  V=${CACHE_TYPE_V}"
log ""
log "MTP:"
log "  ${MTP}"
log ""
log "Endpoint:"
log "  http://${HOST}:${PORT}/v1"
log ""
log "llama-server:"
log "  ${LLAMA_SERVER}"
log "=========================================="

# -----------------------------
# Start llama-server
# -----------------------------

log "Starting llama-server..."

exec "${LLAMA_SERVER}" "${ARGS[@]}"