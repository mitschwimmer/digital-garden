# Digital Garden — Talos Kubernetes rebuild

The former NixOS/Incus-container garden has been retired. This branch contains
the **first source-only foundation** for a single-node Talos Kubernetes cluster
on the existing IncusOS host `measerve`. Nothing is applied automatically.

## Owners

- `infrastructure/incus/`: OpenTofu owns the VM, its attached block volumes,
  guest LAN interface and optional physical AMD GPU passthrough.
- `cluster/talos/`: pinned Talos bootstrap instructions and a Cilium machine
  configuration patch. Talos-generated secrets and machine configs stay private.
- The next milestone will add Cilium, OpenEBS and Argo CD deployment source;
  applications and Velero are subsequent, separately reviewed steps.

Host-managed ZFS pools `local` (Samsung NVMe) and `data` (mirrored HDDs),
the IncusOS management network and unrelated host-managed resources are never
owned by OpenTofu. The VM is initially **stopped**. The installer must be
imported and its full boot path reviewed before starting the VM.

Start with [Incus preflight](infrastructure/incus/README.md), then
[Talos bootstrap](cluster/talos/README.md). Use
[the digital-garden skill](.agents/skills/digital-garden/SKILL.md)
for operational conventions and future Argo CD services.

The old NixOS service source remains accessible in Git history and the
separate `retirement/old-garden` branch. Do not apply its retired manifests.
