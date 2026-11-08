# Argo CD Core bootstrap (Kubernetes API only)

## Current GitOps source: main (2026-11-08)

The `main` branch now contains the complete cluster configuration.
The `garden-root` bootstrap manifest and the self-managed
`cluster/apps/root/*-application.yaml` child declarations in Git
all point to `main`. The **running** `garden-root` still points to
the old `bootstrap/talos-foundation` revision until the operator
performs a one-time, explicit migration below.

Argo CD Core, Cilium, OpenEBS, cert-manager, the two public smoke
sites, Kaniop and `auth.archaic.work` Kanidm are **already live**.
Do not reinstall or manually reapply their manifests just to
change Git branches. The original Cilium bootstrap Helm release
record remains; Cilium is now managed through Argo CD.

### One-time migration: bootstrap/talos-foundation to main

The `main` branch already contains the previous live deployment.
This migration changes **only the Git source-revision selectors** in
Argo `Application` definitions; Helm versions, workload resources,
persistent data, manual child sync policies and prune settings
remain unchanged.

After merging the revision-switch PR into `main`, from the
workstation in `nix develop`:

```sh
git switch main
git pull --ff-only origin main
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"

# Inspect the existing root and controller without mutating resources.
kubectl -n argocd get application garden-root \
  -o jsonpath='{.spec.source.targetRevision}{"\n"}'
kubectl -n argocd get pods
kubectl -n argocd get configmap argocd-cm

# Validate that the newly merged root definitions render locally.
kubectl kustomize cluster/apps/root > /tmp/garden-root-main.yaml
# With the old ref fetched, compare desired manifests in Git:
git diff origin/bootstrap/talos-foundation origin/main -- cluster/apps/root
```

Review the `git diff`: the intended differences under
`cluster/apps/root` are **only** child Application
`targetRevision` changes to `main`. Local Kustomize and Git
diffs do **not** replace live Argo comparison, but are a safe
independent preflight if the CLI is unable to initialize.

**Core CLI caveat:** `argocd --core app diff garden-root --revision main`
can hang while initializing its settings informers. If interrupted
with Ctrl+C it may report
`timed out waiting for settings cache to sync`; the message
alone is **not proof of a bad repository revision or an unhealthy
running controller**. Do not repeatedly retry it or restart Cilium,
Argo or Redis as a workaround. Verify Kubernetes API availability,
Argo controller health, and the locally reviewed change first.

The usual one-time change is:

```sh
kubectl config set-context --current --namespace=argocd
argocd login --core
argocd --core app set garden-root --revision main
```

If **Core CLI commands** are also blocked by the same settings-cache
issue, use Kubernetes' native patch against the **existing root
Application only** instead:

```sh
kubectl -n argocd patch applications.argoproj.io garden-root \
  --type=merge \
  -p '{"spec":{"source":{"targetRevision":"main"}}}'
```

This one-time bootstrap ownership operation is **not** a manual
workload manifest installation. Do not patch child Applications or
apply Helm charts manually. The root's `automated.selfHeal=true`
and `prune=false` let Argo reconcile child Application
**definitions**, while **all child workloads remain manual-sync**.

Verify that Argo processed the new revision; the root may show
its previous `status.sync.revision` briefly until reconciliation:

```sh
kubectl -n argocd get application garden-root \
  -o jsonpath='{.spec.source.targetRevision}{"\t"}{.status.sync.revision}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}'
git rev-parse origin/main
kubectl -n argocd get applications -o wide
```

Require root `spec.source.targetRevision=main`, reported
`status.sync.status=Synced`, `status.health.status=Healthy`,
and `status.sync.revision` matching the merged `main` commit.
If the status revision still points to the former branch's SHA,
the root has **not** finished processing the switch.

Check the two multi-source children and one single-source child:

```sh
kubectl -n argocd get application cilium-platform \
  -o jsonpath='{.spec.sources[1].targetRevision}{"\n"}'
kubectl -n argocd get application openebs-localpv \
  -o jsonpath='{.spec.sources[1].targetRevision}{"\n"}'
kubectl -n argocd get application kanidm-primary \
  -o jsonpath='{.spec.source.targetRevision}{"\n"}'
```

All three must output `main`. Check that Cilium stays
`1.20.4` and OpenEBS stays `4.6.0` as Helm chart
sources. Some children may temporarily show `OutOfSync`
after their target revision changes; **do not bulk-sync**
Cilium, storage, certificates or identity workloads merely to
clear that status. No prune or workload replacement is part
of this branch migration.

Keep the old branch until the migration is verified. If the
root does not reconcile, inspect the actual error from:

```sh
kubectl -n argocd describe application garden-root
kubectl -n argocd logs statefulset/argocd-application-controller --tail=100
kubectl -n argocd logs deployment/argocd-repo-server --tail=100
```

#### Recovery if root cannot render main

If retargeting creates a Git or Kustomize error, the old branch
is intentionally retained. Restore the root revision through the
same Argo CD API:

```sh
kubectl -n argocd patch applications.argoproj.io garden-root \
  --type=merge \
  -p '{"spec":{"source":{"targetRevision":"bootstrap/talos-foundation"}}}'
# Observe and confirm root reconciliation rather than forcing child syncs:
kubectl -n argocd get application garden-root -o wide
```

Do not use prune or uninstall controllers. A root branch rollback
restores old child Git revision declarations, **not** earlier
versions of live application resources.

---


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
`argocd version --client`. **Core mode requires the Kubernetes
context's current namespace to be `argocd`** (upstream Core-mode setup).
Before using the CLI, verify the chart-provisioned ConfigMap exists and
select the namespace on the workstation's current kubeconfig context:

```sh
kubectl -n argocd get configmap argocd-cm
kubectl config set-context --current --namespace=argocd
argocd login --core
```

This changes the kubeconfig's default namespace for later `kubectl`
commands, not a Kubernetes resource. To inspect applications without the
CLI, use `kubectl -n argocd get applications`. A manual child Application
sync uses `argocd --core app sync <application-name>`; do not enable
automatic sync or pruning to compensate for a missing CLI. If Core mode
still reports `configmap "argocd-cm" not found` even when the ConfigMap
exists in `argocd`, inspect `kubectl config current-context`, the
`KUBECONFIG` environment variable and the Helm release first. Do not
create an unmanaged `argocd-cm` ConfigMap or reinstall Argo CD.


This is a single-node, non-HA deployment on the existing Kubernetes
v1.37.1 cluster. Upstream confirms these Helm values implement Core mode.
Argo CD Core's bootstrap Helm release remains separate from the
root Application. Cilium's original Helm release metadata also remains
for recovery, but its **current desired state is reconciled by the
Argo CD `cilium-platform` Application**; never uninstall the
original Helm release or issue competing Helm upgrades.

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

**Branch lifecycle:** The old
`bootstrap/talos-foundation` branch was used during cluster
bootstrap and was later merged into `main`. See the **one-time
migration** procedure above to retarget the live
`garden-root` and its manual-sync children without replacing
their workloads. The versioned bootstrap manifest also points
to `main`. Automatic root pruning remains disabled.

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
