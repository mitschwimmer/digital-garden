#!/bin/sh
set -eu
export LLAMA_CACHE=/var/cache/llama
exec /app/llama-server \
  --models-preset /etc/llama/models.ini \
  --models-max 1 \
  --models-autoload \
  --host 0.0.0.0 \
  --port 8080 \
  --no-webui
