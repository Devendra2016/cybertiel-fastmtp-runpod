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

# Optional multimodal projector. The model card lists BF16 as the recommended
# projector for vision use. Leave empty to run text-only.
MMPROJ_FILE="${MMPROJ_FILE:-}"
MMPROJ_PATH="${MODEL_DIR}/${MMPROJ_FILE}"

# Server
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
API_KEY="${API_KEY:-}"
MODEL_ALIAS="${MODEL_ALIAS:-cyber-tiel}"

# Context / batching
CTX_SIZE="${CTX_SIZE:-262144}"
BATCH_SIZE="${BATCH_SIZE:-2048}"
UBATCH_SIZE="${UBATCH_SIZE:-512}"
PARALLEL="${PARALLEL:-1}"

# GPU / MoE
GPU_LAYERS="${GPU_LAYERS:-99}"
N_CPU_MOE="${N_CPU_MOE:-0}"

# Memory / attention
FLASH_ATTN="${FLASH_ATTN:-on}"
CACHE_TYPE_K="${CACHE_TYPE_K:-q8_0}"
CACHE_TYPE_V="${CACHE_TYPE_V:-q8_0}"

# Sampling: agentic coding defaults from the model card.
TEMP="${TEMP:-0.6}"
TOP_P="${TOP_P:-0.95}"
TOP_K="${TOP_K:-20}"
MIN_P="${MIN_P:-0}"

# Cyber/CTF profile can be selected with PROFILE=cyber.
PROFILE="${PROFILE:-coding}"

# MTP is deliberately OFF by default. Set MTP=true to enable speculative decoding.
MTP="${MTP:-false}"
MTP_N_MAX="${MTP_N_MAX:-3}"

# Download behavior
HF_TOKEN="${HF_TOKEN:-}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-false}"

# Optional extra llama-server arguments, space-separated.
EXTRA_ARGS="${EXTRA_ARGS:-}"

log() {
  echo "[cyber-tiel] $*"
}

die() {
  echo "[cyber-tiel] ERROR: $*" >&2
  exit 1
}

command -v llama-server >/dev/null 2>&1 || die "llama-server not found in base image."

mkdir -p "${MODEL_DIR}"

# Hugging Face CLI is not guaranteed in the minimal server image, so use
# the resolve endpoint directly. Xet-backed files are still served by HF.
download_hf() {
  local repo="$1"
  local filename="$2"
  local destination="$3"

  local url="https://huggingface.co/${repo}/resolve/main/${filename}?download=true"

  if [[ "${FORCE_DOWNLOAD}" != "true" && -s "${destination}" ]]; then
    log "Using existing file: ${destination}"
    return 0
  fi

  log "Downloading ${repo}/${filename}"
  log "Destination: ${destination}"

  local auth_args=()
  if [[ -n "${HF_TOKEN}" ]]; then
    auth_args=(-H "Authorization: Bearer ${HF_TOKEN}")
  fi

  curl -L --fail --retry 5 --retry-delay 3 --progress-bar \
    "${auth_args[@]}" \
    -o "${destination}.partial" \
    "${url}"

  mv "${destination}.partial" "${destination}"
}

download_hf "${MODEL_REPO}" "${MODEL_FILE}" "${MODEL_PATH}"

[[ -s "${MODEL_PATH}" ]] || die "Model download failed: ${MODEL_PATH}"

# Build sampling profile.
if [[ "${PROFILE}" == "cyber" ]]; then
  TOP_K="${CYBER_TOP_K:-40}"
  MIN_P="${CYBER_MIN_P:-0.05}"
  log "Profile: cyber/CTF (top-k=${TOP_K}, min-p=${MIN_P})"
else
  log "Profile: agentic coding (top-k=${TOP_K}, min-p=${MIN_P})"
fi

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

if [[ "${N_CPU_MOE}" != "0" ]]; then
  ARGS+=(--n-cpu-moe "${N_CPU_MOE}")
  log "CPU MoE offload: ${N_CPU_MOE}"
fi

# MTP is optional. Without --spec-type draft-mtp, the embedded MTP tensors
# are ignored by llama.cpp and the model behaves as the base model.
if [[ "${MTP,,}" == "true" || "${MTP}" == "1" || "${MTP,,}" == "yes" ]]; then
  ARGS+=(--spec-type draft-mtp --spec-draft-n-max "${MTP_N_MAX}")
  log "MTP: ENABLED (draft max=${MTP_N_MAX})"
else
  log "MTP: DISABLED"
fi

# Vision support is opt-in. Download mmproj-BF16.gguf and set:
# MMPROJ_FILE=mmproj-BF16.gguf
if [[ -n "${MMPROJ_FILE}" ]]; then
  download_hf "${MODEL_REPO}" "${MMPROJ_FILE}" "${MMPROJ_PATH}"
  [[ -s "${MMPROJ_PATH}" ]] || die "mmproj download failed: ${MMPROJ_PATH}"
  ARGS+=(--mmproj "${MMPROJ_PATH}")
  log "Vision projector: ${MMPROJ_PATH}"
fi

if [[ -n "${API_KEY}" ]]; then
  ARGS+=(--api-key "${API_KEY}")
  log "API authentication: enabled"
else
  log "API authentication: disabled"
fi

# Extra arguments are intentionally appended last so advanced users can
# override/add llama.cpp options from RunPod environment variables.
if [[ -n "${EXTRA_ARGS}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARRAY=( ${EXTRA_ARGS} )
  ARGS+=( "${EXTRA_ARRAY[@]}" )
fi

log "Model: ${MODEL_REPO}:${MODEL_FILE}"
log "Context: ${CTX_SIZE}"
log "GPU layers: ${GPU_LAYERS}"
log "Endpoint: http://${HOST}:${PORT}/v1"
log "Starting llama-server..."

exec llama-server "${ARGS[@]}"
