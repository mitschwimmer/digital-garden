#!/usr/bin/env bash
# Run the unmodified upstream image against the Nix-built configuration volume.
set -euo pipefail
image=${1:?Pass the pinned upstream image reference}
bundle=${2:?Pass the Nix-built llama-config path}
work=$(mktemp -d)
container=
cleanup() {
  if [[ -n "$container" ]]; then docker rm -f "$container" >/dev/null; fi
  rm -rf "$work"
}
trap cleanup EXIT
container=$(docker run -d --user 1000:1000 --tmpfs /var/cache/llama:uid=1000,gid=1000,mode=0750 \
  --mount "type=bind,source=$bundle,target=/etc/llama,readonly" \
  --entrypoint /bin/sh -p 127.0.0.1:18080:8080 "$image" /etc/llama/start.sh)
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
echo 'Upstream router parsed the mounted configuration; both models advertised unloaded; no model download.'
