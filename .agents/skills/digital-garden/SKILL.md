---
name: digital-garden
description: Build, operate and recover mitschwimmer/digital-garden as a single-node Talos Kubernetes cluster on IncusOS host measerve. Use for OpenTofu VM and disk changes, Talos and Cilium networking, Argo CD GitOps, OpenEBS local storage, AMD Radeon GPU passthrough, gateway and OIDC setup, service deployment, updates, secrets, backup and disaster recovery.
---

# Work on Digital Garden (Kubernetes generation)

The target is **one Talos Linux VM on `measerve`**, not the former NixOS-container garden. The IncusOS host, its prepared pools and host networking are prerequisites, not disposable cluster resources. Kubernetes, Argo CD and services are introduced in stages; **do not assume a planned component is installed**. Inspect actual source, versions and live state.

## Current deployment stage (operator-reported, 2026-11-07)

The existing `garden-k8s` VM has Talos **v1.14.5** on its dedicated
64 GiB system disk, Kubernetes **v1.37.1** bootstrapped on one control-plane
node (`192.168.1.49`), and Cilium **v1.20.4** installed via a bootstrap Helm
release. The node, Cilium agent/operator/Envoy and the **single-node Cilium
connectivity suite** passed operator checks. The test suite needs a
`privileged` Pod Security *test-namespace-only* exception; see
`cluster/bootstrap/cilium/README.md`.
The initial ISO was detached after Talos installation.

**Live milestone:** `garden-root` reported **Synced / Healthy** with the
`garden` AppProject present (operator output, 2026-11-07). The two
additional guest disks were reidentified with stable SCSI links and no
detected partitions or filesystems, but **are not provisioned**.

**Current storage milestone:** after removing the unbound
`system_disk` CEL variable, the operator reports both Talos
UserVolumes **ready and mounted as XFS**: `/dev/sdb` ->
`/var/mnt/k8s-data`, and `/dev/sdc` ->
`/var/mnt/k8s-nvme` (2026-11-07). Reboot persistence is **verified**
(2026-11-07); Kubernetes node, Cilium and Argo root are healthy.
Standalone OpenEBS Hostpath 4.6.0 GitOps source with a built-in
Kubernetes v1.37 `MutatingAdmissionPolicy` mount-source guard
is **staged but not included in root**. The guard is **not yet
validated or activated**; upstream alone does not check its
BasePath source. Dry-run the native policy and chart on the
workstation, and verify admission and provisioning behavior before
enabling storage. See `cluster/apps/openebs/README.md`. The GPU passthrough and Kata runtime are not
accepted as functional merely because Talos extensions were bundled.

**Compatibility caveat:** Kubernetes v1.37.1 is beyond Cilium v1.20.4's
officially e2e-tested v1.33–1.36 range. The observed connectivity test is
positive evidence, not a support guarantee. Reassess before exposing
production services. Don't remove/reinstall the working CNI for this reason.

## Route the task

- Read [cluster](references/kubernetes-cluster.md) for current deployment state, Incus VM, Talos bootstrap, Cilium, physical GPU, disk/mount design or upgrades. Use `cluster/talos/README.md` and `cluster/bootstrap/cilium/README.md` for exact, version-pinned commands.
- Read [gitops](references/kubernetes-gitops.md) for Argo CD bootstrap, application ordering, secrets, ingress, workloads and software updates.
- Read [recovery](references/kubernetes-recovery.md) for persistence, backup, restore, destructive changes and decommissioning.
- Before operating the old garden, use the **retirement branch and its old handbook**. This skill is for the *post-retirement* architecture. Old `systems/*` HCL, NixOS seed definitions and service references carried forward in a transition branch are historical, **not deployable desired state**. Replace them before cluster installation.

## Working rules

1. Use a Git branch and inspect affected source plus its owning reference. Prefer native upstream tools and pinned releases. Check version-sensitive APIs against the pinned code or official documentation.
2. Separate ownership: **OpenTofu** manages the Incus VM, network attachments, GPU device and separate block volumes; **Talos** configures the node and disks; **Argo CD** reconciles cluster add-ons and applications. Do not make Argo CD manage its Incus host or let two controllers own the same release.
3. Build and run host/client tooling on the workstation (`nix develop`); never install tooling on IncusOS. Inspect the authenticated Incus remote, the `measerve` inventory, prepared pools, LAN bridge, PCI IOMMU groups and device identities before writing hardware-specific inputs. Never guess PCI addresses or pool names.
4. Bootstrap order: Incus infrastructure -> Talos/Kubernetes -> Cilium/DNS -> Argo CD -> Talos UserVolumes (host-side, outside Argo CD) -> Argo-managed OpenEBS StorageClasses -> apps. Argo CD's initial deployment does **not** require a PVC, so do not make it depend on OpenEBS. **Incus VM, Talos, Kubernetes, Cilium and Argo CD Core root reconciliation are live; storage is not.** Keep bootstrap recoverable without Argo CD; Cilium's bootstrap Helm release remains the sole owner until a reviewed handoff, never uninstall the active CNI to hand it over.
5. Treat data as durable only after tested restoration, not merely because ZFS is mirrored. The single VM is a single availability and Kubernetes control-plane failure domain. Keep machine keys, Talos cluster secrets, Argo admin recovery and SOPS key material outside the cluster.
6. Keep all secrets out of Git plaintext, Nix store, OpenTofu variables/state, build outputs and logs. Use SOPS/age in Git and a pinned, tested Argo-compatible decryption workflow; document key custody and recovery separately.
7. For public services retain native Kanidm OIDC unless a reviewed service contract documents an exception. Record IPv4/IPv6 exposure, callers, TLS trust, gateway timeouts and allow/deny policy. Test both authorized and unauthorized paths.
8. Validate the changed layer before applying. For live operations, inspect saved OpenTofu plans, `talosctl` health and Kubernetes resources/events; use Argo CD sync/health only **after Argo CD is installed**. For the single-node Cilium acceptance test use `cilium connectivity test --single-node --namespace-labels pod-security.kubernetes.io/enforce=privileged`, never relax global Pod Security. A green GitOps sync is not proof that an app works. Stop dependent changes on failures.

## Fixed target decisions (until revised explicitly)

- Networking: Cilium CNI and Cilium Gateway API with Envoy; no separate Envoy Gateway controller or permanent Caddy edge.
- Storage: a Talos system disk and **two independently attached Incus custom block volumes**, mapped to `nvme` and `data`. `data` is an existing mirrored-ZFS pool on the *single host*. Use Talos UserVolumes and OpenEBS Local PV Hostpath; `WaitForFirstConsumer`, `Retain`, no default StorageClass until intentionally chosen. Validate mounts before allowing provisioning.
- Compute: physical Incus PCI GPU passthrough of the **Radeon RX 9060 XT** to the Talos VM; version-matched Talos `amdgpu` extension, AMD Kubernetes device plugin and a real ROCm workload test. GPU compatibility is an acceptance gate, not an assumption.
- Optional runtime: the Talos v1.14.5 Image Factory schematic includes `siderolabs/kata-containers` for future workloads, **not** as the default runtime. Validate nested virtualization inside the Incus VM (`vmx` and `/dev/kvm`) and extension-provided handler names before introducing an explicitly selected Kata `RuntimeClass`. Do not install a conflicting Kata runtime or presume passed-through GPU access inside Kata guests.
- Cluster extensions: **Kubernetes API only by default**. Install Argo CD **Core**, with no Argo CD web UI/API server, Dex, notifications, ingress or OIDC client. Manage `Application` and `ApplicationSet` CRDs via `kubectl`. Apply the same no-UI rule to OpenEBS, monitoring operators, device plugins and other infrastructure extensions; public UIs are only for services that actually need a user interface.
- GitOps: Argo CD (not Flux), with a small root Application, explicitly ordered dependencies and independently deployable services. Bootstrap instructions: `cluster/bootstrap/argocd/README.md`. The Argo CD Core installation remains Helm-owned; Argo CD manages only explicitly declared child Applications.
- Backup: Velero with off-`measerve` repository is planned; application-specific consistency/restore checks remain essential. Do not put irreplaceable state into service until its backup path exists and has been tested.

## Finish

Update the *owning* source and one reference for a new reusable procedure or service contract. Run relevant formatting, schema/template lint and, when available, isolated cluster tests. Report what was built, what was inspected live and what remains untested. Keep destructive operations separated from normal provisioning with an explicit resource inventory and operator approval.
