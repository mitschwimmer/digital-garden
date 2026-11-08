---
name: digital-garden
description: Build, operate and recover mitschwimmer/digital-garden as a single-node Talos Kubernetes cluster on IncusOS host measerve. Use for OpenTofu VM and disk changes, Talos and Cilium networking, Argo CD GitOps, OpenEBS local storage, AMD Radeon GPU passthrough, gateway and OIDC setup, service deployment, updates, secrets, backup and disaster recovery.
---

# Work on Digital Garden (Kubernetes generation)

The target is **one Talos Linux VM on `measerve`**, not the former NixOS-container garden. The IncusOS host, its prepared pools and host networking are prerequisites, not disposable cluster resources. Kubernetes, Argo CD and services are introduced in stages; **do not assume a planned component is installed**. Inspect actual source, versions and live state.

## Current deployment stage (operator-reported, 2026-11-08)

The **single-node Talos cluster is live** in the `garden-k8s` Incus VM
on `measerve`, LAN `192.168.1.49`: Talos **v1.14.5**,
Kubernetes **v1.37.1**, Cilium **v1.20.4** and Argo CD Core **v3.6.1**.
The operator passed the single-node Cilium connectivity suite.
Two Talos XFS UserVolumes survive reboot at `/var/mnt/k8s-nvme`
and `/var/mnt/k8s-data`. The node is still a single failure domain.

**GitOps ownership:** `garden-root` reconciles Argo CD AppProject,
repository declarations, namespaces and *manual-sync* children.
Their Git source declarations are now **`main`**, but the live
`garden-root` must be changed exactly once using
`argocd --core app set garden-root --revision main` and
validated by its sync/health and child target revisions. Before
that operator action, the live root may still track
`bootstrap/talos-foundation`. See
`cluster/bootstrap/argocd/README.md` for the migration and rollback. The Cilium v1.20.4 installation has been
adopted by the `cilium-platform` Argo Application after a reviewed
Helm-to-Argo handoff. Its original bootstrap Helm release record
remains; **never uninstall it**, and don't run competing `helm upgrade`
operations. The Argo application preserves the pre-existing
`cilium-ca` and Hubble certificate bytes with targeted
`ignoreDifferences` plus `RespectIgnoreDifferences=true`.

**Storage:** OpenEBS Local PV Hostpath **v4.6.0** is live with
`nvme` and `data` classes and a tested mount-source admission guard.
Operator-tested disposable provisioning/write/read paths passed.
`Retain` is not a backup; Kanidm database persistence after Pod
replacement and off-host restore have **not** passed.

**Public networking:** Cilium Gateway API (upstream CRDs
**v1.6.3**, Argo-owned), cert-manager **v1.21.3**, Envoy hostNetwork,
public router forwards TCP **80/443** to `192.168.1.49`.
The operator confirmed separate unauthenticated HTTP and HTTPS smoke
sites at `test.archaic.work` and `secure-test.archaic.work`,
including Let's Encrypt HTTP-01 staging and production certificates.
The production Kanidm hostname is **`auth.archaic.work`**: a newly
initialized, Kaniop **v0.21.0**-managed Kanidm **v1.11.2** instance
with its own **10Gi `nvme` PVC**, Let's Encrypt Certificate, and
Cilium SNI TLS passthrough `TLSRoute`. The operator reports all
new resources deployed without problems. The former
`auth.archaic.work` server *outside* Kubernetes was deleted; this
reuses **the name only, not its data or login credentials**.
The disposable `idm.localhost` Kanidm remains separate.

**Next session:** verify whether person `henner` was actually
created and can authenticate at `auth.archaic.work`; prior guidance
for `kanidm person create` and credential enrollment was provided
but **completion was not reported**. Use an isolated
`KANIDM_TOKEN_CACHE_PATH` to avoid stale sessions from the former
external Kanidm. Then establish a Kanidm-consistent **off-host
backup and tested restore** before trusting the new server for
irreplaceable identities or OIDC clients. Cert renewal itself,
Kanidm Pod-replacement persistence, backup/restore, and GPU/ROCm
workload acceptance remain open. Read
`cluster/apps/kanidm-primary/README.md` and
`cluster/apps/web-smoke/README.md` for owning procedures.

**Compatibility caveat:** Kubernetes v1.37.1 exceeds the officially
tested ranges stated for pinned Cilium v1.20.4 and cert-manager
v1.21.3. Passed functional checks do not make the combination
officially supported; revisit during upgrades. Do not remove the
healthy CNI just to change compatibility status.

## Route the task

- Read [cluster](references/kubernetes-cluster.md) for current deployment state, Incus VM, Talos bootstrap, Cilium, physical GPU, disk/mount design or upgrades. Use `cluster/talos/README.md` and `cluster/bootstrap/cilium/README.md` for exact, version-pinned commands.
- Read [gitops](references/kubernetes-gitops.md) for Argo CD bootstrap, application ordering, secrets, ingress, workloads and software updates.
- Read [recovery](references/kubernetes-recovery.md) for persistence, backup, restore, destructive changes and decommissioning.
- Before operating the old garden, use the **retirement branch and its old handbook**. This skill is for the *post-retirement* architecture. Old `systems/*` HCL, NixOS seed definitions and service references carried forward in a transition branch are historical, **not deployable desired state**. Replace them before cluster installation.

## Working rules

1. Use a Git branch and inspect affected source plus its owning reference. Prefer native upstream tools and pinned releases. Check version-sensitive APIs against the pinned code or official documentation.
2. Separate ownership: **OpenTofu** manages the Incus VM, network attachments, GPU device and separate block volumes; **Talos** configures the node and disks; **Argo CD** reconciles cluster add-ons and applications. Do not make Argo CD manage its Incus host or let two controllers own the same release.
3. Build and run host/client tooling on the workstation (`nix develop`); never install tooling on IncusOS. Inspect the authenticated Incus remote, the `measerve` inventory, prepared pools, LAN bridge, PCI IOMMU groups and device identities before writing hardware-specific inputs. Never guess PCI addresses or pool names.
4. Recovery/bootstrap order: Incus infrastructure -> Talos/Kubernetes -> Cilium/DNS -> Argo CD Core -> Talos UserVolumes (host-side, outside Argo) -> Argo-managed OpenEBS -> apps. **All these layers are live now.** Existing Argo child Applications are manual-sync, not auto-synced by the root. Keep recovery bootstrap independent of Argo: preserve the original Cilium Helm release record, but treat `cilium-platform` as its current desired-state owner and never uninstall Helm-managed Cilium workloads as part of the handoff.
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
- GitOps: Argo CD Core (not Flux), with a small root Application and manual-sync children. Argo CD Core's bootstrap Helm release remains independent; **Cilium's desired state is now Argo-managed**. No routine `kubectl apply` or `helm upgrade` for Argo-owned resources. All source manifests target `main`; the live root needs the one-time Argo Core CLI source-revision switch, followed by checking child sources. See `cluster/apps/root` and `cluster/bootstrap/argocd/README.md`.
- Backup: Velero with off-`measerve` repository is planned; application-specific consistency/restore checks remain essential. Do not put irreplaceable state into service until its backup path exists and has been tested.

## Finish

Update the *owning* source and one reference for a new reusable procedure or service contract. Run relevant formatting, schema/template lint and, when available, isolated cluster tests. Report what was built, what was inspected live and what remains untested. Keep destructive operations separated from normal provisioning with an explicit resource inventory and operator approval.
