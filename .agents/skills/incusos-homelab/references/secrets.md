# Secrets with SOPS + age

## Goals

Keep encrypted secrets in Git while preventing plaintext values from appearing in Git history, Nix store paths, OpenTofu configuration/state, normal logs, or documentation.

## Source of truth

Use SOPS files encrypted to age recipients. Keep `.sops.yaml` and all age **public** recipients in Git. Never commit age private identities.

Organize by lifecycle/consumer rather than putting every secret into one global file, for example:

```text
secrets/
├── edge.yaml
├── open-webui.yaml
└── grafana.yaml
```

Keep at least one securely backed-up operator age private key capable of recovery.

## NixOS delivery

Use `sops-nix`.

- Decrypt secrets to runtime files, normally under `/run/secrets`.
- Set narrow owner/group/mode values.
- Feed services file paths, systemd credentials, or an environment file rather than interpolating plaintext into Nix expressions.
- Keep any machine age key or SSH host key used for decryption persistent across guest rebuilds.

For Authelia, use the NixOS module's secret-file options for stable cryptographic material such as storage encryption keys, JWT/session-related secrets, OIDC HMAC material, signing private keys, and OIDC client secrets as applicable to the module/version.

For Open WebUI, prefer the NixOS module/service's environment-file mechanism populated from sops-nix when the required setting is environment-variable based.

## OCI delivery

Do not put decrypted secret values into OpenTofu-managed resource attributes or ordinary variables.

Prefer, in order:
1. application-supported secret files mounted read-only,
2. a runtime/deployment step that places decrypted files into a protected Incus volume without routing plaintext through OpenTofu state,
3. moving the workload to a NixOS system container when secrets are numerous or environment-only and the OCI workaround would become bespoke infrastructure.

If a small secret-sync helper is introduced later, keep it deterministic, auditable, and narrowly scoped. Ensure it never writes decrypted material into the repository or Terraform/OpenTofu state.

## Rotation

Treat secret rotation as an explicit change:
1. generate/replace secret material without printing it,
2. re-encrypt the SOPS file,
3. update both sides of an integration in one iteration where required,
4. deploy,
5. verify authentication,
6. revoke/remove obsolete credentials if the application/provider supports overlap.

Never rotate stable encryption/signing keys casually; understand data/session consequences first.

## Fresh installation versus recovery

Document both paths with existing age/SOPS/Incus commands; do not introduce an initialization program by default.

For a fresh installation, establish an operator recovery identity outside the checkout, persistent machine identities, public recipients, and new encrypted consumer files. Keep prompts and secret-bearing files out of Git, logs and ordinary IaC inputs.

For a rebuild, recover the encrypted consumer files and operator identity first. Restore existing machine identities into their persistent locations, or establish replacement machine identities and update SOPS recipients using operator access. Preserve the decrypted secret values during recipient changes: rebuilding a guest must not rotate storage encryption keys, OIDC credentials or signing identities.

Explain how to verify decryption privately on the intended consumer and restore matching application databases/state. Verify identities and data together where encryption couples them. Keep the recovery operator key backed up separately from the host.

Handle OpenTofu state recovery explicitly: restore the backed-up state when applicable, or document a reviewed native import/reconstruction procedure. Do not blindly apply stale state to a reset host. Establish which resources and volumes survived before choosing the recovery path.
