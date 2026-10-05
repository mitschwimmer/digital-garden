#!/usr/bin/env bash
# Build declarative config with Nix, deploy to its volume, then activate upstream OCI.
set -euo pipefail
if [[ $# -ne 1 || ! $1 =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]]; then
  echo 'Usage: bash scripts/deploy-llama.sh <incus-remote-alias>' >&2
  exit 2
fi
cd "$(dirname "$0")/.."
remote=$1
[[ $(jq -er '.incus_remote' tofu/site.auto.tfvars.json) == "$remote" ]]
pool=$(jq -er '.storage_pool // "local"' tofu/site.auto.tfvars.json)
target="$remote:garden-llama"
volume=garden-llama-config
bundle=$(nix build .#llama-config --out-link result-llama-config --print-out-paths)
[[ "$bundle" == /nix/store/* ]]
incus storage volume show "$remote:$pool" "$volume" --project default >/dev/null
state=$(incus query "$remote:/1.0/instances/garden-llama/state?project=default" | jq -er '.status')
[[ "$state" == Running || "$state" == Stopped ]] || { echo "Unexpected state: $state" >&2; exit 1; }
backup=$(mktemp -d "$PWD/result-llama-rollback.XXXXXX")
previous=false
if incus storage volume file pull "$remote:$pool" "$volume/models.ini" "$backup/models.ini" --project default &&
   incus storage volume file pull "$remote:$pool" "$volume/start.sh" "$backup/start.sh" --project default; then
  previous=true
elif [[ "$state" == Running ]]; then
  echo 'Cannot back up the running service configuration; leaving it untouched.' >&2
  exit 1
fi
push_config() {
  local source=$1 file
  for file in models.ini start.sh; do
    incus storage volume file push "$source/$file" "$remote:$pool" "$volume/$file" \
      --uid 0 --gid 0 --mode 0444 --project default || return $?
  done
}
activated=false
changed=false
restore() {
  local status=$?
  trap - EXIT
  if [[ "$activated" == false && "$changed" == true ]]; then
    echo 'Activation failed; keeping the router stopped while restoring configuration.' >&2
    incus stop "$target" --project default --force >/dev/null 2>&1 || true
    if [[ "$previous" == true ]]; then
      if push_config "$backup"; then
        if [[ "$state" == Running ]]; then incus start "$target" --project default || true; fi
      else
        echo "Restore failed; router remains stopped. Retained backup: $backup" >&2
      fi
    fi
    echo "Previous files retained at: $backup" >&2
  fi
  exit "$status"
}
trap restore EXIT
if [[ "$state" == Running ]]; then incus stop "$target" --project default; fi
changed=true
push_config "$bundle"
verify=$(mktemp -d "$backup/verify.XXXXXX")
for file in models.ini start.sh; do
  incus storage volume file pull "$remote:$pool" "$volume/$file" "$verify/$file" --project default
  cmp "$bundle/$file" "$verify/$file"
done
incus start "$target" --project default
incus exec "$target" --project default -- curl --fail --silent --show-error \
  --retry 15 --retry-connrefused --retry-delay 2 --max-time 5 http://127.0.0.1:8080/health
incus exec "$target" --project default -- curl --fail --silent --show-error \
  --max-time 10 http://127.0.0.1:8080/v1/models |
  jq -e '[.data[].id] | contains(["mimo", "qwen36"])'
activated=true
if [[ "$previous" == true ]]; then printf '\nPrevious configuration for rollback: %s\n' "$backup"; fi
echo 'Upstream llama.cpp activated; model downloads remain on demand.'
