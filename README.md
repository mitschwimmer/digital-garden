# Digital Garden — Talos Kubernetes rebuild

The former NixOS/Incus-container garden has been retired. This branch contains
the **first source foundation** for a single-node Talos Kubernetes cluster
on the existing IncusOS host `measerve`. The operator has applied
infrastructure, Talos and Cilium manually; no GitHub source change
deploys automatically.

## Owners

- `infrastructure/incus/`: OpenTofu owns the VM, its attached block volumes,
  guest LAN interface and optional physical AMD GPU passthrough.
- `cluster/talos/`: pinned Talos bootstrap instructions and a Cilium machine
  configuration patch. Talos-generated secrets and machine configs stay private.
- `cluster/bootstrap/cilium/`: pinned Helm values and a one-time procedure
  for bootstrapping Cilium as the sole initial CNI, before Argo CD exists.
  **Cilium v1.20.4 has not been e2e-tested with the generated Kubernetes
  v1.37.1**; see its compatibility and acceptance gate.
- **Next:** bootstrap Argo CD into the already healthy Cilium cluster, without
  requiring storage. Talos will then configure the two UserVolumes at OS level;
  **Argo CD will manage OpenEBS** and its `nvme`/`data` StorageClasses after
  disk mounts are verified. Apps, backups and Velero follow separately.

Host-managed ZFS pools `local` (Samsung NVMe) and `data` (mirrored HDDs),
the IncusOS management network and unrelated host-managed resources are never
owned by OpenTofu. The initial VM boot/installer phase has completed: Talos and Cilium are live.
The instructions below also document the original bootstrap for recovery.

Start with [Incus preflight](infrastructure/incus/README.md), then
[Talos bootstrap](cluster/talos/README.md), followed by
[Cilium bootstrap](cluster/bootstrap/cilium/README.md). Use
[the digital-garden skill](.agents/skills/digital-garden/SKILL.md)
for operational conventions and future Argo CD services.

The old NixOS service source remains accessible in Git history and the
separate `retirement/old-garden` branch. Do not apply its retired manifests.
