# Argo CD and applications

## Live ownership and bootstrap (2026-11-08)

**Argo CD Core v3.6.1** (bootstrap chart `10.14.0`) runs headless;
it has no public UI/API server, Dex or notifications. The initial
Core installation remains a **separate bootstrap Helm release**.
`garden-root` is live and reconciles the `garden` AppProject,
namespaces, source repositories, and independent manual-sync
Applications. Source manifests now target **`main`**, with the
one-time live `garden-root` revision handoff performed through the
Argo CD Core CLI; until verified, the live root may still be on the
historic `bootstrap/talos-foundation` revision.

Gateway API CRDs **v1.6.3** are Argo-owned via `gateway-api-crds`.
The initially Helm-bootstrapped **Cilium v1.20.4** release has been
adopted into Argo CD's `cilium-platform` Application. Its historic
Helm release record remains and must **not** be uninstalled. The Argo
chart reads `cluster/bootstrap/cilium/values.yaml`, preserving the
Talos-safe CNI configuration while enabling Gateway hostNetwork and
Envoy's `NET_BIND_SERVICE`. The `garden` AppProject explicitly
allows `cilium-secrets`, where Gateway secret synchronization has
Roles/RoleBindings. `cilium-platform` preserves the non-idempotent
`kube-system/cilium-ca` and `hubble-server-certs` key/certificate
data through `ignoreDifferences` and `RespectIgnoreDifferences=true`.

**No direct `kubectl apply` or `helm upgrade`** for Argo-owned
platform resources after bootstrap. Work in a Git branch, review and
merge the desired state, then *explicitly* sync the relevant Argo CD
child. Argo CD is not auto-syncing the children, and a Git merge
is not a live deployment. Bootstrap-level Talos/Incus work
remains outside Argo CD. Moving the **live** root to `main`
requires the one-time Argo CD Core CLI operation documented in
`cluster/bootstrap/argocd/README.md`. The root's automated sync
then updates the Git revision of child `Application` definitions,
but child workloads retain manual sync and no prune.

## Storage and app acceptance

The operator reports both Talos XFS UserVolumes mounted at
`/var/mnt/k8s-nvme` and `/var/mnt/k8s-data` after reboot.
OpenEBS Local PV Hostpath **v4.6.0** is live through the
`openebs-localpv` Application. The two `nvme` and `data`
StorageClasses use `WaitForFirstConsumer` and `Retain`, and
the native mount-source guard was tested including fail-closed
canaries. Operator reports initial disposable provisioning,
write/read and cross-Pod data access passed. This does not
demonstrate database persistence through Pod replacement or
off-host recovery. Some older status descriptions under
`cluster/apps/openebs/README.md` document the historical
pre-activation checks.

The root includes Kaniop **v0.21.0**, a disposable Kanidm
`identity/kanidm-test` (`idm.localhost`), cert-manager
**v1.21.3**, Cilium Gateways, ACME issuers and a new
`identity/kanidm-primary` **Kanidm v1.11.2** instance at
`auth.archaic.work`. This is a fresh database and 10Gi
`nvme` PVC, not a migration from the deleted external
Kanidm server at the same hostname. The operator reports the
new resources deployed and routing healthy, but has **not**
confirmed completion of the proposed personal `henner`
account or authentication steps. Verify with Kanidm CLI before
marking person enrollment passed.

Public tests: HTTP `test.archaic.work` on TCP/80 and HTTPS
`secure-test.archaic.work` on TCP/443, both unauthenticated.
Let's Encrypt staging and production HTTP-01 issuance passed.
The primary Kanidm is published by an SNI TLS passthrough
`TLSRoute` on port 443, while the secure smoke site continues
TLS termination at Envoy. Keep port 80 public for renewal.
Do not claim renewal has been observed until checked.

## Platform apps

Treat Kubernetes extensions (OpenEBS, Cilium, cert-manager, device plugins,
observability operators) as **API-first, headless controllers**. Do not deploy
their dashboards or public management endpoints unless a concrete requirement
is reviewed. User-facing products such as Immich are different and may
need published interfaces.

- Install OpenEBS **Local PV Hostpath only**; no replicated OpenEBS engines. Configure exactly two explicitly named classes `nvme` and `data`, each selecting its Talos user-volume base directory. Both use `WaitForFirstConsumer` and `Retain`. Avoid automatic default-class assignment until decided. A missing mount is a stop condition, not a reason to provision on the system disk.
- Install the AMD device plugin appropriate for the passed-through Radeon. Let Talos own the driver and ensure a real GPU pod completes a compute test before deploying inference workloads.
- Manage Cilium Gateway, HTTPRoutes and TLSRoutes with Gateway API. The smoke site terminates public TLS at Envoy; Kanidm uses SNI TLS passthrough to its own cert-manager-managed Secret. Preserve trustworthy forwarded headers, appropriate backend TLS, long-lived stream timeouts and explicit WebDAV LAN denial from public clients. Verify each control before public exposure.
- Use SOPS/age for encrypted secrets. Argo CD does not decrypt SOPS by default; select, pin and test a plugin/controller workflow, scope its credentials and keep recovery keys off-cluster.

## Services and acceptance

Services already introduced independently: disposable and permanent-domain Kanidm, public HTTP/HTTPS smoke sites. Later candidates include GPU inference, Walter, Immich and WebDAV. Do **not** assume migration of former identities or application data. Give each service one owner/reference documenting image/version pin, callers, native OIDC contract or exception, data StorageClass, exposed endpoints, secrets, health probes, startup conditions, restore procedure and denial tests.

Prefer standard Kubernetes resources, documented upstream charts and explicit StorageClasses. Prevent two simultaneous writers to a singleton data volume; RWO alone does not guarantee one pod. Check Argo CD sync **and** application readiness, real writes/reads, ingress policy and reboot persistence. Avoid auto-prune for data-bearing resources without reviewed safeguards.

## Operational change

Edit pinned declarative source on a branch, validate chart rendering/manifests and CI, review diff, merge and observe Argo CD reconciliation. For dangerous changes (PVCs, StorageClasses, CRDs, identity state, database major versions), require an explicit change and restore plan before sync. Record live outcomes separately from source validation.
