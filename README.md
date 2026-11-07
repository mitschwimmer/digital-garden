# Digital Garden — Kubernetes rebuild

This is the **post-retirement planning branch**, not a deployable Talos cluster yet.

The intended platform is a single-node Talos Linux Kubernetes VM on IncusOS host `measerve`: OpenTofu owns the VM, network, GPU passthrough and block volumes; Cilium provides CNI and Gateway API; Argo CD reconciles Kubernetes applications. Two local storage classes (`nvme` and `data`) use independently mounted Incus volumes, with the host's existing mirrored ZFS `data` pool retained. AMD Radeon RX 9060 XT support must be verified through an actual GPU workload.

See the [digital-garden skill](.agents/skills/digital-garden/SKILL.md) and its Kubernetes-specific references for the intended operating model, rollout sequence and recovery controls.

**Transition warning:** `platform/`, `systems/`, `nix/modules/` and the older reference documents are *legacy NixOS-container generation source*. They have not been removed or translated, and must not be applied as if they were the Kubernetes desired state. The new OpenTofu/Talos/Argo source will be introduced after the old garden's retirement. Do not merge this branch to `main` until old resource retirement and source cleanup have been confirmed.

Run the one-time legacy retirement only from the separate [`retirement/old-garden`](https://github.com/mitschwimmer/digital-garden/tree/retirement/old-garden) branch on the workstation with its original state. Neither deleting the old garden nor building the new cluster is an automatic GitOps action.
