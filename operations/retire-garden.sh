#!/usr/bin/env bash
# Deliberate, state-scoped retirement of the former Incus digital garden.
# No Incus storage pool or untracked resource is ever deleted by this script.
set -Eeuo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage:
  operations/retire-garden.sh inspect REMOTE
  operations/retire-garden.sh plan REMOTE
  operations/retire-garden.sh apply REMOTE PLAN_DIRECTORY

Run from the existing workstation checkout, inside `nix develop`, with each
root's original local OpenTofu state and site.auto.tfvars.json present.
Use branch retirement/old-garden (which intentionally disables prevent_destroy).

`inspect` only reads Incus and OpenTofu state. `plan` writes saved destroy plans
under .operations/retirement/ but changes nothing on measerve. Inspect *all*
plan files before running `apply`. `apply` asks for a separate typed confirmation
before applying each root's exact saved plan. All old application data, including
volume snapshots, may be irreversibly destroyed. Host storage pools are retained.
USAGE
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
notice() { printf '\n== %s ==\n' "$*"; }

(( $# >= 2 && $# <= 3 )) || { usage; exit 2; }
mode=$1
remote=$2
[[ $mode == inspect || $mode == plan || $mode == apply ]] || { usage; exit 2; }
[[ $remote =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || die 'Invalid Incus remote alias.'
[[ $mode != apply || $# == 3 ]] || { usage; exit 2; }
[[ $mode == apply || $# == 2 ]] || { usage; exit 2; }

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
roots=(systems/walter systems/webdav systems/immich systems/identity systems/edge platform)

for command in incus tofu jq git sha256sum; do
  command -v "$command" >/dev/null || die "Required command missing: $command (run nix develop)."
done
# Never let hidden TF_* settings redirect the backend or working state.
if env | grep '^TF_' >/dev/null; then die 'Unset TF_* environment overrides before retirement.'; fi

# Verify that the Incus remote resolves to the intended physical machine.
incus info "${remote}:" --project default >/dev/null || die "Cannot connect to Incus remote $remote."
server=$(incus query "${remote}:/1.0" | jq -r '.metadata.environment.server_name // .environment.server_name // empty')
if [[ -n $server && $server != measerve ]]; then
  die "Remote $remote identifies as $server, not measerve."
fi
printf 'Incus remote: %s; reported server name: %s\n' "$remote" "${server:-unavailable (verify manually)}"

expected_addresses() {
  case "$1" in
    systems/walter) printf '%s\n' incus_instance.walter incus_storage_volume.data incus_storage_volume.secrets ;;
    systems/webdav) printf '%s\n' incus_instance.webdav incus_image.seed incus_storage_volume.webdav incus_storage_volume.webdav_secrets ;;
    systems/immich) printf '%s\n' incus_instance.immich incus_image.seed incus_storage_volume.immich incus_storage_volume.immich_secrets incus_storage_volume.database ;;
    systems/identity) printf '%s\n' incus_instance.identity incus_image.seed incus_storage_volume.identity incus_storage_volume.identity_secrets incus_storage_volume.acme ;;
    systems/edge) printf '%s\n' incus_instance.edge incus_image.seed incus_storage_volume.caddy ;;
    platform) printf '%s\n' incus_network.private incus_project.ai incus_project.identity incus_project.photos incus_project.webdav ;;
    *) die "Unknown root: $1" ;;
  esac
}

check_source() {
  [[ $(git -C "$repo" branch --show-current) == retirement/old-garden ]] ||
    die 'Plan/apply requires branch retirement/old-garden.'
  git -C "$repo" diff --quiet && git -C "$repo" diff --cached --quiet ||
    die 'Tracked files differ from the committed retirement branch.'
}

check_root() {
  local root=$1 address inputs configured_remote state
  inputs="$repo/$root/site.auto.tfvars.json"
  [[ -f $inputs ]] || die "Missing $inputs. Use the original workstation checkout."
  configured_remote=$(jq -er '.incus_remote | select(type == "string")' "$inputs") ||
    die "No incus_remote in $inputs"
  [[ $configured_remote == "$remote" ]] || die "$root points to $configured_remote, not $remote"
  if grep -Eq 'prevent_destroy[[:space:]]*=[[:space:]]*true' "$repo/$root/"*.tf; then
    die "$root still protects volumes. Use the reviewed retirement branch."
  fi
  tofu -chdir="$repo/$root" init -input=false -lockfile=readonly >/dev/null
  [[ $(tofu -chdir="$repo/$root" workspace show) == default ]] ||
    die "$root has a non-default OpenTofu workspace."
  local snapshot
  if ! snapshot=$(tofu -chdir="$repo/$root" state pull); then
    die "$root state snapshot is unavailable. Do not assume resources are absent."
  fi
  printf '%s\n' "$snapshot" | jq -e '(.lineage | type == "string") and (.resources | type == "array")' >/dev/null ||
    die "$root has no verifiable existing OpenTofu state snapshot."
  if ! state=$(tofu -chdir="$repo/$root" state list); then
    die "$root state is unavailable. Do not assume resources are absent."
  fi
  while IFS= read -r address; do
    [[ -z $address || $address == data.* ]] && continue
    if ! expected_addresses "$root" | grep -Fxq -- "$address"; then
      die "$root contains unexpected managed state: $address"
    fi
  done <<< "$state"
  printf '%s\n' "$state"
}

inventory() {
  notice 'Host inventory (read-only)'
  incus list "${remote}:" --all-projects
  incus project list "${remote}:"
  incus network list "${remote}:" --project default
  incus storage list "${remote}:"
  # Incus pool names are host-owned; list volumes without deleting pools.
  local pool
  while IFS= read -r pool; do
    [[ -n $pool ]] || continue
    printf '\nStorage volumes in pool %s:\n' "$pool"
    incus storage volume list "${remote}:${pool}" --all-projects
  done < <(incus storage list "${remote}:" --format=json | jq -r '.[].name')
}

if [[ $mode == inspect ]]; then
  inventory
  for root in "${roots[@]}"; do
    notice "Managed state: $root"
    (cd "$repo/$root" && tofu state list) || die "Cannot read state for $root"
  done
  exit 0
fi

check_source
revision=$(git -C "$repo" rev-parse HEAD)
base="$repo/.operations/retirement"

if [[ $mode == plan ]]; then
  inventory
  mkdir -p -- "$base"
  report=$(mktemp -d "$base/plans.XXXXXXXX")
  printf '%s\n%s\n' "$remote" "$revision" > "$report/context.txt"
  for root in "${roots[@]}"; do
    notice "Plan destroy: $root"
    slug=${root//\//-}
    state=$(check_root "$root")
    # A fully retired root has no managed objects left; report this explicitly.
    managed=$(printf '%s\n' "$state" | grep -v '^data\.' | sed '/^$/d' || true)
    if [[ -z $managed ]]; then
      printf 'No managed resources in %s state. Verify host inventory.\n' "$root"
      : > "$report/$slug.empty"
      continue
    fi
    plan="$report/$slug.tfplan"
    tofu -chdir="$repo/$root" plan -destroy -input=false -out="$plan"
    tofu -chdir="$repo/$root" show -no-color "$plan" > "$report/$slug.plan.txt"
    tofu -chdir="$repo/$root" show -json "$plan" | jq -r '
      .resource_changes[]? | select(.mode == "managed") |
      [.address, (.change.actions | join(",")), (.change.before.remote // "")] | @tsv
    ' > "$report/$slug.actions.tsv"
    [[ -s "$report/$slug.actions.tsv" ]] || die "Empty destroy plan for $root with live state."
    while IFS=$'\t' read -r address actions planned_remote; do
      [[ $actions == delete ]] || die "Unexpected action $actions for $address ($root)"
      [[ $planned_remote == "$remote" ]] || die "Wrong/missing remote in plan for $address"
      expected_addresses "$root" | grep -Fxq -- "$address" || die "Unexpected resource in plan: $address"
    done < "$report/$slug.actions.tsv"
    planned=$(cut -f1 "$report/$slug.actions.tsv" | sort)
    tracked=$(printf '%s\n' "$managed" | sort)
    [[ $planned == "$tracked" ]] || die "Plan/state resource mismatch in $root"
    sha256sum "$plan" | awk '{print $1}' > "$report/$slug.sha256"
    cat "$report/$slug.actions.tsv"
    printf 'Full review: %s\n' "$report/$slug.plan.txt"
  done
  printf '\nReview every saved plan. To apply, run:\n  %q apply %q %q\n' \
    "$repo/operations/retire-garden.sh" "$remote" "$report"
  exit 0
fi

[[ -t 0 ]] || die 'Apply needs an interactive terminal.'
report=$(realpath -e -- "$3")
[[ $report == "$base"/plans.* ]] || die "Plan directory must be below $base"
[[ $(sed -n '1p' "$report/context.txt") == "$remote" ]] || die 'Plan remote differs.'
[[ $(sed -n '2p' "$report/context.txt") == "$revision" ]] || die 'Plan was prepared from a different commit.'
# Preflight every root and verify every saved plan BEFORE the first deletion.
for root in "${roots[@]}"; do
  slug=${root//\//-}
  state=$(check_root "$root")
  managed=$(printf '%s\n' "$state" | grep -v '^data\.' | sed '/^$/d' || true)
  if [[ -f $report/$slug.applied || -f $report/$slug.empty ]]; then
    [[ -z $managed ]] || die "$root changed since planning (was marked empty/applied)."
    continue
  fi
  plan="$report/$slug.tfplan"
  [[ -f $plan && -f $report/$slug.sha256 && -f $report/$slug.actions.tsv ]] ||
    die "Missing plan or summary for $root."
  [[ $(cat "$report/$slug.sha256") == $(sha256sum "$plan" | awk '{print $1}') ]] ||
    die "Plan checksum changed for $root."
  actions=$(tofu -chdir="$repo/$root" show -json "$plan" | jq -r '
    .resource_changes[]? | select(.mode == "managed") |
    [.address, (.change.actions | join(",")), (.change.before.remote // "")] | @tsv
  ')
  [[ $actions == "$(cat "$report/$slug.actions.tsv")" ]] ||
    die "Plan summary mismatch for $root."
  [[ -n $actions ]] || die "Saved plan is empty for $root."
  while IFS=$'\t' read -r address operation planned_remote; do
    [[ $operation == delete && $planned_remote == "$remote" ]] ||
      die "Unexpected saved action or remote for $address."
    expected_addresses "$root" | grep -Fxq -- "$address" ||
      die "Unexpected resource in saved plan: $address"
  done <<< "$actions"
  [[ $(printf '%s\n' "$actions" | cut -f1 | sort) == $(printf '%s\n' "$managed" | sort) ]] ||
    die "State/plan mismatch for $root."
done
notice 'Final safety gate'
printf 'All old digital-garden services and protected volumes will be deleted.\n'
printf 'Retained: IncusOS, measerve host network and ALL existing storage pools.\n'
printf 'Disable public router forwarding and confirm the remote above before proceeding.\n'
read -r -p "Type 'RETIRE digital-garden on measerve' to continue: " response
[[ $response == 'RETIRE digital-garden on measerve' ]] || die 'Not confirmed.'

for root in "${roots[@]}"; do
  notice "Destroy: $root"
  slug=${root//\//-}
  if [[ -f $report/$slug.applied ]]; then
    printf 'Already applied in this run; checking empty state.\n'
    state=$(check_root "$root")
    [[ -z $(printf '%s\n' "$state" | grep -v '^data\.' | sed '/^$/d') ]] || die "$root still has managed state."
    continue
  fi
  state=$(check_root "$root")
  if [[ -f $report/$slug.empty ]]; then
    [[ -z $(printf '%s\n' "$state" | grep -v '^data\.' | sed '/^$/d') ]] || die "$root became nonempty. Re-plan."
    continue
  fi
  plan="$report/$slug.tfplan"
  [[ -f $plan && -f $report/$slug.sha256 ]] || die "Missing saved plan for $root."
  expected_sha=$(cat "$report/$slug.sha256")
  actual_sha=$(sha256sum "$plan" | awk '{print $1}')
  [[ $expected_sha == "$actual_sha" ]] || die "Plan checksum changed for $root."
  cat "$report/$slug.actions.tsv"
  printf 'Review the full plan at %s\n' "$report/$slug.plan.txt"
  read -r -p "Type 'delete $root' to apply this saved plan: " response
  [[ $response == "delete $root" ]] || die "Stopped before deleting $root."
  tofu -chdir="$repo/$root" apply -input=false "$plan"
  state=$(check_root "$root")
  [[ -z $(printf '%s\n' "$state" | grep -v '^data\.' | sed '/^$/d') ]] ||
    die "Managed state remains in $root; investigate before continuing."
  : > "$report/$slug.applied"
done
notice 'Post-retirement inventory (inspect manually for unmanaged leftovers)'
inventory
printf '\nAll planned roots processed. Storage pools were never targeted.\n'
