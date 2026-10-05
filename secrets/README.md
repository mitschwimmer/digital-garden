# Edge secrets

Run scripts/prepare-auth.py after attaching the protected edge-secrets and Authelia state volumes.
It creates secrets/edge.yaml (SOPS ciphertext) and .sops.yaml (public age recipients).
Only these two generated files belong in Git. The script refuses to overwrite existing ciphertext.
The private operator recovery key is stored outside the repository; back it up securely.
The guest age key is stored on /var/lib/garden-secrets, never in OpenTofu state.

Do not replace JWT, session or storage keys when changing SMTP/users. In particular, replacing
the storage encryption key breaks access to existing encrypted Authelia data.
Password reset is disabled: edit the encrypted user database explicitly.
Use SOPS_AGE_KEY_FILE pointing to the operator key and sops secrets/edge.yaml for deliberate updates.
The users and smtp fields are JSON strings delivered as runtime files.
