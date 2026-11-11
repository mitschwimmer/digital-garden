# OpenEBS admission mount-guard canary (operator only)

These are **manual Pod tests** for the staged Kubernetes native
`MutatingAdmissionPolicy`. The fixture Pods are NOT part of the
`cluster/apps/openebs/kustomization.yaml` or Argo root Application.
Neither fixture creates a PVC or writes into the data UserVolumes.

**Preconditions:** both Talos `u-k8s-data` and `u-k8s-nvme` are
`ready` and still mounted from their own XFS disks after reboot,
the Kubernetes node and Cilium are healthy, the standalone Helm chart
has rendered cleanly, and `kubectl apply --dry-run=server -f
cluster/apps/openebs/mount-guard.yaml` succeeds.

The guarded Hostpath **BasePaths are exactly the existing mount roots**:
`/var/mnt/k8s-data` and `/var/mnt/k8s-nvme`. OpenEBS will create its
PV directories as children of those roots; no initial `openebs/`
directory is required. The provisioner's init helper mounts the
BasePath as hostPath volume `data`.

## Prepare an empty test namespace, without OpenEBS

On the workstation, from repository root:

```sh
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"

# Must NOT already contain resources; inspect before changing anything.
kubectl get namespace openebs --ignore-not-found
kubectl -n openebs get all 2>/dev/null || true
```

If `openebs` already exists, inspect its contents and STOP if it is
in use by unrelated resources. Otherwise create it just for this test:

```sh
kubectl create namespace openebs
kubectl label namespace openebs \
  pod-security.kubernetes.io/enforce=privileged --overwrite

# This is a controlled, temporary cluster-wide admission policy,
# scoped by expression to openebs Pods with a data hostPath.
# There is no Helm release, controller, PVC or StorageClass yet.
kubectl apply -f cluster/apps/openebs/mount-guard.yaml
kubectl get mutatingadmissionpolicies,mutatingadmissionpolicybindings
```

## Check the API-server mutation (no Pod persisted)

```sh
kubectl create --dry-run=server -o yaml \
  -f cluster/apps/openebs/tests/guard-data-probe.yaml
kubectl create --dry-run=server -o yaml \
  -f cluster/apps/openebs/tests/guard-nvme-probe.yaml
kubectl create --dry-run=server -o yaml \
  -f cluster/apps/openebs/tests/guard-fallback-probe.yaml
```

**All three** returned Pods must contain the injected
`spec.initContainers[name=garden-mount-guard]` with mounts at
`/data`, `/expected`, and `/ephemeral`. The data probe's `garden-expected-volume` hostPath must be
`/var/mnt/k8s-data`, the NVMe probe's must be
`/var/mnt/k8s-nvme`, and the fallback probe's must be
`/var/mnt`. If a Pod lacks injection, or any mutation errors
occur, **stop and clean up**; do not use OpenEBS.

Also check that a nonmatching Pod without a `spec.volumes`
field passes dry-run, with **no** injected guard:

```sh
kubectl -n openebs run garden-guard-no-volumes --image=busybox:1.37.0 \
  --restart=Never --dry-run=server -o yaml \
  --command -- /bin/true
```

The policy match condition checks `has(object.spec.volumes)`
to avoid an unbound field error on ordinary controller Pods.

## Exercise the guard with two disposable Pods

These run **only after** the admission dry-run demonstrates mutation.

Positive: the Pod references the correctly mounted `k8s-data` root,
and both the injected initContainer and inert main container should
finish successfully.

```sh
kubectl create -f cluster/apps/openebs/tests/guard-data-probe.yaml
kubectl -n openebs wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  pod/garden-guard-data-probe --timeout=120s
kubectl -n openebs logs garden-guard-data-probe -c garden-mount-guard
kubectl -n openebs logs garden-guard-data-probe -c inert
```

Repeat the successful execution against the NVMe-backed disk:

```sh
kubectl create -f cluster/apps/openebs/tests/guard-nvme-probe.yaml
kubectl -n openebs wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  pod/garden-guard-nvme-probe --timeout=120s
kubectl -n openebs logs garden-guard-nvme-probe -c inert
```

Negative: the Pod deliberately mounts the existing `/var/mnt`
EPHEMERAL parent, **without unmounting either live disk**. The
injected initContainer must fail; its log should contain
`OpenEBS_Hostpath_mount_not_verified`. The inert main container
must **never run**.

```sh
kubectl create -f cluster/apps/openebs/tests/guard-fallback-probe.yaml
kubectl -n openebs get pod garden-guard-fallback-probe -w
# Interrupt the watch once failed; then:
kubectl -n openebs logs garden-guard-fallback-probe -c garden-mount-guard
kubectl -n openebs describe pod garden-guard-fallback-probe
```

If the negative probe succeeds, or the positive one fails for a
reason other than a transient image pull, the guard does NOT meet
the acceptance criterion. Do not install OpenEBS.

## Always remove the test resources

```sh
kubectl -n openebs delete pod \
  garden-guard-data-probe garden-guard-nvme-probe \
  garden-guard-fallback-probe \
  --ignore-not-found
kubectl delete -f cluster/apps/openebs/mount-guard.yaml
```

Delete the `openebs` namespace **only if this test created it and it
contains nothing else**:

```sh
kubectl delete namespace openebs
```

Future GitOps activation must create the policy, binding and
StorageClasses through Argo CD, not retain a competing manually
managed admission configuration. These tests prove the helper's
**creation path**, not that arbitrary privileged Pods or previously
bound local PV consumers are safe when a mount disappears.
