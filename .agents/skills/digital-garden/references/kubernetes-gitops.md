# Argo CD and applications

## Bootstrap and ownership

Install the pinned Argo CD release only after Kubernetes and Cilium are healthy. Use local administrative access (port-forward) until the intended gateway, TLS and authentication configuration is ready. Register the Git repository and a minimal root Application that explicitly reconciles child applications. Define namespace ownership, sync waves or dependencies for CRDs/controllers before custom resources. After handoff, stop applying the same objects with ad hoc Helm/kubectl or Talos bootstrap configuration.

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
