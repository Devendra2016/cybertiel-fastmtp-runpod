# Cyber-Tiel-Coder 35B-A3B GGUF-MTP on RunPod
#
# Runtime: official llama.cpp CUDA server image.
# The model is downloaded at container start so the image stays small.
#
# Docs:
# https://huggingface.co/peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP
# https://github.com/ggml-org/llama.cpp

FROM ghcr.io/ggml-org/llama.cpp:server-cuda

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl bash \
    && rm -rf /var/lib/apt/lists/*

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8000

ENTRYPOINT ["/start.sh"]
