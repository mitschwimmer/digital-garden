# Digital Garden — Talos Kubernetes

The former NixOS/Incus-container garden has been retired.
The current garden is a **single-node Talos Kubernetes cluster**
running in the `garden-k8s` VM on IncusOS host `measerve`
(IPv4 `192.168.1.49`). Infrastructure bootstrap is completed;
the application platform is actively operated with Argo CD Core.
See [the Digital Garden skill](.agents/skills/digital-garden/SKILL.md)
for the current operator-reported stage, boundaries, and next work.

## Current status (operator report, 2026-11-08)

| Layer | Status |
| --- | --- |
| IncusOS / OpenTofu | VM, LAN networking and separate disks live |
| Talos / Kubernetes | Talos v1.14.5, Kubernetes v1.37.1, one Ready node |
| Cilium | v1.20.4, single-node connectivity passed; Gateway API and Envoy on 80/443 |
| Argo CD | Core v3.6.1, `garden-root` and manual-sync children live |
| Storage | Talos XFS `nvme` and `data` UserVolumes; OpenEBS Local PV Hostpath v4.6.0 and mount guard working |
| Public HTTP / HTTPS | `test.archaic.work`, `secure-test.archaic.work`, Let's Encrypt HTTP-01 staging/production issuance tested |
| Identity | Kaniop v0.21.0, disposable `idm.localhost` test, newly deployed Kanidm v1.11.2 at `auth.archaic.work` via SNI TLS passthrough |
| Recovery | Kanidm off-host backup/restore and cert renewal observation **not yet accepted** |
| GPU / Kata | Additional hardware/compute/runtime acceptance pending |

The former `auth.archaic.work` Kanidm server ran outside Kubernetes
and was deleted. The Kubernetes Kanidm instance reuses its hostname
but **not its database or credentials**. The personal `henner` account
creation and login were explained in the prior session, but the
operator **has not reported whether they succeeded**.

## Ownership and GitOps

- `infrastructure/incus/`: OpenTofu owns the VM, networking and
  independent block-volume attachments. Host-managed ZFS pools and
  the IncusOS management network are **not** OpenTofu resources.
- `cluster/talos/`: Talos owns the node OS and the `nvme` /
  `data` filesystem mounts; machine keys/configs stay private.
- `cluster/bootstrap/`: pinned one-time bootstrap procedures for
  Cilium and Argo CD Core. Bootstrap recovery remains possible
  without Argo CD.
- `cluster/apps/root/`: live Argo CD root AppProject and child
  Applications. Cilium is now Argo-managed through
  `cilium-platform`; do **not** uninstall its historic Helm
  bootstrap release. Argo CD Core's own bootstrap release
  remains separate.
- `cluster/apps/`: OpenEBS, cert-manager, Gateway API,
  smoke tests, and Kanidm resources. Child syncs are manual;
  a Git commit or merge **does not automatically sync them**.

**Branch note:** The root Application and its declared children
still target `bootstrap/talos-foundation`. Merging that branch
into `main` records a stable repository baseline but **does not
automatically switch GitOps to follow `main`**. Make a separate,
reviewed change when switching the watched revision.

## Next session

1. Check whether `henner@auth.archaic.work` exists; if not,
   create it from `idm_admin` with the Kanidm CLI, generate a
   private credential setup token, and verify browser sign-in.
   Use a fresh `KANIDM_TOKEN_CACHE_PATH` for the new server.
   See [Kanidm primary runbook](cluster/apps/kanidm-primary/README.md).
2. Implement Kanidm-consistent backups **off `measerve`**
   with a tested restore and recoverable admin/Talos credentials.
   Do not treat the new identity database as durable until then.
3. Separately check Kanidm Pod-replacement persistence,
   Let's Encrypt certificate renewal, and GPU/ROCm acceptance.
   Revisit Cilium/cert-manager compatibility with Kubernetes 1.37.1.

For recovery or reconstruction start with
[Incus](infrastructure/incus/README.md),
[Talos](cluster/talos/README.md),
[Cilium](cluster/bootstrap/cilium/README.md),
and [Argo CD](cluster/bootstrap/argocd/README.md).
For the deployed public endpoints use
[Gateway smoke tests](cluster/apps/web-smoke/README.md).
The old NixOS source remains in Git history and the
`retirement/old-garden` branch; do not reapply it.
