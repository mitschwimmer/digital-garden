# Argo CD and applications

## Bootstrap and ownership

Install a **pinned, non-HA Argo CD bootstrap** after Kubernetes,
Cilium and DNS are healthy; do **not** wait for OpenEBS. The normal
Argo CD installation does not need a PersistentVolumeClaim: Kubernetes
resources hold its configuration, and its Redis instance is a cache.
Use local administrative access (port-forward or core CLI) until
gateway, TLS and identity integration exist. Register the Git repository
and a minimal root Application that explicitly reconciles child apps.
Prefer Argo CD as owner of OpenEBS, not a one-off Helm release that must
later be adopted. Talos must create/verify the two UserVolumes via
its own machine configuration **outside Argo CD** before an OpenEBS
Application is allowed to provision. Define namespace ownership, sync
waves and dependencies for CRDs/controllers before custom resources.
Keep the working bootstrap Cilium release Helm-owned until a separately
reviewed takeover; avoid competing Helm/Argo CD controllers.

Keep the desired-state layout small: `infrastructure/incus` for OpenTofu, `cluster/talos` and `cluster/bootstrap` for pre-GitOps sources, `cluster/apps` for Argo CD-managed platform and service resources. Source paths are a *target design*, not proof that they exist yet. Do not read the former NixOS `systems/*` HCL as current infrastructure.

## Platform apps

- Install OpenEBS **Local PV Hostpath only**; no replicated OpenEBS engines. Configure exactly two explicitly named classes `nvme` and `data`, each selecting its Talos user-volume base directory. Both use `WaitForFirstConsumer` and `Retain`. Avoid automatic default-class assignment until decided. A missing mount is a stop condition, not a reason to provision on the system disk.
- Install the AMD device plugin appropriate for the passed-through Radeon. Let Talos own the driver and ensure a real GPU pod completes a compute test before deploying inference workloads.
- Manage Cilium Gateway and HTTPRoutes with Gateway API; terminate public TLS with cert-manager-managed Secrets. Preserve trustworthy forwarded headers, appropriate backend TLS, long-lived stream timeouts and explicit WebDAV LAN denial from public clients. Verify each control before public exposure.
- Use SOPS/age for encrypted secrets. Argo CD does not decrypt SOPS by default; select, pin and test a plugin/controller workflow, scope its credentials and keep recovery keys off-cluster.

## Services and acceptance

Introduce services independently (proposed: test app, Kanidm, GPU inference, Walter, Immich, WebDAV). This is a fresh installation: do **not** assume migration of previous state or identities. Give each service one owner/reference documenting image/version pin, callers, native OIDC contract or exception, data StorageClass, exposed endpoints, secrets, health probes, startup conditions, restore procedure and denial tests.

Prefer standard Kubernetes resources, documented upstream charts and explicit StorageClasses. Prevent two simultaneous writers to a singleton data volume; RWO alone does not guarantee one pod. Check Argo CD sync **and** application readiness, real writes/reads, ingress policy and reboot persistence. Avoid auto-prune for data-bearing resources without reviewed safeguards.

## Operational change

Edit pinned declarative source on a branch, validate chart rendering/manifests and CI, review diff, merge and observe Argo CD reconciliation. For dangerous changes (PVCs, StorageClasses, CRDs, identity state, database major versions), require an explicit change and restore plan before sync. Record live outcomes separately from source validation.
