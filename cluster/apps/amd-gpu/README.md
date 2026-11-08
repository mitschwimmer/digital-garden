# AMD GPU device plugin

## Observed hardware (operator, 2026-11-07)

Incus passed the host Radeon RX 9060 XT PCI function `0000:04:00.0` into
`garden-k8s`. Inside Talos v1.14.5, the card is enumerated as Navi 44
at guest PCI `0000:06:00.0`. The matching `amdgpu` extension reports
`20260916-v1.14.5`, and `/dev/dri` render nodes plus `/dev/kfd`
exist. The node, Cilium, OpenEBS, and Argo CD recovered healthy after reboot.

This proves **PCI passthrough, kernel-driver extension presence, and device-node
creation**, not Kubernetes GPU allocation or ROCm compute compatibility.

## GitOps deployment

`cluster/apps/root/amd-gpu-application.yaml` is intentionally **manual-sync
only**. Its Git source points to `cluster/apps/amd-gpu`. The pinned image
is `rocm/k8s-device-plugin:1.31.0.10`, based on upstream
[ROCm/k8s-device-plugin](https://github.com/ROCm/k8s-device-plugin/tree/v1.31.0.10).
This uses the upstream device plugin's required privileged access to
`/var/lib/kubelet/device-plugins` and `/sys` but omits the optional
node labeller and GPU health-exporter stack. Talos retains sole ownership
of the host kernel driver.

Check the rendered manifests with
`kubectl kustomize cluster/apps/amd-gpu` and inspect the privileged
DaemonSet before merging. Confirm the namespace's admission policy and
that no other AMD device plugin is already installed. Argo CD's root will
register the child, but will not deploy the DaemonSet automatically.

When approved, manually sync the `amd-gpu-device-plugin` Application
without prune. The only resources created by the child are a dedicated
ServiceAccount and the DaemonSet in `kube-system`.

## Acceptance (workstation)

```sh
kubectl -n argocd get applications
kubectl -n kube-system rollout status daemonset/amd-gpu-device-plugin --timeout=120s
kubectl -n kube-system logs daemonset/amd-gpu-device-plugin -c device-plugin
kubectl get node talos-nz5-tvq -o json | jq '{capacity:.status.capacity["amd.com/gpu"],allocatable:.status.allocatable["amd.com/gpu"]}'
```

Require allocatable `amd.com/gpu` to be `1` before testing a
disposable workload with `resources.limits.amd.com/gpu: 1`. Validate
real ROCm kernel execution, not only `rocminfo` or an advertised
resource. Consumer GPU support for Navi 44 is a **separate acceptance
gate**. Do not deploy production inference, enable automatic prune, or
change Cilium ownership based only on the device plugin's readiness.
