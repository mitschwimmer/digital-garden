# Kubernetes cluster and IncusOS boundaries

## Current observed stage (2026-11-07)

The operator installed and booted the one-node Talos control plane and
reported a **successful full single-node Cilium connectivity test**.
Before changing anything live, query the actual state rather than relying
on this dated milestone.

- IncusOS host: `measerve`; Incus VM: `garden-k8s`; Talos LAN IPv4:
  `192.168.1.49` (the host's management address is `192.168.1.137`).
- Talos **v1.14.5** on system disk, with Image Factory schematic
  `26a7fb977530a932ea54bbbff1a50973c13b7648599ee4cb6c1a9fed62c15ea7`;
  generated `talosctl` client matches v1.14.5. Talos image contains
  `amdgpu`, `kata-containers`, and `qemu-guest-agent` extensions.
- Kubernetes **v1.37.1** (single control-plane node), initialized with
  `talosctl bootstrap`; `kubectl get nodes` reported **Ready**.
- Cilium **v1.20.4** installed from pinned Helm chart in
  `cluster/bootstrap/cilium/values.yaml`; Cilium agent, Envoy and
  operator all reported **OK/Ready**. CLI pinned to **v0.20.2**. The
  operator reports connectivity tests successful after a temporary
  namespace-scoped Pod Security Admission exception.
- The Talos installer ISO was detached after installation. Argo CD Core's
  `garden-root` reported **Synced / Healthy** and the `garden` AppProject
  exists (operator output 2026-11-07); exact live Helm chart revision was
  not reported. No end-user services have been deployed. **Talos UserVolumes,
  OpenEBS, GPU passthrough and Kata workloads are not yet accepted as
  deployed/working.**

**Compatibility gate:** Cilium v1.20.4 was e2e-tested through Kubernetes
v1.36, not v1.37. The successful test is encouraging, but cannot replace a
supported-version decision or operational smoke/restore tests.

## Ownership, source and verification

Use `infrastructure/incus/main.tf` and `infrastructure/incus/README.md`
for Incus VM and pool-backed volumes; use `cluster/talos/README.md`
for Talos machine configuration/ISO/etcd; use
`cluster/bootstrap/cilium/README.md` for Cilium Helm and diagnostics.
These paths are relative to repository root. Always fetch the actual
branch source and inspect the live VM or Kubernetes state before an operation.
The old NixOS `systems/*` and container-era services are historical and
must not be deployed.

OpenTofu owns the Incus VM and block devices; Talos owns the operating
system and mounts; Helm owns the initial Cilium release; future Argo CD
owns only explicitly handed-off cluster add-ons and apps. Do not have
Argo CD and a separate Helm workflow reconcile the same Cilium resources.

The host's prepared `local` (Samsung 9100 PRO NVMe) and mirrored `data`
(HDDs) ZFS pools are not OpenTofu-managed. Do not delete or rebuild them
as a side effect of cluster work. VM initial resources: 8 vCPUs,
24 GiB RAM, 64 GiB system disk, 128 GiB `k8s-nvme` and 1 TiB `k8s-data`.

## Observed guest disk identities

Talos maintenance-mode inventory from 2026-11-07:

| Guest path | Stable Incus SCSI by-id identity | Purpose |
|---|---|---|
| `/dev/sda`, 64 GiB | `scsi-0QEMU_QEMU_HARDDISK_incus_root` | Talos system disk, already installed |
| `/dev/sdb`, 1 TiB | `scsi-0QEMU_QEMU_HARDDISK_incus_k8s--data` | future `data` UserVolume |
| `/dev/sdc`, 128 GiB | `scsi-0QEMU_QEMU_HARDDISK_incus_k8s--nvme` | future `nvme` UserVolume |

**Never** format the root disk or assume `/dev/sdX` order stays fixed.
For UserVolumes, select by verified persistent properties, not arbitrary
enumeration. Inspect current `talosctl get disks -o yaml` before
adding any volume configuration. Talos v1.14 introduced typed machine
configuration documents; old `machine.install` and `cluster.network`
patches conflict with them. Validate every generated config before applying.

Use `UserVolumeConfig` with `volumeType: disk` only for verified
whole-disk dedicated volumes; follow the pinned Talos v1.14 docs.
Confirm expected mounts at `/var/mnt/k8s-nvme` and `/var/mnt/k8s-data`
and persistence across reboot before configuring OpenEBS paths. Missing
mounts are a **stop** condition: never allow local-PV creation to write
into a fallback directory on the system disk.

## Cilium acceptance and Pod Security

The first Cilium test failed while deploying client Pods:
`ReplicaFailure=True / FailedCreate`, because Talos Kubernetes
admission defaulted to `baseline` and blocked `NET_RAW` and
`hostPort` on test workloads. Cilium itself and the node were already
healthy. The operator later verified test Deployments became ready
after labeling only `cilium-test-1` with
`pod-security.kubernetes.io/enforce=privileged`. The full single-node
connectivity suite subsequently passed.

Repeat the test with the **namespace-scoped exception** rather than
changing global/default namespace Pod Security:

```sh
cilium status --wait
cilium connectivity test --single-node \
  --namespace-labels pod-security.kubernetes.io/enforce=privileged
```

Clean up ephemeral test namespaces via the Cilium CLI after acceptance.
Do **not** reinstall the working CNI. Keep Helm as Cilium's owner until
a carefully reviewed Argo CD adoption; a blind uninstall can strand the
cluster networking. Gateway API is not enabled by the initial Helm values.

## Next dependencies

1. Verify node/Cilium remain healthy and secure off-host copies of
   Talos credentials, the working `talosconfig`, kubeconfig and etcd
   recovery material.
2. Argo CD Core's `garden-root` now reports **Synced / Healthy**.
   Keep Cilium's existing Helm release independent. Next, verify two
   identified, apparently unformatted block devices and perform a
   **Talos machine-configuration dry-run only** before authorizing
   filesystem initialization. Talos disk discovery of no signatures
   does not itself prove there is no valuable data.
3. Configure **two** explicit Talos UserVolumes on the existing extra
   disks, via Talos machine configuration *outside Argo CD*. Validate
   selectors, mounts, restart persistence and data-disk isolation.
4. Let **Argo CD** deploy OpenEBS Local PV Hostpath and manage the two
   `nvme` and `data` StorageClasses (`WaitForFirstConsumer`, `Retain`,
   neither default). Do not enable provisioning until both actual mounts
   are verified; fail closed if a mount is missing.
5. Later cold-attach the Radeon physical GPU and verify Talos driver,
   advertised `amd.com/gpu`, and a real GPU compute workload. Do not
   infer functioning GPU from extensions alone. Kata is future opt-in,
   requires nested KVM and a reviewed RuntimeClass; keep it off by default.

The Radeon RX 9060 XT (`1002:7590`) was originally at
`0000:04:00.0`, IOMMU group 13, with audio function
`0000:04:00.1` in group 14. Reinspect host PCI/IOMMU identity before
passthrough. Intel iGPU stays available to IncusOS.

## Operational checks

Perform changes only from the workstation `nix develop`, never an
IncusOS shell. In this order: confirm authenticated Incus remote and VM,
review the saved OpenTofu plan, inspect `talosctl` health/disks,
`kubectl get nodes,pods`, Cilium status/connectivity, and later Argo CD
sync. Upgrades to Talos/Kubernetes/extensions or Cilium are independent
change windows and can reboot or strand the only node. Keep an off-host
recovery point, and verify restored application data before claiming
production readiness.
