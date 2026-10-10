# Encrypted consumers

The existing files contain SOPS ciphertext; retain their stable values for
recovery. `.sops.yaml` records public age recipients. Machine keys live on the
edge/WebUI persistent secret volumes, with a separate operator recovery key and
secure backups outside this repository.

Follow [identities and encrypted inputs](../.agents/skills/digital-garden/references/secrets.md) to restore, update
recipients, or intentionally initialize an empty application installation.
Never regenerate existing cryptographic identities as a troubleshooting step.
`examples/` contains placeholders only. Never copy real plaintext into this tree,
OpenTofu inputs/state or a Nix derivation.
