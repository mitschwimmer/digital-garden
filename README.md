# Digital Garden — Talos Kubernetes rebuild

The former NixOS/Incus-container garden has been retired. This branch contains
the **first source-only foundation** for a single-node Talos Kubernetes cluster
on the existing IncusOS host `measerve`. Nothing is applied automatically.

## Owners

- `infrastructure/incus/`: OpenTofu owns the VM, its attached block volumes,
  guest LAN interface and optional physical AMD GPU passthrough.
- `cluster/talos/`: pinned Talos bootstrap instructions and a Cilium machine
  configuration patch. Talos-generated secrets and machine configs stay private.
- `cluster/bootstrap/cilium/`: pinned Helm values and a one-time procedure
  for bootstrapping Cilium as the sole initial CNI, before Argo CD exists.
  **Cilium v1.20.4 has not been e2e-tested with the generated Kubernetes
  v1.37.1**; see its compatibility and acceptance gate.
- The next milestones are Talos UserVolumes/OpenEBS and Argo CD; applications,
  backups and Velero are subsequent, separately reviewed steps.

Host-managed ZFS pools `local` (Samsung NVMe) and `data` (mirrored HDDs),
the IncusOS management network and unrelated host-managed resources are never
owned by OpenTofu. The VM is initially **stopped**. The installer must be
imported and its full boot path reviewed before starting the VM.

Start with [Incus preflight](infrastructure/incus/README.md), then
[Talos bootstrap](cluster/talos/README.md), followed by
[Cilium bootstrap](cluster/bootstrap/cilium/README.md). Use
[the digital-garden skill](.agents/skills/digital-garden/SKILL.md)
for operational conventions and future Argo CD services.

The old NixOS service source remains accessible in Git history and the
separate `retirement/old-garden` branch. Do not apply its retired manifests.
