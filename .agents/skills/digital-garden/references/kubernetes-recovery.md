# Data protection, recovery and retirement

## Persistent storage

IncusOS owns prepared NVMe and mirrored ZFS `data` pools; OpenTofu manages only VM disks/custom volumes. Talos exposes those disks as UserVolumes and OpenEBS Local PV Hostpath creates Kubernetes `local` PVs. `Retain` preserves volume directories when a PVC is removed, but does not provide backups, quotas, per-PVC Incus snapshots or multi-node mobility. Monitor free space in both Talos filesystems and on host pools; verify fail-closed behavior when either mount is absent.

## Backup architecture

Target Velero filesystem backups to a repository outside `measerve`. Choose and test object storage, backup credentials and encryption before relying on it. Include Kubernetes resource manifests and the two classes' local PV content. Velero filesystem backup is not an atomic database snapshot: use native PostgreSQL/Kanidm backups or coordinated quiescence and restore procedures where consistency matters. Discardable caches should be documented and excluded.

Separately preserve encrypted Talos machine/cluster secrets, SOPS age keys, Incus infrastructure state/inputs, Argo admin break-glass access and the minimal source needed to bootstrap without the cluster. Take etcd backups appropriate to the pinned Talos release. No application should claim production readiness before a restore has been performed on disposable infrastructure and verified with actual user-visible data.

## Recovery order

1. Recover workstation access to IncusOS and host pools without Kubernetes or Kanidm.
2. Restore/recreate the VM and attach the correct NVMe/data volumes; avoid formatting disks containing surviving data.
3. Restore Talos configuration, bootstrap Kubernetes and Cilium, then install Argo CD.
4. Restore application objects and data in a planned order, keeping app writers stopped until their contents are present and coherent.
5. Verify gateway, TLS, Kanidm authorization, data reads/writes, GPU inference and restoration checks. Resume external traffic only after acceptance.

## Destruction

Never run `tofu destroy`, Argo CD prune or PVC deletion as an incidental cleanup operation. Before any destructive change list owners, dependencies, data and affected pools; show the exact plan; require explicit authorization. The one-time *old-garden retirement* uses `operations/retire-garden.sh` on its own retirement branch, not this Kubernetes handbook. Protect the prepared IncusOS pools and host/network management throughout. For the new cluster, keep infrastructure state and off-host backup/key material independent of its lifecycle.
