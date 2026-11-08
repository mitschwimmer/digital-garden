# Disposable Kanidm identity test

This is a deliberately non-production identity instance managed by
[Kaniop v0.21.0](https://github.com/pando85/kaniop/releases/tag/v0.21.0).
The operator is managed by Argo CD, and a single Kanidm server is pinned to
`kanidm/server:1.12.0`. The test domain `idm.localhost` is **immutable** in
Kanidm; do **not** reuse this database for a future real identity domain.

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

## 2. Create ephemeral TLS material (never commit it)

Kanidm needs a TLS certificate whose SAN matches its fixed domain. The
origin includes `8443` for local port-forward testing. There is no
public DNS, ingress, cert-manager or publicly trusted certificate yet.

From the **repository root** on the workstation:

```sh
mkdir -p .operations/kanidm-test
chmod 700 .operations/kanidm-test
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -nodes -days 14 \
  -keyout .operations/kanidm-test/tls.key \
  -out .operations/kanidm-test/tls.crt \
  -subj /CN=idm.localhost \
  -addext 'subjectAltName=DNS:idm.localhost'
chmod 600 .operations/kanidm-test/tls.key

kubectl -n identity create secret tls kanidm-test-tls \
  --cert=.operations/kanidm-test/tls.crt \
  --key=.operations/kanidm-test/tls.key
```

Store the key in the ignored `.operations` directory, never in Git.
For test certificate renewal, replace the existing Secret deliberately;
Kaniop detects TLS Secret changes and rolls the StatefulSet.

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
  --cacert .operations/kanidm-test/tls.crt \
  --resolve idm.localhost:8443:127.0.0.1 \
  https://idm.localhost:8443/
```

Check the `Kanidm` CR readiness and that the single PVC is Bound to
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
