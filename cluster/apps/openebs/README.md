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

## Canary failure and source correction (2026-11-07)

The operator confirmed the pinned Helm 4.6.0 chart renders successfully,
Kustomize emits the two non-default StorageClasses, and a previous server-side
admission dry-run accepted the policy. The policy and binding were already
**live** in Kubernetes, although OpenEBS and its StorageClasses were not.
The first three Pod admission canaries were **rejected** with:

```text
invalid ApplyConfiguration: may not mutate atomic arrays, maps or structs:
.spec.initContainers[0].command, .spec.initContainers[0].args
```

The policy's ApplyConfiguration attempted to add an initContainer with
atomic `command` and `args` fields. The staged source now retains the
volume ApplyConfiguration mutation but uses a separate `JSONPatch` to add
the complete initContainer. It handles Pods with and without an existing
`initContainers` list. Reinvocation is set to `Never` to avoid duplicate
appends. The correction was subsequently validated and applied, and the three
canaries passed as recorded below. Keep OpenEBS inactive pending GitOps
activation and a real helper provisioning test.

From the updated branch on the workstation, first review the exact diff,
then check API acceptance without changing live state:

```sh
kubectl apply --dry-run=server -f cluster/apps/openebs/mount-guard.yaml
```

If accepted, compare live policy to source and deliberately update only the
admission policy/binding with `kubectl apply -f
cluster/apps/openebs/mount-guard.yaml`. This affects cluster-wide Pod
admission (matching only the `openebs` namespace helper signature), so
inspect for unexpected OpenEBS workloads before doing so. Repeat all three
`kubectl create --dry-run=server -o yaml` canary checks and confirm the
injected guard and correct expected mount paths; do not execute test Pods
until their mutation works. The unguarded control Pod had no injected guard;
its restricted Pod Security warnings are separate and do not prove guard
functionality. The namespace enforces `privileged` for this Hostpath helper use case;
independent `restricted:latest` Pod Security warnings do not block the tests.

## Admission guard live acceptance (operator output, 2026-11-07)

After the JSONPatch correction, the operator confirmed:

- `kubectl apply --dry-run=server` accepted the policy and binding; the
  corrected policy was subsequently applied to the live Kubernetes API.
- All three `kubectl create --dry-run=server -o yaml` probes succeeded with
  `garden-mount-guard` injected; expected hostPath references resolved to
  the `k8s-data` and `k8s-nvme` Talos XFS mounts and `/var/mnt` for
  the fallback. A nonmatching Pod had no injected guard.
- Talos still reported both UserVolumes `ready`, mounted as XFS on
  `/dev/sdb` and `/dev/sdc`; EPHEMERAL remained on `/dev/sda4`.
- Both positive executable canaries ended `Completed` with zero restarts.
- The fallback executable canary's `garden-mount-guard` initContainer
  terminated `Error` (exit code 1). Its `inert` main container remained
  `Waiting: PodInitializing` with no container ID, confirming fail-closed
  behavior. The operator's initial log request raced Pod initialization;
  the guard's exact diagnostic log line has not been independently copied.
- The `openebs` namespace had `pod-security.kubernetes.io/enforce=privileged`.
  `restricted:latest` warnings were emitted independently, without blocking
  the canaries; inspect PSA warn/audit settings separately if relevant.

**Cleanup confirmed by operator output:** no resources were reported in
the `openebs` namespace, no StorageClasses were present, and `garden-root`
remained Synced/Healthy. The preceding admission policy/binding
`--ignore-not-found` commands returned no resource records, consistent with
removal of the temporary manually managed guard. The exact fallback guard
log line has not been copied. OpenEBS remains **not activated**: GitOps
AppProject permissions, chart deployment, actual helper Pod injection, and
sacrificial PVC write/read checks are still pending. This canary establishes
mount protection for the tested helper signature, not universal hostPath
protection or existing PV consumer recovery.

## Prepared GitOps activation branch (not deployed)

The isolated `prepare/openebs-gitops-activation` branch stages two changes
relative to `bootstrap/talos-foundation`:

- `cluster/apps/root/project.yaml` allows only the existing garden Git
  repository and pinned OpenEBS Helm repository, destination namespaces
  `argocd` and `openebs`, and the reviewed cluster-scoped resource kinds.
  The AppProject sync wave is `-1` so it precedes child Application creation.
- `cluster/apps/root/kustomization.yaml` includes the already prepared
  `openebs-application.yaml`. The child **has no automated sync**; the
  root Application does auto-sync from `bootstrap/talos-foundation`, so
  these source changes must not be merged into that watched branch until
  preconditions are checked.

**Before merging/activating** inspect the live cluster, because the operator
has not yet reported actual test cleanup. From the workstation:

```sh
kubectl -n openebs get pods,deployments,daemonsets,jobs,pvc
kubectl get storageclasses
kubectl get mutatingadmissionpolicy garden-openebs-mount-guard --ignore-not-found
kubectl get mutatingadmissionpolicybinding garden-openebs-mount-guard --ignore-not-found
kubectl -n argocd get applications
kubectl -n argocd get appproject garden -o yaml
kubectl get namespace openebs --show-labels
```

Expect no canary Pods, no controller, no PVC, no StorageClass, and
no manually owned guard objects after cleanup. If any remain, inspect
their ownership; do not delete unexpected resources. Reconfirm both
Talos mount sources and node readiness before allowing provisioning.
Review `.operations/openebs/rendered.yaml` for all chart API groups/kinds,
RBAC, and actual helper Pod naming/volume shape; add only documented
missing permissions if a rendered resource genuinely needs them.
Inspect chart and Kustomize output together for duplicate resources.

After reviewing/merging the activation changes into the **watched** branch,
the self-syncing `garden-root` can create `openebs-localpv` and update
the `garden` AppProject. Confirm root reconciliation and that the child
Application is present but **not synchronized**. Then explicitly approve
and request the first **manual** child synchronization via Kubernetes
Application API. Inspect health, admission mutation on the actual helper,
PVC/PV disk paths, and disposable write/read tests before using persistent
workloads. Avoid broad auto-prune, and never use Helm independently to
deploy the same release. Leave GPU, Cilium ownership, and default
StorageClass unchanged.

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
   `StorageClass`, `ClusterRole`, `ClusterRoleBinding`,
   `MutatingAdmissionPolicy`, `MutatingAdmissionPolicyBinding`).
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
