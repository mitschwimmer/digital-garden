# Bootstrap Cilium on the first Talos node

This is a **one-time, manually Helm-managed bootstrap** to make Kubernetes
networking work *before* Argo CD is installed. The chart is pinned to
**v1.20.4** and the values are [values.yaml](values.yaml).
The only Talos node is `192.168.1.49` (the LAN address allocated to
`garden-k8s` on IncusOS `measerve`).

## Compatibility caveat (important)

The generated Talos v1.14.5 Kubernetes API is **v1.37.1**. Cilium v1.20.4 is
the current stable release, but its official e2e Kubernetes matrix stops at
**v1.36**. Kubernetes v1.37 is newer than that tested range. This is a
deliberate *experimental bootstrap* and **must not be treated as supported
production until compatibility is independently established**. For a strict
supported-version requirement, recreate the fresh (no application data yet)
Talos control plane on Kubernetes 1.36 rather than downgrading an
already-initialized Kubernetes cluster in place. Do not deploy applications
until smoke tests, DNS, Services, policy, egress and reboot tests pass.

Official references:
- https://docs.cilium.io/en/stable/network/kubernetes/requirements/
- https://docs.cilium.io/en/stable/installation/k8s-install-helm/
- https://docs.cilium.io/en/stable/installation/k8s-install-talos-linux/

## Preconditions

From the **repository root** on the workstation (run `nix develop`):

```sh
export TALOS_IP=192.168.1.49
export TALOSCONFIG="$PWD/.operations/talos/talosconfig"
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"

talosctl --endpoints "$TALOS_IP" --nodes "$TALOS_IP" version
kubectl version
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl -n kube-system get daemonsets
helm list -A
```

**Stop** if authenticated Talos access or the Kubernetes API is unavailable,
etcd was not bootstrapped successfully, a different CNI/kube-proxy exists,
an existing Helm-managed `cilium` release exists, or KubePrism is not
configured for port `7445`. Before Cilium is installed, the node may
appear `NotReady` and CoreDNS pods may be pending; that alone is expected.
The Talos v1.14.5 config must have no `KubeFlannelCNIConfig`, have
`KubeProxyConfig.enabled: false`, and allow workloads on the control plane.
Inspect the **local** secret machine config without publishing it:

```sh
grep -A12 '^kind: KubePrismConfig$' .operations/talos/controlplane.yaml
grep -A6 '^kind: KubeProxyConfig$' .operations/talos/controlplane.yaml
grep '^kind: KubeFlannelCNIConfig$' .operations/talos/controlplane.yaml
```

The last command must print nothing. Do not proceed if any check disagrees.

## Render and install (one operator)

The root path is deliberate. Helm is the bootstrap owner; do **not** also
create an Argo CD Application for Cilium yet.

```sh
helm show chart oci://quay.io/cilium/charts/cilium --version 1.20.4
helm template cilium oci://quay.io/cilium/charts/cilium \
  --version 1.20.4 \
  --namespace kube-system \
  --values cluster/bootstrap/cilium/values.yaml \
  > .operations/talos/cilium-rendered.yaml

helm install cilium oci://quay.io/cilium/charts/cilium \
  --version 1.20.4 \
  --namespace kube-system \
  --values cluster/bootstrap/cilium/values.yaml \
  --wait --timeout 10m
```

The render output is **ignored local state**, not a committed set of
kube-system resources. If the install times out, inspect Cilium pods,
DaemonSets, logs and events. Don't install a second CNI or re-run
`helm install` blindly. There must be one Helm release and one Cilium
control plane at any time.

## Acceptance

```sh
helm -n kube-system status cilium
kubectl -n kube-system rollout status daemonset/cilium --timeout=5m
kubectl -n kube-system rollout status deployment/cilium-operator --timeout=5m
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl -n kube-system get pods -l k8s-app=kube-dns

# Pin-matched Cilium CLI v0.20.2 is provided by nix develop.
cilium version --client
cilium status --wait
# This is a one-node Kubernetes cluster; skip inter-node-only scenarios.
cilium connectivity test --single-node
```

Only after the node is `Ready` and CoreDNS is `Running` and ready, test a
temporary pod's DNS and egress (do not leave workloads behind):

```sh
kubectl run cilium-smoke --image=busybox:1.36 \
  --restart=Never --command -- sleep 3600
kubectl wait --for=condition=Ready pod/cilium-smoke --timeout=120s
kubectl exec cilium-smoke -- nslookup kubernetes.default.svc.cluster.local
kubectl exec cilium-smoke -- wget -q -O - https://example.com/
kubectl delete pod cilium-smoke
```

### If test setup times out

The Cilium CLI can fail *before any traffic checks* while waiting for its
`cilium-test-1/client` Deployment. `replicas count is zero` reports the
Deployment's observed `status.replicas` count, not a specific CNI diagnosis.
**Do not** blindly increase the timeout, reinstall Cilium, or delete the
test namespace before capturing its failure events:

```sh
kubectl get nodes -o wide
cilium status
kubectl -n cilium-test-1 get deployments,replicasets,pods -o wide
kubectl -n cilium-test-1 describe deployment client
kubectl -n cilium-test-1 get events --sort-by=.lastTimestamp
kubectl describe node
```

Inspect the actual pod and ReplicaSet if created; a zero observed replica
count can result from missing Pods, scheduling, insufficient resources,
admission failures or slow controllers. The expected client replicas are
different from inter-node-only deployments. The single-node switch is
required for the future rerun, but **does not alone diagnose client=0**.

Once the underlying issue has been understood and corrected, remove only
the CLI's temporary namespace before a clean retry:

```sh
kubectl delete namespace cilium-test-1
cilium connectivity test --single-node
```

Do not delete unrelated namespaces. If `cilium-test-1` does not exist,
there is nothing to clean up.

If the CLI connectivity test or any smoke check fails, inspect Cilium
and CoreDNS instead of adding services. The full test includes network-policy
enforcement, and may take longer than basic readiness checks. Inspect
individual failures before rerunning. Treat the Kubernetes 1.37 compatibility
decision as open until all tests pass and keep the version caveat documented.

## No dual ownership on the Argo CD handoff

Do not `helm uninstall cilium` merely to introduce Argo CD: this can remove
the running CNI and strand its own controller. Before an Argo-managed
application is introduced, plan an explicit handoff of the *same* pinned
chart, release identity, values and CRDs, verify what will prune or replace,
and only then retire Helm release bookkeeping. The new controller must not
fight the old owner. Until then, Helm is the sole owner and Cilium upgrades
are separate, reviewed operations.
