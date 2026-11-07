# Bootstrap Talos on the Incus VM

Source-only specification. **No machine configs, talosconfig, kubeconfig,
Talos cluster secrets, installer checksum or age private keys belong in Git.**
Keep all generated client/cluster credentials in the ignored `.operations/`
directory on the workstation and an independently encrypted off-host copy.

## Pinned release and installation medium

Initial Talos target: **v1.14.5 (amd64, metal ISO)**, built through the
official Image Factory with `siderolabs/amdgpu`. Image Factory also provides
the corresponding extension-aware installer image. Save the schematic ID,
image digest/checksum and version in private operator notes. If the exact
Image Factory image cannot be obtained/verified, stop rather than substituting
an unrelated third-party image.

See [Incus VM prerequisites](../../infrastructure/incus/README.md).
That OpenTofu root starts with `start_vm=false` and GPU disabled until first
storage/network boot is verified.

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
   install disk and the actual reserved LAN IP:

   ```sh
   mkdir -p .operations/talos
   chmod 700 .operations/talos
   talosctl gen config garden "https://$TALOS_IP:6443" \
     --install-disk "$SYSTEM_DISK" \
     --config-patch @cluster/talos/cilium.patch.yaml \
     --output-dir .operations/talos
   ```

   Check the generated machine config, its target disk, the external API
   endpoint and Talos/Kubernetes version compatibility before applying.
   The patch explicitly selects **no bundled CNI, no kube-proxy**, and
   allows workloads on the single control-plane node.
5. Apply `.operations/talos/controlplane.yaml` to the VM using
   `talosctl apply-config --insecure` with the observed node IP; this
   installs Talos to the selected system disk. Boot from the system disk,
   then disconnect the ISO through a reviewed OpenTofu configuration
   update (`installer_iso=""`, `installation_complete=true`).
6. Bootstrap the single control-plane's etcd **once**, using the saved
   `talosconfig`. Obtain a kubeconfig and verify API access and etcd
   health. Kubernetes pods will not become ready before Cilium is installed.
7. Install a pinned Cilium Helm release with the documented Talos settings
   (Cilium kube-proxy replacement, KubePrism at localhost:7445,
   `cgroup.autoMount.enabled=false`, `cgroup.hostRoot=/sys/fs/cgroup`,
   the capability restrictions required by Talos, and tested DNS routing).
   Start with Cilium networking only; enable Cilium Gateway API after a
   healthy baseline. For Cilium's Talos DNS path, review
   `bpf.hostLegacyRouting` from the pinned chart documentation.
8. Only after Cilium is healthy, use `talosctl get disks` and verified
   serials to create **two** v1.14 `UserVolumeConfig` resources, one
   on each extra block disk. In Talos v1.14 use `volumeType: disk`
   when dedicating the whole block disk; no size constraints in that mode.
   Confirm `/var/mnt/k8s-nvme` and `/var/mnt/k8s-data` are actual mount
   points after reboot. Never let OpenEBS create directories until then.
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
