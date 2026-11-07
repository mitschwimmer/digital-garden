# Argo CD and applications

## Bootstrap and ownership

Install pinned, non-HA **Argo CD Core v3.6.1** (argo-helm
chart `10.14.0`) after Kubernetes, Cilium and DNS are healthy;
do **not** wait for OpenEBS. Follow
`cluster/bootstrap/argocd/README.md` for exact Helm and Kubernetes
API commands. Use the upstream Core chart settings: disable
`server`, `dex` and `notifications`. Never expose an Argo CD
web UI/API server, route, ingress, OIDC client, or unnecessary admin
dashboard: **the operator manages GitOps through `Application` and
`ApplicationSet` CRDs via Kubernetes RBAC/`kubectl` only**.

The initial Core installation does not need a PVC; Redis is a cache.
Keep the Argo CD Core Helm release independent from the root Application,
which initially manages only a reviewed `garden` AppProject, not child
applications or Cilium. Add each platform extension as a child Application
only after validating its prerequisites. Prefer Argo CD as the owner of
OpenEBS, not a separate manual Helm release. Talos must first create and
verify both UserVolumes through its own machine configuration, outside
Argo CD. Define namespace ownership and ordered dependencies for
CRDs/controllers before custom resources. Keep Cilium Helm-owned until
a separately reviewed handoff, not a blind uninstall.

Keep the desired-state layout small: `infrastructure/incus` for OpenTofu, `cluster/talos` and `cluster/bootstrap` for pre-GitOps sources, `cluster/apps` for Argo CD-managed platform and service resources. Source paths are a *target design*, not proof that they exist yet. Do not read the former NixOS `systems/*` HCL as current infrastructure.

## Storage gate (2026-11-07)

Talos reports both dedicated XFS UserVolumes ready and mounted at
`/var/mnt/k8s-nvme` and `/var/mnt/k8s-data`. The root Application
remains minimal. Standalone OpenEBS LocalPV Hostpath v4.6.0 sources
are **staged only** under `cluster/apps/openebs`, and its child
Application is **not included** in `cluster/apps/root/kustomization.yaml`.
No storage provisioning is activated. Before connecting it, verify
Talos mounts across a separately approved reboot and implement/test
a fail-closed guard against writes to the Talos system disk if a
mount disappears. OpenEBS Hostpath's BasePath settings alone do not
provide that guarantee. Follow `cluster/apps/openebs/README.md`.

## Platform apps

Treat Kubernetes extensions (OpenEBS, Cilium, cert-manager, device plugins,
observability operators) as **API-first, headless controllers**. Do not deploy
their dashboards or public management endpoints unless a concrete requirement
is reviewed. User-facing products such as Immich are different and may
need published interfaces.

- Install OpenEBS **Local PV Hostpath only**; no replicated OpenEBS engines. Configure exactly two explicitly named classes `nvme` and `data`, each selecting its Talos user-volume base directory. Both use `WaitForFirstConsumer` and `Retain`. Avoid automatic default-class assignment until decided. A missing mount is a stop condition, not a reason to provision on the system disk.
- Install the AMD device plugin appropriate for the passed-through Radeon. Let Talos own the driver and ensure a real GPU pod completes a compute test before deploying inference workloads.
- Manage Cilium Gateway and HTTPRoutes with Gateway API; terminate public TLS with cert-manager-managed Secrets. Preserve trustworthy forwarded headers, appropriate backend TLS, long-lived stream timeouts and explicit WebDAV LAN denial from public clients. Verify each control before public exposure.
- Use SOPS/age for encrypted secrets. Argo CD does not decrypt SOPS by default; select, pin and test a plugin/controller workflow, scope its credentials and keep recovery keys off-cluster.

## Services and acceptance

Introduce services independently (proposed: test app, Kanidm, GPU inference, Walter, Immich, WebDAV). This is a fresh installation: do **not** assume migration of previous state or identities. Give each service one owner/reference documenting image/version pin, callers, native OIDC contract or exception, data StorageClass, exposed endpoints, secrets, health probes, startup conditions, restore procedure and denial tests.

Prefer standard Kubernetes resources, documented upstream charts and explicit StorageClasses. Prevent two simultaneous writers to a singleton data volume; RWO alone does not guarantee one pod. Check Argo CD sync **and** application readiness, real writes/reads, ingress policy and reboot persistence. Avoid auto-prune for data-bearing resources without reviewed safeguards.

## Operational change

Edit pinned declarative source on a branch, validate chart rendering/manifests and CI, review diff, merge and observe Argo CD reconciliation. For dangerous changes (PVCs, StorageClasses, CRDs, identity state, database major versions), require an explicit change and restore plan before sync. Record live outcomes separately from source validation.
