#!/usr/bin/env bash
# Verify the real configured OCI router; production model downloads remain lazy.
set -euo pipefail
image=${1:?Pass the configured image reference}
work=$(mktemp -d)
container=
cleanup() {
  if [[ -n "$container" ]]; then docker rm -f "$container" >/dev/null; fi
  rm -rf "$work"
}
trap cleanup EXIT
container=$(docker run -d --tmpfs /var/cache/llama:uid=1000,gid=1000,mode=0750 \
  -p 127.0.0.1:18080:8080 "$image")
docker cp "$container:/etc/llama/models.ini" "$work/models.ini"
diff -u llama/models.ini "$work/models.ini"
if ! curl --fail --silent --show-error --retry 30 --retry-connrefused --retry-delay 1 \
  --connect-timeout 2 --max-time 5 http://127.0.0.1:18080/health > /dev/null; then
  docker logs "$container"
  exit 1
fi
curl --fail --silent --show-error http://127.0.0.1:18080/v1/models > "$work/models.json"
jq -e '[.data[].id] | sort == ["mimo", "qwen36"]' "$work/models.json"
curl --fail --silent --show-error http://127.0.0.1:18080/models > "$work/status.json"
jq -e '(.data | length == 2) and ([.data[].status.value] | all(. == "unloaded"))' "$work/status.json"
test -z "$(docker exec "$container" find /var/cache/llama -type f -name '*.gguf' -print)"
echo 'Image presets parsed; both models are advertised unloaded; no GGUF was downloaded.'
