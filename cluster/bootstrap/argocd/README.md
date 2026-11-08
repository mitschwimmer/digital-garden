# Argo CD Core bootstrap (Kubernetes API only)

The Garden uses **Argo CD Core**: no Argo CD API server, web UI, Dex,
notifications, ingress or HTTPRoute. Reconcile via Kubernetes
`Application` and `ApplicationSet` CRDs with `kubectl`.
This is also the default for other cluster-platform extensions:
do not install or publish a UI unless it serves an explicit
end-user/operator requirement.

Pinned releases:
- argo-helm chart: **`argo-cd` 10.14.0**
- chart application: **Argo CD v3.6.1**
- workstation `argocd` Core CLI: **v3.6.1**, pinned in `flake.nix`

The development shell includes the matching Argo CD CLI. Use `--core` so
it talks directly to the Kubernetes API: this installation has no Argo CD
API server. From the repository root, enter `nix develop`, set
`KUBECONFIG="$PWD/.operations/talos/kubeconfig"` and verify the client with
`argocd version --client`. A manual child Application sync uses
`argocd --core app sync <application-name>`; do not enable automatic sync
or pruning to compensate for a missing CLI.


This is a single-node, non-HA deployment on the existing Kubernetes
v1.37.1 cluster. Upstream confirms these Helm values implement Core mode.
The bootstrap Helm release remains managed **only by Helm**, not by the
root Application. The currently running Cilium 1.20.4 Helm release
is **not** included in Argo CD's desired state.

Official source:
- https://github.com/argoproj/argo-helm/tree/argo-cd-10.14.0/charts/argo-cd
- https://argo-cd.readthedocs.io/en/stable/operator-manual/core/

## Preflight

From the repository root in `nix develop` on the workstation:

```sh
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"

kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
cilium status --wait
helm list -A
kubectl get ns argocd --ignore-not-found
```

**Stop** if the node or Cilium are unhealthy, Kubernetes API access fails,
or a different Argo CD installation or release already exists. No
StorageClass is necessary for Argo CD Core.

## Render and install

```sh
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
helm show chart argo/argo-cd --version 10.14.0

mkdir -p .operations/argocd
helm template argocd argo/argo-cd \
  --version 10.14.0 \
  --namespace argocd \
  --include-crds \
  --values cluster/bootstrap/argocd/values.yaml \
  > .operations/argocd/rendered.yaml

# Inspect first: NO argocd-server Deployment/Service,
# Ingress, HTTPRoute, NodePort/LoadBalancer or PersistentVolumeClaim.
# The render is local ignored operator state.
```

Only after reviewing the rendering, create **one** Helm release:

```sh
helm install argocd argo/argo-cd \
  --version 10.14.0 \
  --namespace argocd \
  --create-namespace \
  --values cluster/bootstrap/argocd/values.yaml \
  --wait --timeout 10m
```

If the installation times out, inspect the existing release and events.
Do not install another copy or repeatedly run `helm install`.
Core keeps the application controller, repo server, Redis (cache), and
ApplicationSet controller. They use standard Kubernetes resources;
Argo CD does not need a PVC or a dedicated UI/API service.

## Kubernetes API acceptance

```sh
helm -n argocd status argocd
kubectl -n argocd get pods -o wide
kubectl -n argocd get deployments,statefulsets,services
kubectl get crd applications.argoproj.io appprojects.argoproj.io
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=5m
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5m
```

Confirm the server Deployment and Service are **absent**:

```sh
kubectl -n argocd get deployment argocd-server --ignore-not-found
kubectl -n argocd get service argocd-server --ignore-not-found
```

Both commands should print nothing. Do not expose any Argo CD admin
endpoint, and do not add an OIDC client just for this headless controller.

## Minimal GitOps root

Argo CD Core can have **no `default` AppProject** after its Helm
bootstrap: the `argocd-server` is disabled. Do not create a root
Application referring to a nonexistent project; it will remain
`InvalidSpecError` before fetching Git.

Bootstrap the explicit `garden` AppProject through the Kubernetes API
**first**, then the root Application referencing it. Once healthy, the root
tracks `cluster/apps/root/` and takes over reconciliation of the *same*
`garden` AppProject. This is a deliberate, one-time project seed, not
a separate long-term resource owner.

The initial `garden` AppProject allows only this repository and the
`argocd` namespace, with **no cluster-scoped resource privileges**.
No child Application, OpenEBS, StorageClass or workload is included.
Expand these permissions only for separately reviewed child Applications.

```sh
kubectl kustomize cluster/apps/root
kubectl apply --dry-run=server -f cluster/apps/root/project.yaml
kubectl apply -f cluster/apps/root/project.yaml
kubectl apply -f cluster/bootstrap/argocd/root-application.yaml

kubectl -n argocd get appprojects.argoproj.io
kubectl -n argocd get applications.argoproj.io -o wide
kubectl -n argocd describe application garden-root
kubectl -n argocd get application garden-root \
  -o jsonpath='{.spec.project}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}'
```

If an earlier root Application used `project: default`, it is safe to
apply the revised root manifest again; verify `spec.project=garden`
and the appearance of the `garden` AppProject. If later errors explicitly
report Git authentication or fetch failures, diagnose repository access
separately; don't treat the missing-project error as an authentication
failure.

**Branch lifecycle:** the initial Application tracks
`bootstrap/talos-foundation`, which is currently the working PR #63
branch and contains `cluster/apps/root/`. This lets the operator inspect
the root before merging the foundation branch. Only use this while the
operator controls that branch; Argo CD can deploy cluster-scoped objects.

**After** PR #63 is merged into `platform/talos-argocd` and that branch
contains the complete root source, explicitly retarget the running
Application through the Kubernetes API, then update the versioned
bootstrap manifest to match in a follow-up source change:

```sh
kubectl -n argocd patch application garden-root --type merge \
  -p '{"spec":{"source":{"targetRevision":"platform/talos-argocd"}}}'
kubectl -n argocd get application garden-root \
  -o jsonpath='{.spec.source.targetRevision}{"\n"}'
```

Do not switch to a branch that lacks the root path. Automatic root pruning
is disabled deliberately; do not introduce deletion/prune behavior without
a reviewed data and recovery plan.

## Next: Talos disks, then GitOps OpenEBS

Use Talos machine configuration to define the two UserVolumes on the
already attached 128 GiB NVMe-backed and 1 TiB HDD-backed block devices.
These volumes are **not** Kubernetes objects and are never managed by Argo
CD. Verify disk identity, actual mount points and reboot persistence.

Only after verification, add an OpenEBS Local PV Hostpath child Application
to `cluster/apps/root/`. Have it manage `nvme` and `data`
StorageClasses (`WaitForFirstConsumer`, `Retain`, no default class)
with a fail-closed mount prerequisite. Avoid installing OpenEBS manually
as a competing Helm release.

No extension UI should be deployed by default. Application-facing
interfaces (e.g., Immich) are a separate product requirement.

## Diagnosis

```sh
kubectl -n argocd get pods -o wide
kubectl -n argocd get events --sort-by=.lastTimestamp
kubectl -n argocd logs deployment/argocd-repo-server --tail=100
kubectl -n argocd logs statefulset/argocd-application-controller --tail=100
kubectl -n argocd get application garden-root -o yaml
```

Never delete an existing Argo CD Helm release or the Argo CD CRDs as a
troubleshooting shortcut: controller state and tracked Applications
could be affected.
