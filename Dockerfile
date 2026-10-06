FROM ghcr.io/ggml-org/llama.cpp:server-cuda

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

RUN test -x /app/llama-server

COPY start.sh /start.sh

RUN chmod +x /start.sh

EXPOSE 8000

ENTRYPOINT ["/start.sh"]