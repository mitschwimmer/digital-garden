# Run Walter as a direct OCI application

- [Integrations and exposure](#integrations-and-exposure)
- [Prepare, deliver the secret, then start](#prepare-deliver-the-secret-then-start)
- [Fast development updates](#fast-development-updates)
- [Acceptance, updates and recovery](#acceptance-updates-and-recovery)

`systems/walter` owns one linux/amd64 OCI process and protected data/secret
volumes in the existing `ai` project. No seed, NixOS configuration or closure
deployment is involved. The image lock records the tested upstream publication
and source revision; image acceptance still requires live checks below.
The image has no shell or diagnostic utilities. Use edge or a trusted backend
for HTTP checks, and Incus console logs for startup/storage/discovery errors.

## Integrations and exposure

Edge publishes `https://walter.archaic.work`, progressively flushing SSE with a
7205-second header timeout around Walter's two-hour generation budget. Configure
public DNS for edge. There is no identity proxy. Walter enforces native OIDC,
exact Origin/CSRF checks and the `ai-users@auth.archaic.work` group SPN on every login. This reuses the
existing AI audience; membership remains owned by `directory.nix`.

`systems/identity/walter.nix` declares the confidential client only when its real
SOPS ciphertext is staged. Callback is exactly
`https://walter.archaic.work/auth/callback`. PKCE remains required; scopes are
openid/profile/groups. Kanidm's native `groups` claim contains group UUIDs and
SPNs, including `ai-users@auth.archaic.work`; match that exact SPN in Walter.
Do not map a custom `groups` claim: the native scope overwrites it.
Verify discovery at
`https://auth.archaic.work/oauth2/openid/walter/.well-known/openid-configuration`
returns the exact issuer configured in Walter. Deploy identity before starting
Walter; startup requires successful HTTPS discovery.

Walter is a trusted inference caller at
`http://garden-llama.garden.internal:8080/v1/chat/completions`. The public browser
cannot access inference directly. Only one private NIC exists, without a proxy
device or public port mapping. The intended HTTP caller is edge; trusted host
administrators and routable garden guests can also reach the backend, as for the
existing applications. Project `ai` and gardenbr0 do not enforce caller isolation.
Walter listens on IPv4 only; gardenbr0 has no IPv6 subnet and must remain private.
Verify lack of direct public IPv4/IPv6 access to Walter and inference. Stronger
separation from trusted guests needs a separate network-policy change.

## Prepare, deliver the secret, then start

Run the shared [setup](lifecycle.md#setup) and
[infrastructure](infrastructure.md) workflow. Platform must already provide `ai`
and gardenbr0. Give this root its own inspected remote/pool inputs and state.
Initial whole-plan apply uses the default `start = false`: it creates a stopped
container and both volumes, with autostart/restart disabled.

Create a new random OIDC client secret in a private operator workspace. Encrypt
JSON with the single key `walter-client` to
`systems/identity/walter-secrets.yaml` using the existing identity/recovery
recipients in `.sops.yaml`. Preserve all existing identity secrets. Follow the
shared [secret procedure](secrets.md#create-and-encrypt); verify decryption to
`/dev/null`, stage ciphertext and deploy identity. No fabricated ciphertext is
included here. The raw value in Walter must match the provisioned basic secret.

Walter needs only one startup-read secret file. Native Incus custom-volume file
transfer avoids a new guest or secret controller and keeps plaintext outside
OpenTofu state. In the private operator terminal, from the repository root:

```fish
umask 077
set -l secret_work (mktemp -d)
sops --decrypt --extract '["walter-client"]' systems/identity/walter-secrets.yaml > "$secret_work/oidc-client"
```

Require success and a nonempty file before transfer; never print it. Inspect
`systems/walter/site.auto.tfvars.json`, applied state, remote inventory and volume
identity first. Load only this root's inputs:

```fish
set -l WALTER_REMOTE (jq -r .incus_remote systems/walter/site.auto.tfvars.json)
set -l WALTER_POOL (jq -r .storage_pool systems/walter/site.auto.tfvars.json)
incus storage volume file push "$secret_work/oidc-client" "$WALTER_REMOTE:$WALTER_POOL" walter-secrets/oidc-client --project ai --uid 65532 --gid 65532 --mode 0400
```

Require a host/client supporting custom-volume file transfer. Verify the file
appears in the container at `/run/secrets/oidc-client` with mapped UID/GID 65532
and mode 0400, and the directory is 0700; do not chown raw host paths. The secret
volume is read-only in Walter. Transfer failure keeps startup disabled. Do not
use a provider `file`, environment value or local-exec provisioner for plaintext.
Remove only the operation's temporary plaintext after successful delivery and
verification; retain encrypted recovery material privately.

Inference must be healthy and advertise `qwen38-chat`. Both profiles are required
public JSON object strings in this root's local inputs: `quick_profile` and
`thoughtful_profile`. Defaults are empty preparation values and the start
precondition rejects them. Verify actual flags against the installed model and
template before supplying nonempty settings. A candidate pair for testing is
`{"reasoning_effort":"none"}` and `{"reasoning_effort":"medium"}`; these are not
accepted settings. Verify German/English answers, both thinking modes, no
reasoning tags in answer content and `reasoning_format: deepseek`. Check history
and output limits against the installed 32768-token context; bytes are not tokens.

After secret/discovery/model verification, set `start = true`, review a new whole
plan and apply it. The plan enables running/autostart/restart. OpenTofu owns this
state; do not start manually to bypass the preparation gates.

## Fast development updates

For disposable development chats, per-update backups are intentionally skipped.
Persistent volumes remain protected. In the repository's fish development shell,
authenticate GitHub CLI once with `gh auth login`. Then run:

```fish
python operations/watch_walter_image.py
```

The watcher polls Walter's latest main-push `oci.yml` run every five seconds.
It waits for a successful publication with a digest different from the current
`systems/walter/image.lock.json`, then prints only `sha256:...` to stdout and
exits. Progress goes to stderr, so stdout can be captured. Failed/cancelled
runs are reported once and the watcher waits for another push or successful
rerun. Interrupt with Ctrl-C. It uses temporary artifact downloads only; it
never edits the checkout, calls OpenTofu/Incus, stops the app or applies changes.

The `walter-image` artifact must match its run, revision, repository and platform.
Merge the artifact-producing Walter workflow first; old runs without an artifact
need a new push. Published artifacts are retained for 30 days. The shell includes
GitHub CLI. The helper is limited to polling and checking the publication record;
image/config editing and deployment remain native operator commands.

Use `--json` to print the complete published lock when updating the pin, keeping
revision and publication metadata accurate:

```fish
python operations/watch_walter_image.py --json > systems/walter/image.lock.json.tmp
and mv systems/walter/image.lock.json.tmp systems/walter/image.lock.json
```

Review the lock diff, then run `tofu apply` yourself from `systems/walter` and
review its displayed plan before confirming. An image replacement must retain
both protected volumes; do not accept volume deletion/replacement. OpenTofu
owns container replacement/startup; no preliminary stop/start configuration
cycle, identity deployment or edge deployment is needed for an image-only update.
Afterward verify readiness, re-login, streaming and an existing conversation,
then commit the image lock. The full backup/restore workflow below remains
appropriate for valuable data.

## Acceptance, updates and recovery

From edge, require bounded private readiness before browser tests:

```fish
incus exec "$WALTER_REMOTE:edge" --project default -- curl --fail --retry 15 --retry-connrefused --retry-delay 2 --connect-timeout 5 --max-time 10 --retry-max-time 90 http://walter.garden.internal:8080/healthz
incus console "$WALTER_REMOTE:walter" --project ai --show-log
```

Health proves the process only. Through public HTTPS test allowed AI-group login,
denied unrelated/missing groups, logout, secure cookies and CSRF rejection.
Verify incremental SSE, German/English output in both modes, cancellation on stop
and browser disconnect, upstream errors and two-user conversation isolation.
Restart and verify chat persistence, failed interrupted placeholders and renewed
login. Require actual offline restoration and intended network exposure before
accepting the service. Keep observations private with revision/date/environment.

For normal updates/rotation with valuable data, first set `start = false` and apply a reviewed whole plan;
require clean shutdown before touching volumes. Walter handles SIGTERM with a
20-second shutdown budget; the host timeout is 30 seconds. Retain previous image,
source/inputs and a consistent data checkpoint. Rotate both client consumers in
dependency order, transfer with the same ownership, then enable startup through
a fresh whole plan and repeat acceptance. Image changes can replace the guest;
the protected volumes must survive and remain mapped to UID/GID 65532.

`/data` is the consistency group: one writer, per-user JSON conversations, private
content. Stop cleanly before snapshot/export/copy; encrypt off-host backups and
preserve 0700/ownership. Sessions are memory-only and disposable. Preserve the
matching client ciphertext/recovery key separately; the secret volume contains
plaintext and any export must also be encrypted. A local protected volume is not
a backup. Restore data with the writer stopped, use a compatible pinned image,
restore secret delivery, then verify real conversations, user isolation and
restart persistence. An image rollback cannot undo a future data-format change.

Decommission by withdrawing the edge route and declaring the dedicated client
`present = false` in identity; retain ciphertext/data under the shared
[retirement procedure](retirement.md). Do not remove shared ai-users, inference
or the ai project. Data deletion needs its own explicit retention decision.

Upstream runtime contract:
[Walter deployment](https://github.com/mitschwimmer/walter/blob/ef189ae399bd0a1dce766042634f68bbac9ed8f9/deploy/README.md).
