# Bootstrap Talos on the Incus VM

Source-only specification. **No machine configs, talosconfig, kubeconfig,
Talos cluster secrets, installer checksum or age private keys belong in Git.**
Keep all generated client/cluster credentials in the ignored `.operations/`
directory on the workstation and an independently encrypted off-host copy.

## Pinned release and installation medium

Initial Talos target: **v1.14.5 (amd64, metal ISO, Secure Boot off)**,
from the official Image Factory schematic
`26a7fb977530a932ea54bbbff1a50973c13b7648599ee4cb6c1a9fed62c15ea7`.
The source schematic is checked in at [image-factory.yaml](image-factory.yaml).
It includes `siderolabs/amdgpu`, `siderolabs/kata-containers` (for later
opt-in workloads) and `siderolabs/qemu-guest-agent`.

Boot ISO:
`https://factory.talos.dev/image/26a7fb977530a932ea54bbbff1a50973c13b7648599ee4cb6c1a9fed62c15ea7/v1.14.5/metal-amd64.iso`.

**Crucial:** the ISO alone does not pin the installed system. Generate the
machine configuration with [installer.patch.yaml](installer.patch.yaml), which
pins the *matching* factory installer:
`factory.talos.dev/metal-installer/26a7fb977530a932ea54bbbff1a50973c13b7648599ee4cb6c1a9fed62c15ea7:v1.14.5`.
Verify the official ISO checksum/signature before importing. Preserve
the verified checksum and ISO separately from cluster secrets.

See [Incus VM prerequisites](../../infrastructure/incus/README.md).
That OpenTofu root starts with `start_vm=false` and GPU disabled until first
storage/network boot is verified.

## Confirmed installation target (2026-11-07)

This VM is at `192.168.1.49`. The Talos maintenance-mode disk inventory
identified exact Incus SCSI symlinks:

| Target | Guest path | Stable symlink |
|---|---|---|
| Talos system, 64 GiB | `/dev/sda` | `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_root` |
| Kubernetes data, 1 TiB | `/dev/sdb` | `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_k8s--data` |
| Kubernetes NVMe, 128 GiB | `/dev/sdc` | `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_k8s--nvme` |
| Installer CD-ROM | `/dev/sr0` | `/dev/disk/by-id/scsi-0QEMU_QEMU_CD-ROM_incus_installer` |

**Only `/dev/sda` is an installation target. Never install Talos to
`/dev/sdb` or `/dev/sdc`.** At later reboots, select data disks by
stable observed identity, not arbitrary `/dev/sdX` ordering.

The original workstation flake carried `talosctl v1.13.11`; it is now
pinned to the exact node release `v1.14.5` from the upstream GitHub
asset using the published SHA-256. Before generation confirm
`talosctl version --client` reports `v1.14.5`.

## Sequence

1. Confirm the Talos VM and its three virtual disks exist, and that the LAN
   bridge/MAC DHCP reservation gives the VM a **stable new IPv4**. Do not
   reuse the host's `192.168.1.137`; that address belongs to IncusOS.
2. Boot the VM from the imported pinned ISO. Inspect the Incus console and
   obtain the Talos VM's actual DHCP address. Do **not** assume `/dev/sda`
   or any preassigned virtual disk numbering.
3. With a matching `talosctl` release on your workstation, inspect the disks
   in Talos maintenance mode:

   ```sh
   talosctl get disks --insecure --nodes "$TALOS_IP"
   talosctl get disks --insecure --nodes "$TALOS_IP" -o yaml
   ```

   Identify the 64 GiB **system disk** separately from the 128 GiB
   `k8s-nvme` and 1 TiB `k8s-data` disks, including stable serials.
   The later UserVolume selectors must match the intended guest disks.
4. Generate configuration **only on the workstation** using the observed
   install disk and the actual reserved LAN IP. The two patches use Talos
   **v1.14 typed documents**, not legacy `v1alpha1` fields; `--install-disk`
   generates the `UnattendedInstallConfig.provisioning.diskSelector` itself.

   In November 2026 the original v1.13-style patches caused six validation
   errors against Talos v1.14.5. If you generated configs with those old
   patches, preserve them separately **without ever applying them** before
   generating a fresh set. This node has not been configured yet, so generating
   new PKI is safe. Do not later reuse the old talosconfig with the new config.

   ```sh
   # Run from the repository root after entering nix develop.
   umask 077
   export TALOS_IP=192.168.1.49
   export SYSTEM_DISK=/dev/sda

   # Only if the previous, invalid generated files exist:
   if test -d .operations/talos; then
     mv .operations/talos .operations/talos-invalid-v114
   fi

   mkdir -p .operations/talos
   chmod 700 .operations/talos
   talosctl gen config garden "https://$TALOS_IP:6443" \
     --talos-version v1.14.5 \
     --install-disk "$SYSTEM_DISK" \
     --config-patch-control-plane @cluster/talos/cilium.patch.yaml \
     --config-patch @cluster/talos/installer.patch.yaml \
     --output-dir .operations/talos

   talosctl validate --config .operations/talos/controlplane.yaml --mode metal
   ```

   Verify the generated document identities and values before installation:

   - **UnattendedInstallConfig:** `provisioning.diskSelector` selects
     `/dev/sda`; `installer.image` is the exact Image Factory installer.
   - **KubeProxyConfig:** `enabled: false`.
   - **KubeFlannelCNIConfig:** no such document in `controlplane.yaml`.
   - **KubeNodeConfig:** no `node-role.kubernetes.io/control-plane: NoSchedule`
     taint; retain the generated control-plane labels.
   - There is no legacy `machine.install`, `cluster.network`,
     `cluster.proxy` or `cluster.allowSchedulingOnControlPlanes` field
     competing with those typed documents.

   The patch deliberately selects **no bundled CNI, no kube-proxy**, and
   allows workloads on the only control-plane node. Validation must pass
   before continuing; keep the new `talosconfig` with the matching
   configuration and back both up securely off-host.
5. Apply `.operations/talos/controlplane.yaml` to the VM using
   `talosctl apply-config --insecure` with the observed node IP; this
   installs Talos to the selected system disk. Boot from the system disk,
   then disconnect the ISO through a reviewed OpenTofu configuration
   update (`installer_iso=""`, `installation_complete=true`).
6. Bootstrap the single control-plane's etcd **once**, using the saved
   `talosconfig`. Obtain a kubeconfig and verify API access and etcd
   health. Kubernetes pods will not become ready before Cilium is installed.
7. Install Cilium using the [pinned and staged bootstrap procedure](
   ../bootstrap/cilium/README.md) with its Talos-specific values and
   mandatory compatibility/acceptance checks. Cilium v1.20.4 has not yet
   been officially e2e-tested against the generated Kubernetes v1.37.1;
   do not deploy garden services until the full connectivity and policy
   gates pass. Enable Cilium Gateway API only in a later reviewed stage.
8. Only after Cilium is healthy, use `talosctl get disks` and verified
   serials to create **two** v1.14 `UserVolumeConfig` resources, one
   on each extra block disk. In Talos v1.14 use `volumeType: disk`
   when dedicating the whole block disk; no size constraints in that mode.
   Confirm `/var/mnt/k8s-nvme` and `/var/mnt/k8s-data` are actual mount
   points after reboot. Never let OpenEBS create directories until then.
### Kata Containers, later

The factory image already includes `siderolabs/kata-containers`; this is
intentional future support, **not** a request to switch the default pod
runtime or deploy any Kata workload during bootstrap. Talos itself is a
KVM guest in IncusOS. Kata starts a further VM inside Talos and needs
nested KVM support: verify the Incus VM's `security.nesting` behaviour
(default `true` for Incus VMs), `vmx` CPU flag, and `/dev/kvm`
availability *inside Talos* before enabling an explicit Kubernetes
`RuntimeClass` for a sacrificial test pod. Keep normal workloads on
the default runtime. Review the exact shipped extension's runtime
handler names before creating a RuntimeClass, and do not install a
second competing Kata runtime with `kata-deploy`.

9. Cold-attach the Radeon GPU in OpenTofu, verify passthrough and the
   version-matched `amdgpu` extension inside Talos. Later, Argo CD will
   manage the AMD device plugin; acceptance requires a real GPU compute
   pod, not just a device in PCI inventory.

## Validation gates

- VM survives an Incus/Talos restart and still has fixed LAN address.
- Talos booted from the system disk; ISO is detached.
- Talos API is reachable independently of the cluster's services.
- Kubernetes control plane and Cilium are healthy.
- Two independent additional disks are identified and correctly mounted;
  no unintended format occurred on the system disk.
- Only the intended GPU reaches Talos and the host Intel iGPU remains.
- Operator can reconstruct access using off-host copies of cluster secrets.

The **next** GitOps milestone is Argo CD, not part of this first foundation
revision. Keep its bootstrap and child Applications in separate source.
