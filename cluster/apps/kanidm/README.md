# Disposable Kanidm identity test

This is a deliberately non-production identity instance managed by
[Kaniop v0.21.0](https://github.com/pando85/kaniop/releases/tag/v0.21.0).
The operator is managed by Argo CD, and a single Kanidm server is pinned to
`kanidm/server:1.11.2`. The test domain `idm.localhost` is **immutable** in
Kanidm; do **not** reuse this database for a future real identity domain.

Version acceptance (observed 2026-11-08): Kaniop v0.21.0 embeds
Kanidm client SDK **v1.11.2** and rejected the initial `1.12.0` server
pin with `VersionIncompatible` / `UpgradeBlocked`. The CR remained
uninitialized (`0` replicas, no generated admin Secret). We therefore
pin the server to the published Kanidm **1.11.2** security-patch release.
Do **not** set `spec.disableUpgradeChecks: true` to work around this
contract. Inspect compatibility with the operator before any later
Kanidm upgrade; never downgrade an initialized identity database.

The root Application registers the `kaniop` and `kanidm-test` child
Applications, but neither has automated sync or pruning. It creates the
`identity` namespace under restricted Pod Security. Kaniop is installed
from the upstream **OCI Helm chart**, not its Git checkout: the published
chart packages generated CRDs. The root Application registers the public
OCI Helm repo without any credentials and permits CRDs in the `garden`
AppProject. The Kaniop Helm chart has a CRD apply hook which updates
schemas; inspect those cluster-scoped objects before approving sync.

This test uses the existing OpenEBS `nvme` StorageClass with a 2Gi RWO
PVC and `Retain`. Check that Talos `/var/mnt/k8s-nvme` is XFS and mounted
and that the OpenEBS guard is active and accepted before installation.
There is **no off-host backup or verified restore**. Treat the data and
Kaniop-generated administrator passwords as disposable; do not configure
production identities, OIDC clients, relying parties, or other workloads
to depend on this instance. Do not delete a claim/PV to clean up casually.

## 1. Operator and CRDs

From the repository root, after merging source into the tracked branch
and after the `garden-root` Application is Synced/Healthy:

```sh
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"
export TALOSCONFIG="$PWD/.operations/talos/talosconfig"
kubectl -n argocd get configmap argocd-cm
# Core CLI discovers argocd-cm using the kubeconfig context's namespace.
# This changes the workstation's default kubectl namespace to argocd.
kubectl config set-context --current --namespace=argocd
argocd login --core
kubectl -n argocd get applications kaniop kanidm-test
kubectl get ns identity
kubectl get storageclass nvme
kubectl -n openebs get deploy openebs-localpv-localpv-provisioner
```

Inspect the rendered Kaniop Helm chart (including `crdApply` hook and
cluster-scoped RBAC) before syncing. **Manually** sync `kaniop` only,
without prune, using the Argo CD Core CLI:

```sh
argocd --core app sync kaniop
kubectl -n kaniop get deployments,pods
kubectl get crd kanidms.kaniop.rs
```

Do not sync the Kanidm child until the Kaniop Deployment and the
`kanidms.kaniop.rs` CRD are ready.

## 2. Wait for cert-manager to issue the TLS certificate

No manual certificate or private key generation is needed. The independent
`cert-manager` and `identity-test-tls` Argo CD children are deliberately
**manual-sync only**. Follow [the TLS runbook](../identity-certificates/README.md)
to confirm cert-manager v1.21.3's compatibility on Kubernetes v1.37.1
(official support only covers v1.33–v1.36), then issue a disposable CA and
a leaf certificate for `idm.localhost`.

Do not sync this Kanidm child until both Certificates are Ready and the
`identity/kanidm-test-tls` Kubernetes Secret exists:

```sh
kubectl -n identity get issuers,certificates
kubectl -n identity wait --for=condition=Ready certificate/kanidm-test-ca --timeout=180s
kubectl -n identity wait --for=condition=Ready certificate/kanidm-test-tls --timeout=180s
kubectl -n identity get secret kanidm-test-tls
```

Only the public CA certificate is exported to the workstation for the
later HTTPS verification. No CA private keys or passwords belong in Git.

## 3. Manual Kanidm sync and acceptance

Only after Kaniop is ready, TLS is installed, and the OpenEBS `nvme`
mount guard is verified:

```sh
argocd --core app sync kanidm-test
kubectl -n identity get kanidm kanidm-test -o yaml
kubectl -n identity get sts,pods,pvc,svc
kubectl -n identity wait --for=condition=ready pod \
  -l kanidm.kaniop.rs/cluster=kanidm-test --timeout=300s
```

In a terminal, port-forward the internal ClusterIP Service:

```sh
kubectl -n identity port-forward service/kanidm-test 8443:8443
```

In a second terminal, use the local certificate for validation instead
of disabling certificate checks:

```sh
curl --fail --show-error \
  --cacert .operations/kanidm-test/ca.crt \
  --resolve idm.localhost:8443:127.0.0.1 \
  https://idm.localhost:8443/
```

Check the `Kanidm` CR readiness, the cert-manager Certificates' Ready
conditions, and that the single PVC is Bound to
an OpenEBS local PV on `nvme`. Kaniop bootstraps built-in admin
credentials into the `kanidm-test-admin-passwords` Kubernetes Secret;
do **not** print those credentials in shared terminal logs or issue
manual recovery commands that invalidate the operator's stored
credentials. Browser-based authentication, WebAuthn, OIDC, external
TLS/DNS and public exposure remain **out of scope**.

## Failure and future work

If the instance fails to start, check Kaniop controller and Kanidm pod
logs and the namespace's Pod Security admission events before altering
the CR. Keep both Applications manual-sync, avoid prune or PVC deletion,
and do not relax the cluster-wide PSA policy.

Before production deployment, choose a stable real DNS domain and TLS
trust chain, implement Gateway API/BackendTLSPolicy as appropriate,
establish off-host backups and tested restores, and perform both positive
and negative authentication/authorization tests. The `idm.localhost`
instance must be replaced, not repurposed.
