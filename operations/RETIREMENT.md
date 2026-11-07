# Old garden retirement (workstation only)

**This branch is for deleting the existing Digital Garden. Do not merge its disabled `prevent_destroy` volume safeguards into `main`.** It intentionally contains the existing infrastructure declarations, with protection removed for retirement only.

This retirement is **destructive**, including all old applications, user accounts, credentials and custom volumes. The prepared IncusOS storage pools and host configuration must remain.

## Workstation prerequisites

Use the original workstation checkout with its six local OpenTofu states, `site.auto.tfvars.json` files, authenticated Incus client and Nix development shell. Check that each remote is `measerve`. If any original state or runtime input is missing, **stop and investigate**; do not initialize an empty state and assume it is safe to delete the live instance. The script fails on unknown resource addresses.

Before destruction, disable public router forwarding and revoke external credentials that will no longer be used. Decide what encrypted keys, OpenTofu state, and application records need confidential retention; **no application-state migration or backup is performed**. Saved OpenTofu plans can contain secrets, so the script stores them in ignored, private `.operations/retirement/` folders.

## Procedure

```bash
git fetch origin
git switch retirement/old-garden
nix develop
bash operations/retire-garden.sh inspect YOUR_REMOTE
bash operations/retire-garden.sh plan YOUR_REMOTE
```

Read **every** `*.plan.txt` output under the printed private plan directory. Confirm that each proposed deletion belongs to the old garden and that no Incus pool, host-level bridge or unrelated resource is included. The script will stop if it detects an unexpected resource.

After independently reviewing the plans and resolving any operational concerns:

```bash
bash operations/retire-garden.sh apply YOUR_REMOTE /ABSOLUTE/PATH/TO/PLANS_DIRECTORY
```

The apply command confirms the complete retirement, then prompts for explicit approval of every independent OpenTofu root. It applies only the exact saved plans, in this order: Walter, WebDAV, Immich, identity, edge, then platform. It verifies managed state after each apply and finally prints a host inventory for manual leftover review.

An interrupted run may be resumed using the same plan directory if the saved plans remain valid. If anything changes, create new plans before continuing. **Do not force-delete unknown Incus volumes, images, snapshots, networks or projects just to make the inventory empty.** Treat anything not accounted for by the former OpenTofu state as a separate discovery and authorization task.

## After retirement

Verify prepared pools, access to IncusOS, the host LAN bridge and GPU inventory. Switch to `platform/talos-argocd` for the **new** operating skill. That branch initially contains a target architecture and references, not a deployable Talos implementation; remove obsolete source as part of the new cluster provisioning work.

## Partial failure: project not empty

Incus can cache OCI images in a project independently of any OpenTofu-managed instances. After deleting `walter` its `ai` project may still contain one or more cached images. A failed platform destroy may already have removed the other projects and `gardenbr0`; OpenTofu does not roll them back. **Do not reuse the partially applied saved plan.**

First inspect what remains, including image fingerprints:

```bash
bash operations/retire-garden.sh inspect YOUR_REMOTE
incus project info YOUR_REMOTE:ai
incus image list YOUR_REMOTE: --project ai
```

Verify no instances still depend on the image, and that the fingerprint is exclusively old-garden state. Then remove **only that named image**:

```bash
incus image delete YOUR_REMOTE:FINGERPRINT --project ai
```

If other resources remain in `ai` (custom volumes, snapshots, non-default profiles, buckets, instances), investigate and authorize them separately. Never use `incus project delete --force` or blanket deletion to circumvent the check. Once `ai` is empty:

```bash
bash operations/retire-garden.sh plan YOUR_REMOTE
# Read the new platform.plan.txt and verify it targets only incus_project.ai.
# Then use the new printed apply command and plan directory.
```

A new plan should see the already-deleted roots as empty. If it does not, stop and examine the state/inventory mismatch before applying anything.
