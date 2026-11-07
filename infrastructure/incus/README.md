# Garden Talos VM (OpenTofu)

This is the **only** new Incus infrastructure root. It manages one empty VM,
two retained custom `block` volumes and their attachments. The root disk is
an Incus VM disk. Host pools `local` (NVMe ZFS) and `data` (mirrored ZFS) and
the IncusOS host bridge are external prerequisites and must **never** be
destroyed or imported into this root.

## Verified measerve hardware, 2026-11-07

- Intel Core Ultra 5 235, 14 online logical CPUs; 31.62 GiB RAM.
- `local` ZFS uses the Samsung 9100 PRO NVMe. Existing host backup, image and
  log volumes in `local` are not ours.
- `data` is the separately prepared ZFS pool on two 4 TB HDDs (mirror).
- AMD Radeon RX 9060 XT: PCI `0000:04:00.0`, `1002:7590`, IOMMU group 13.
  Audio function `0000:04:00.1` is in group 14; not passed through initially.
  Host Intel iGPU `0000:00:02.0` remains accessible to IncusOS.
- Active IncusOS `instances`-role LAN interface: `enp129s0`. Confirm that
  an unmanaged bridge of that name is actually present in the Incus API before
  passing it as `lan_parent`; no managed guest bridge is created here.

## Workstation-only preflight

Run from the project checkout, not on IncusOS:

```sh
nix develop
incus info measerve:
incus list measerve: --all-projects
incus storage list measerve:
incus storage show measerve:local
incus storage show measerve:data
incus network list measerve: --project default
incus info measerve: --resources
incus query measerve:/os/1.0/system/network
```

Confirm the remote name, empty old-garden inventory, exact `enp129s0`
unmanaged bridge, free space, no `garden-k8s` VM or `garden-k8s-*` volumes
outside state, and GPU availability. Pause if any input conflicts with the host.
Never modify IncusOS networking as a side effect of a Talos plan.

## Prepare the first boot ISO

Use the **exact pinned Talos v1.14.5 amd64 metal ISO** from the
[factory schematic](../../cluster/talos/image-factory.yaml):
`26a7fb977530a932ea54bbbff1a50973c13b7648599ee4cb6c1a9fed62c15ea7`.
The schematic has `amdgpu`, `kata-containers` (future use) and
`qemu-guest-agent`; Secure Boot is disabled. Talos must later install via
the [matching installer patch](../../cluster/talos/installer.patch.yaml).
Verify the image checksum/signature from the Image Factory before import.

On the **workstation**, at the repository root:

```sh
mkdir -p .operations/talos
chmod 700 .operations/talos
curl --fail --location --output .operations/talos/metal-amd64.iso \
  https://factory.talos.dev/image/26a7fb977530a932ea54bbbff1a50973c13b7648599ee4cb6c1a9fed62c15ea7/v1.14.5/metal-amd64.iso
# Independently obtain and compare the official SHA256 checksum/signature here.
# Do NOT import an unverified download.
incus storage volume import measerve:local .operations/talos/metal-amd64.iso \
  garden-talos-v1.14.5 --type=iso --project default
incus storage volume show measerve:local garden-talos-v1.14.5
```

The ISO is an external import because Incus requires the `--type=iso` import
path. Only the two *data* volumes are OpenTofu-owned. The ISO may be deleted
manually later after unmounting and verified disk boot. Double-check command
syntax with the installed Incus client if its CLI version differs.

## Prepare private input and plan

```sh
cp infrastructure/incus/site.auto.tfvars.json.example \
   infrastructure/incus/site.auto.tfvars.json
# Set actual remote, inspected LAN parent and a NEW unique reserved MAC.
# The example MAC is NOT a reservation; do not leave it unchanged.
# Reserve the selected MAC -> fixed IPv4 in the LAN DHCP server.
cd infrastructure/incus
tofu fmt -check -diff
tofu init -input=false -lockfile=readonly
tofu validate
tofu plan -out=first.tfplan
tofu show first.tfplan
```

The first plan should create exactly three managed objects: two custom
block volumes and one stopped VM. The root disk is a device on the VM.
There must be **zero** Incus pool, project, physical bridge or host changes.
The VM and custom volumes have `prevent_destroy = true`; do not bypass
those guards for routine maintenance.

Only after reviewing this exact saved plan:

```sh
tofu apply first.tfplan
```

The new VM remains stopped by default. Before starting, verify the ISO
volume is imported and the MAC reservation is active. To boot from ISO,
set `start_vm = true` and apply a **new** reviewed plan. Initially leave
`enable_gpu_passthrough = false` so a potential VFIO binding problem cannot
block testing storage and networking. The GPU can be cold-attached later
after the VM is shut down and the host GPU is no longer in use.
For future Kata Containers, nested virtualization is already enabled by
default on Incus VMs (unless explicitly disabled). Verify the `vmx`
CPU capability and `/dev/kvm` in Talos before using a Kata RuntimeClass;
do not change the first reviewed VM plan solely for this deferred feature.

## Installation and handoff

Use [Talos bootstrap instructions](../../cluster/talos/README.md) to
discover actual disk identities, generate protected machine secrets, install
Talos once, then boot from its root disk. When disk boot succeeds, set
`installer_iso = ""`, `installation_complete = true`, and reconcile the
VM configuration to detach the ISO. Remove the externally imported ISO
only after confirming this worked.

The additional disks must be mapped to Talos UserVolumes by **verified
guest-visible disk identity**; device names or host pool names alone are
not proof. No storage provisioner should run on an unmounted filesystem.

## Safety/diagnostics

- The VM's root disk contains Talos state and etcd; Incus VM deletion is
  destructive even if custom volumes are protected.
- Both custom volumes are pinned by separate Incus resource objects and
  may not be shrunk after creation.
- The physical GPU is exclusive to the VM when passed through; no Incus
  hotplug is assumed.
- A passing OpenTofu plan or applied VM is not a working Talos cluster.
- Inspect `incus info measerve:garden-k8s`,
  `incus config show measerve:garden-k8s --expanded` and
  `incus console measerve:garden-k8s` on first boot.
- Preserve the private root state, local inputs, ISO checksum and Talos
  cluster secrets outside the cluster. This root does **not** configure Velero.
