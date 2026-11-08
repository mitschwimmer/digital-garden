# Kubernetes cluster and IncusOS boundaries

## Current observed stage (2026-11-08)

The operator reports a healthy **single-node** Talos cluster.
Before acting, inspect live state rather than relying on this dated
status. Its hardware identity and baseline deployment are:

- IncusOS host `measerve`; VM `garden-k8s` at IPv4
  `192.168.1.49` (host management `192.168.1.137`).
- Talos **v1.14.5**, Kubernetes **v1.37.1**, one Ready
  control-plane node; standalone Cilium connectivity suite passed.
- Cilium agent/operator/Envoy **v1.20.4**, Gateway API enabled
  in hostNetwork mode via Argo CD's `cilium-platform`; the
  former bootstrap Helm release record is retained.
- Argo CD Core **v3.6.1**, `garden-root` live, child
  Applications manual-sync. Argo-managed Gateway API CRDs
  **v1.6.3** and cert-manager **v1.21.3**.
- XFS Talos UserVolumes `u-k8s-nvme` (128Gi) and
  `u-k8s-data` (1Ti), mounted after reboot.
- OpenEBS Local PV Hostpath **v4.6.0**, `nvme` and `data`
  StorageClasses, working mount-source guard and initial
  disposable provisioning tests, as reported by the operator.
- TCP 80/443 forwarded to this node. Operator-tested public
  HTTP and HTTPS smoke websites and ACME HTTP-01 issuance;
  `auth.archaic.work` uses Cilium TLS passthrough to a
  newly deployed Kaniop-managed Kanidm.
- GPU hardware passthrough, device allocation and real ROCm
  workload acceptance remain separate checks; no claim made.
  Neither Kanidm off-host restore nor new-person sign-in is confirmed.

**Compatibility caveat:** Cilium v1.20.4 and cert-manager v1.21.3
were tested upstream against older Kubernetes versions than
v1.37.1. Observed functionality does not guarantee compatibility
for upgrades or recovery.

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
system and mounts; the initial Helm release record for Cilium remains for bootstrap
history, but Argo CD's `cilium-platform` now owns its desired state.
Do not run competing Helm changes or uninstall the old release.

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
Do **not** reinstall the working CNI. Cilium's reviewed Argo adoption and Gateway API enablement passed on
2026-11-08. The bootstrap Helm release must not be uninstalled:
doing so can remove the live CNI. Inspect Argo's
`cilium-platform` status before subsequent changes.

## UserVolumes, OpenEBS and next dependencies (2026-11-08)

- `u-k8s-nvme`: guest `/dev/sdc` mounted at
  `/var/mnt/k8s-nvme`; `u-k8s-data`: `/dev/sdb` at
  `/var/mnt/k8s-data`. Both are XFS and passed the
  operator-reported Talos reboot persistence test.
  The system disk remains separate on `/dev/sda`.
- OpenEBS Local PV Hostpath v4.6.0, the `nvme` and `data`
  StorageClasses and the native mount-source guard are live.
  Guard-positive and guard-fail-closed admission canaries,
  followed by disposable first provisioning/write/read,
  reportedly passed. Guard scope is specific to the
  configured helper; it is not a general data-backup policy.
- The next identity acceptance is to verify personal account
  `henner` on the new `auth.archaic.work` Kanidm. The
  registration commands were provided, but outcome **not reported**.
  Use a dedicated token cache so credentials from the
  deleted external `auth.archaic.work` server are not reused.
- Create a Kanidm-consistent off-host backup and **verify
  restoration** into a disposable environment before relying
  on identity data. Cert-manager renewal and new Kanidm Pod
  replacement remain untested.
- Later validate Radeon RX 9060 XT GPU visibility, device
  plugin allocation and a real ROCm workload before calling
  passthrough complete. Kata opt-in requires nested KVM checks.

The Radeon RX 9060 XT (`1002:7590`) was formerly reported at
`0000:04:00.0` (audio `0000:04:00.1`). Reinspect host PCI and
IOMMU identity before changing passthrough; never assume
the device addresses remain stable.

## Operational checks

Perform changes only from the workstation `nix develop`, never an
IncusOS shell. In this order: confirm authenticated Incus remote and VM,
review the saved OpenTofu plan, inspect `talosctl` health/disks,
`kubectl get nodes,pods`, Cilium status/connectivity, and later Argo CD
sync. Upgrades to Talos/Kubernetes/extensions or Cilium are independent
change windows and can reboot or strand the only node. Keep an off-host
recovery point, and verify restored application data before claiming
production readiness.
