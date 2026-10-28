# Projects, mounts and identities

Read `platform/main.tf` for the bridge and project declarations. Images, profiles
and volumes are project-local; the private bridge is shared through
`features.networks=false`. Existing host pools are data sources, not managed
resources. Edge uses the built-in default project.

Each leaf root owns only its guest, seed (NixOS) and volumes. Resolve exact
project/instance, volume names, pools and device paths from its HCL and applied
state. For NixOS compare mounts in `target.json` with HCL devices and service-unit
mount guards. The service reference explains which paths must be backed up
together and which caches are disposable; do not duplicate the mount inventory here.

Guest `user.garden.system` metadata comes from the root's `target.json`, which
also supplies deployment identity and required mount checks. Update target,
configuration, devices and the owning service's recovery requirements together.
Compare metadata and closure identity before switching; native deployment does
not enforce their match.

Namespaces do not isolate bridge traffic. Only trusted workloads may join.
Do not expose backend ports or Incus management publicly. Untrusted tenants need
an explicit network/kernel isolation design. Require persistent mounts before
services write; do not fix ownership by chowning host volumes to raw guest UIDs.
Protected volumes survive accidental destroy attempts, but are not backups.
