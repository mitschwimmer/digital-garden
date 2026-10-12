# Retire one system deliberately

Identify its dependents, public routes, OIDC client, secrets and owned data.
Withdraw the public route in edge Nix and retire the OAuth client through an
explicit `present = false` identity declaration. Review a backup/retention plan
before stopping the service. Verify remaining services still work.

Operate only the retiring system's root. Review the full saved plan; do not
remove state records to hide surviving resources. Volumes have prevent_destroy,
so a whole-root destroy is intentionally blocked until data retirement is
separately authorized and that protection is deliberately changed. Keep archives,
keys and ciphertext together for the required recovery period.

Shared platform networking/projects must outlive their consumers. Retiring a
leaf does not authorize deleting platform, another root's state or another
system's volumes. Record what was deleted, retained and archived, then verify
caller and authorization behavior for surviving services.
