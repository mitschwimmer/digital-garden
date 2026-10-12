# Reconcile one infrastructure root

Read [platform inputs](platform.md). Enter exactly one operation root and inspect
its local inputs, state and target host. Platform must already exist before leaf
roots can resolve `gardenbr0`. Do not use another root's plan, inputs or state.

## Review and apply the whole plan

Run in the selected root, in the repository's fish development shell:

```fish
tofu fmt -check -diff
tofu init -input=false -lockfile=readonly
tofu validate
tofu plan -out=change.tfplan
tofu show change.tfplan
```

Stop on any failure. Inspect all proposed changes against actual inventory and
intended ownership. Review replacements, deletions and device changes explicitly.
The first plan creates this root's resources, including volumes. Resource counts
are not acceptance criteria. Only apply that exact reviewed saved plan:

```fish
tofu apply change.tfplan
```

Do not change inputs/source between plan and apply, use `-target`, or apply from
a different root. Remove the spent plan after recording its result. Protected
volumes intentionally block destroy; removing that protection is a separate
explicit data-retirement change. Preserve state on partial failure and re-plan.

For NixOS this starts a system-specific minimal seed, not the final services.
Continue with [readiness](readiness.md), [secrets](secrets.md) where required and
[activation](activation.md). OCI starts through its declared infrastructure and
uses [inference checks](inference.md). A successful apply proves neither health
nor authorization. Stop dependent operations at a failed prerequisite.
