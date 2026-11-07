# Staged OpenEBS Local PV Hostpath (not activated)

**Status, 2026-11-07:** The operator reports both Talos XFS
UserVolumes **ready and mounted** on the intended distinct guest disks:

| Volume | Source | Actual target |
|---|---|---|
| `u-k8s-nvme` | `/dev/sdc` (128 GiB) | `/var/mnt/k8s-nvme` |
| `u-k8s-data` | `/dev/sdb` (1 TiB) | `/var/mnt/k8s-data` |

**Reboot persistence has not been confirmed.** Neither OpenEBS nor
its StorageClasses have been deployed. The staged child Application
[`../root/openebs-application.yaml`](../root/openebs-application.yaml)
is deliberately NOT included in root's `kustomization.yaml`. It has
**no automatic sync policy** even if included by mistake. Do not add it
to root or manually install the chart until the gate below is satisfied.

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
non-default. Their per-class BasePaths are
`/var/mnt/k8s-nvme/openebs` and `/var/mnt/k8s-data/openebs`.
The chart's fallback `localpv.basePath` is deliberately `/dev/null`
(a file, not a writable directory), so a class without a valid
BasePath should fail rather than select the default OS-disk location.
This **does not** protect against an unmounted `/var/mnt/k8s-*` path.

PVC size is **not a filesystem quota** unless a separately reviewed
quota configuration is enabled. `Retain` avoids automatic deletion of
data directories on PVC removal, but is not backup or restore.
One Incus VM remains a single failure domain.

## Hard prerequisites before activating

1. Verify after an **operator-approved node reboot** that both Talos
   `VolumeStatus` records are `ready`, the matching
   `MountStatus` sources are still `/dev/sdc` and `/dev/sdb`
   and filesystems `xfs`, and that Kubernetes/Cilium/Argo CD have
   recovered. A reboot interrupts the only Kubernetes node.
2. **Fail-closed provisioning is NOT solved by upstream OpenEBS.**
   Its Hostpath helper creates directories using the configured
   BasePath; when a mount disappears, writes may land on the parent
   Talos `EPHEMERAL` filesystem. The custom classes are not sufficient
   protection. Design and test an enforceable mount-source guard
   on disposable infrastructure before enabling the child. Do not
   run a missing-mount test against the current cluster.
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

## Source-only template review on the workstation

```sh
nix develop
helm repo add openebs-localpv https://openebs.github.io/dynamic-localpv-provisioner
helm repo update openebs-localpv
helm show chart openebs-localpv/localpv-provisioner --version 4.6.0
kubectl kustomize cluster/apps/openebs

mkdir -p .operations/openebs
helm template openebs-localpv openebs-localpv/localpv-provisioner \
  --version 4.6.0 --namespace openebs \
  --values cluster/apps/openebs/values.yaml \
  > .operations/openebs/rendered.yaml
```

Inspect the rendered resources before creating the child Application.
There should be no default `openebs-hostpath` StorageClass, no
additional storage engines, no Loki/Alloy, and no public API or UI.
The two custom StorageClasses are in the Kustomize output and are
not directly installed by the Helm chart. Use `kubectl` and Argo CD
`Application` CRDs for status; no OpenEBS admin UI is needed.

The exact upstream chart version and application rendering still need
to be verified on the workstation. Do not interpret source staging
as a successful Helm render or a live deployment.

Official sources:
- https://github.com/openebs/dynamic-localpv-provisioner/releases/tag/v4.6.0
- https://github.com/openebs/dynamic-localpv-provisioner/tree/v4.6.0/deploy/helm/charts
- https://openebs.io/docs/user-guides/local-storage-user-guide/local-pv-hostpath/configuration/hostpath-create-storageclass
