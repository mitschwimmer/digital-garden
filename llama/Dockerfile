FROM ghcr.io/ggml-org/llama.cpp@sha256:d67ddc789b54a48ea30d0d36bf4c5003285bd41638a330e0a5b5d24d31a2bab6

# Application configuration is immutable image content, not infrastructure state.
COPY --link --chmod=0444 models.ini /etc/llama/models.ini
ENV LLAMA_CACHE=/var/cache/llama \
    LLAMA_ARG_MODELS_PRESET=/etc/llama/models.ini \
    LLAMA_ARG_MODELS_MAX=1 \
    LLAMA_ARG_MODELS_AUTOLOAD=true \
    LLAMA_ARG_HOST=0.0.0.0 \
    LLAMA_ARG_PORT=8080 \
    LLAMA_ARG_UI=false
LABEL org.opencontainers.image.source="https://github.com/mitschwimmer/digital-garden"
USER 1000:1000
