# Projects, mounts and identities

`platform/main.tf` owns gardenbr0 in default and the identity, ai, photos and inference
projects. Images, profiles and volumes are project-local; the private bridge is
shared through `features.networks=false`. Existing host pools are data sources,
not managed resources. Edge uses the built-in default project.

| Guest | Persistent paths |
|---|---|
| edge | `/var/lib/caddy` |
| identity | `/var/lib/kanidm`, `/var/lib/acme`, `/var/lib/garden-secrets` |
| open-webui | `/var/lib/open-webui`, `/var/lib/garden-secrets` |
| immich | `/var/lib/immich` on data; `/var/lib/postgresql`, `/var/lib/garden-secrets` on local |
| garden-llama | `/var/cache/llama`, read-only `/etc/llama` |

Each leaf root owns only its guest, seed (NixOS) and volumes. Guest
`user.garden.system` metadata comes from that root's `target.json`. The target
also supplies the deployment identity and required mount checks. Update target,
configuration, devices and recovery documentation together when adding a system.
Never change metadata just to make a mismatched closure pass a deployment check.

Namespaces do not isolate bridge traffic. Only trusted workloads may join this
bridge. Do not expose backend ports or Incus management publicly. A service
requiring untrusted tenants needs an explicit network/kernel isolation design.
Protected volumes survive accidental destroy attempts, but are not backups.
