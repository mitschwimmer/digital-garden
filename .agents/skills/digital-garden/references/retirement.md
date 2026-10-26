# Retire one system deliberately

Identify its dependents, public routes, OIDC client, secrets and owned data.
Review a backup/retention plan before stopping the service. Withdraw any public
route in edge Nix and retire any OAuth client through an explicit
`present = false` identity declaration (`autoRemove = false` does not delete
omitted clients). Check the pinned provisioner's removal behavior in
[identity](identity.md): version 1.3.0 can delete an absent entity and then fail
while tracking its deleted name. Confirm actual deletion before removing a
redundant absence declaration and redeploying; do not retain a failing tombstone.
Revoke application sessions/API keys where required. For private
services, remove caller configuration and verify consumers handle withdrawal.
Apply/deploy integration owners in dependency order and test surviving services.

Operate only the retiring system's root. Review the full saved plan; do not
remove state records to hide surviving resources. Volumes have prevent_destroy,
so a whole-root destroy is intentionally blocked until data retirement is
separately authorized and that protection is deliberately changed. Keep archives,
keys and ciphertext together for the required recovery period.

Shared platform networking/projects must outlive their consumers. Retiring a
leaf does not authorize deleting platform, another root's state or another
system's volumes. Record what was deleted, retained and archived, then verify
caller and authorization behavior for surviving services.

After accepted removal, remove obsolete service registrations/configuration and
its service reference when no longer needed; preserve required tombstones and
private recovery records for their retention period. Update shared guidance only
if its concepts changed, not to remove a service name from another inventory.
