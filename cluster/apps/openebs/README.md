# Staged OpenEBS Local PV Hostpath (not activated)

**Status, 2026-11-07:** The operator reports both Talos XFS
UserVolumes **ready and mounted** on the intended distinct guest disks:

| Volume | Source | Actual target |
|---|---|---|
| `u-k8s-nvme` | `/dev/sdc` (128 GiB) | `/var/mnt/k8s-nvme` |
| `u-k8s-data` | `/dev/sdb` (1 TiB) | `/var/mnt/k8s-data` |

**Reboot persistence is now verified** (operator output, 2026-11-07):
both Talos volumes are still XFS on the original guest disks and mounts;
the Kubernetes node is Ready; Cilium agent/operator/Envoy are OK; and
`garden-root` remains Synced/Healthy. Neither OpenEBS nor its
StorageClasses have been deployed. The staged child Application
[`../root/openebs-application.yaml`](../root/openebs-application.yaml)
is deliberately NOT included in root's `kustomization.yaml`. It has
**no automatic sync policy** even if included by mistake. Do not add it
to root or manually install the chart until the gate below is satisfied.

## Read-only guard and chart validation

Before expanding the AppProject or including the staged child in the
root, run from the repository root in `nix develop`:

```sh
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"

# The native admission policy must be accepted by Kubernetes v1.37.
kubectl apply --dry-run=server -f cluster/apps/openebs/mount-guard.yaml

# Render all staged custom resources (guard + exactly two classes).
kubectl kustomize cluster/apps/openebs

# Confirm the independent pinned Helm chart and render controller/RBAC.
helm repo add openebs-localpv https://openebs.github.io/dynamic-localpv-provisioner
helm repo update openebs-localpv
helm show chart openebs-localpv/localpv-provisioner --version 4.6.0
mkdir -p .operations/openebs
helm template openebs-localpv openebs-localpv/localpv-provisioner \
  --version 4.6.0 --namespace openebs \
  --values cluster/apps/openebs/values.yaml \
  > .operations/openebs/rendered.yaml
```

The operator reports that the **previous** admission policy passed
`kubectl apply --dry-run=server`. Since then its match condition was
hardened to skip Pods without volumes and its BasePaths were simplified
to the existing Talos mount roots. **Repeat the dry-run against this
revision** before any live test.

A policy dry-run only checks API acceptance; it does not prove Pod
mutation. After successful chart rendering, follow the reversible
[positive and negative guard tests](tests/README.md). They temporarily
apply only the guard policy/binding (no chart, PVC, or StorageClass),
then test dry-run Pod mutation and safe one-shot Pod execution.
Remove all canary resources afterward. Do not activate the Argo child
until the tests pass; verify the *actual* OpenEBS helper later during
a sacrificial PVC provisioning test.

## Minimal components and ownership

Use standalone upstream `localpv-provisioner` chart **4.6.0** from
`https://openebs.github.io/dynamic-localpv-provisioner`, not the OpenEBS
umbrella chart (which brings extra storage engines and observability).
One controller Deployment and on-demand privileged helper Pods; no
Argo CD UI, no OpenEBS UI, no PVC for the controller, and no default
StorageClass. Chart installation belongs **only to Argo CD** (multi-source
child Application), not a separate Helm release.

The Git Kustomization defines exactly two custom classes, `nvme` and
`data`, both `WaitForFirstConsumer`, `Retain` and explicitly
non-default. Their per-class BasePaths are the already-mounted XFS roots,
`/var/mnt/k8s-nvme` and `/var/mnt/k8s-data`. The pinned provisioner
creates individual PV subdirectories beneath each BasePath, so no
bootstrap directory creation is necessary.
The chart's fallback `localpv.basePath` is deliberately `/dev/null`
(a file, not a writable directory), so a class without a valid
BasePath should fail rather than select the default OS-disk location.
This **does not** protect against an unmounted `/var/mnt/k8s-*` path.

PVC size is **not a filesystem quota** unless a separately reviewed
quota configuration is enabled. `Retain` avoids automatic deletion of
data directories on PVC removal, but is not backup or restore.
One Incus VM remains a single failure domain.

## Hard prerequisites before activating

1. **Passed:** post-reboot Talos source/target verification,
   Kubernetes node readiness, Cilium and Argo CD root health.
2. **Mount-source guard staged; NOT yet validated or enabled.** Upstream
   Hostpath helper Pods can create directories under BasePath even if
   a mount is absent. The native v1.37 Kubernetes
   [`mount-guard.yaml`](mount-guard.yaml) MutatingAdmissionPolicy
   adds a short-lived initContainer to OpenEBS helper Pods with
   a `data` hostPath in the `openebs` namespace. It recognizes **only**
   the two approved BasePaths; an unknown path deliberately maps the
   expected reference to EPHEMERAL and always fails. For approved
   paths, the initContainer checks that its `/data` bind mount's
   filesystem-device ID matches the corresponding Talos UserVolume
   mountpoint *and differs from* the Talos `/var/mnt` EPHEMERAL
   parent. A failure stops helper execution before `mkdir -p`.
   The policy skips Pods without `spec.volumes` instead of denying
   them due to a missing optional field. Policy `failurePolicy: Fail` rejects a helper
   Pod if admission evaluation fails. The guard adds no webhook or
   long-running workload; it uses `busybox:1.37.0` in a one-shot
   initContainer.
   
   **Before activation, prove** the policy is accepted by the live
   Kubernetes v1.37 API, admission mutates a representative helper Pod,
   and a sacrificial provisioning test writes to the intended disk.
   Use the safe `tests/` fixtures to test the correct data mount and
   the EPHEMERAL fallback (without unmounting either live Talos volume).
   This guard protects OpenEBS helper Pods, not arbitrary privileged
   Pods that bypass OpenEBS or all possible existing PV consumers.
3. Review namespace-scoped Pod Security: OpenEBS helper Pods require
   `privileged` in the `openebs` namespace only. The staged child
   Application uses `CreateNamespace=true` and
   `managedNamespaceMetadata` with the PSA enforce label.
   Do not weaken cluster-wide/default Pod Security.
4. Review upstream chart ClusterRole permissions: they are broad
   for namespace Pods, PVs/PVCs and storage classes. Consider
   narrowing RBAC in a separate reviewed change.
5. Only at activation time, extend the `garden` AppProject to allow
   the pinned Helm source repository, destination namespace `openebs`,
   and the minimum required cluster kinds (`Namespace`,
   `StorageClass`, `ClusterRole`, `ClusterRoleBinding`).
   Keep permissions explicit. Root currently permits only `argocd`.
6. Verify the branch in both the parent and the staged child sources
   after the PR merges; `bootstrap/talos-foundation` is transient.
   Review chart rendering and all side effects before activation.

## Final activation sequence (not yet authorized)

1. Review the guard dry-run output and rendered Helm objects.
2. Add the reviewed external Helm repo, `openebs` destination, and
   the narrowly required cluster-scoped resource kinds to `garden`
   AppProject; extend no other namespaces.
3. Add `openebs-application.yaml` to the root Kustomization, then
   verify the non-automated child Application exists. The admission
   guard has sync wave `-2`; custom StorageClasses have wave `1`.
4. Manually synchronize the child through the Argo CD Kubernetes API,
   verifying admission policy/binding and provisioner are ready
   **before any PVC is created**.
5. Perform admission-mutation and guarded provisioning smoke tests.
   Verify PV path, reclaim policy, selected disk, and real read/write
   persistence. Treat failures as blockers, not reasons to bypass
   the guard. Only then permit application workloads to claim storage.

No destructive migration, Cilium ownership change or default
StorageClass is included in this stage.

Official sources:
- https://github.com/openebs/dynamic-localpv-provisioner/releases/tag/v4.6.0
- https://github.com/openebs/dynamic-localpv-provisioner/tree/v4.6.0/deploy/helm/charts
- https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-hostpath/configuration/hostpath-create-storageclass
