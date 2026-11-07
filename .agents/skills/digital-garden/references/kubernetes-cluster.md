# Cluster and host boundaries

## Discover first

Use an authenticated workstation Incus client. Confirm the chosen remote resolves to `measerve` and inspect instances, pools, IncusOS LAN bridges and physical PCI inventory. Pools are host prerequisites, *not* OpenTofu-managed cluster resources. Do not use an IncusOS shell as a build or configuration workspace. Check that the post-retirement inventory is empty before the first VM plan.

## Bootstrap order

1. Build the workstation development shell and pin Incus provider, Talos, Kubernetes, Cilium and Gateway API CRDs. Inspect compatibility matrices before choosing versions.
2. With OpenTofu, create **one VM** with an appropriate LAN NIC, a Talos system disk, a custom NVMe block volume and a separate custom block volume on the existing mirrored `data` pool. Preserve stable names/device identity. Plan and review replacements before applying; never delete pools.
3. Inspect IOMMU groups, actual RX 9060 XT PCI ID and any associated functions. Configure Incus physical GPU passthrough only after identifying the correct device and checking host usage and isolation. Do not presume hotplug or headless host availability.
4. Generate Talos machine configuration and cluster secrets off-host, retain encrypted copies outside the cluster, and configure the single control-plane node to schedule workloads. Pin any required version-matched `amdgpu` system extension. Apply machine configuration and bootstrap etcd once.
5. Use explicit disk selectors and two Talos UserVolume mounts (for example `/var/mnt/k8s-nvme`, `/var/mnt/k8s-data`). Never match by arbitrary `/dev/sdX` enumeration. Confirm mounting and restart persistence before installing local PV provisioning.
6. Install Cilium with Talos-compatible settings, control-plane API access during bootstrap, kube-proxy replacement if selected and a single-operator topology. Prove API, CoreDNS, pod-to-pod, egress and network policy operation.
7. Install Argo CD only after networking works; see [gitops](kubernetes-gitops.md).

## Network and GPU gates

Cilium Gateway API can expose the public gateway directly through host networking on a stable LAN address. If listeners use 80/443, configure permitted privileged binding as required by the pinned Cilium version. Verify IPv4, IPv6, router forwarding and public TLS separately; don't expose Kubernetes/Incus management APIs to the internet.

After PCI passthrough, inspect Talos kernel module state, `/dev/dri`/`/dev/kfd` where applicable, AMD plugin-advertised `amd.com/gpu` capacity and pod scheduling. Finish with a real ROCm container computation (not merely `kubectl get nodes`). Do not let an operator overwrite Talos's immutable host driver.

## Updates and diagnostics

Upgrade one layer at a time: Incus/VM infrastructure, Talos/Kubernetes and extensions, Cilium/Gateway, Argo CD, then workloads. Talos upgrades reboot the only node. Require a current off-host recovery point and test persistence of both workload mounts after reboot. Diagnose from Incus console/resources, `talosctl`, `kubectl` and Argo CD in that order. Keep administrative access independent of Kanidm.
