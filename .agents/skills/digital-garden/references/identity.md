# Declare Kanidm through its NixOS module

- [Secret contract](#secret-contract)
- [Fresh bootstrap](#fresh-bootstrap)
- [OIDC and acceptance](#oidc-and-acceptance)
- [User lifecycle and credential enrollment](users.md)

`systems/identity/configuration.nix` owns server settings and OAuth clients;
`directory.nix` owns persons, groups and membership. All supported administrative
configuration is declared under `services.kanidm`, including `provision`.
Do not run imperative person/group/client setup scripts or make UI configuration
changes that compete with Nix. User password/passkey enrollment and databases
remain persistent runtime state, not Nix configuration.

The pinned nixpkgs module supports users, groups, OAuth2 scope/claim maps and
runtime secret files. `pkgs.kanidm_1_11.withSecretProvisioning` is the nixpkgs-managed
patched variant (Kanidm 1.11.2 at this pin) needed for stable admin and client secrets.
Use the matching versioned workstation client; the unversioned alias is removed.
When updating nixpkgs, retain this variant until upstream supports its interfaces
and fresh bootstrap plus restart/rotation checks pass without it. There is no
local Kanidm fork or custom provisioning service.

Provisioning uses explicit admin/idm-admin password files; omitting idm-admin
would reset its password on each restart. autoRemove is false: retain an explicit
`present = false` declaration for intentional entity deletion. Membership is
reconciled by the module; change authorization in Nix, not interactively.

## Secret contract

Identity consumes `admin` and `idm-admin` from `systems/identity/secrets.yaml`
as 0400 kanidm-owned files through native provisioning options. Application-specific
client declarations may live in imported modules with separate ciphertext; inspect
those imports and their owning service references. Do not replace existing admin
or unrelated client inputs when adding a client. Follow [secret delivery](secrets.md).

## Fresh bootstrap

1. Provision platform, then edge and identity seeds with separate inputs/state.
2. Deploy edge and configure DNS/public HTTP reachability as in [ingress](ingress.md).
3. Add real persons and mailAddresses to directory.nix; assign intended ai-users
   or admins membership. There is deliberately no guessed operator account.
4. Prepare [secrets](secrets.md), install identity's own age key, and stage ciphertext.
5. Deploy identity. NixOS ACME obtains identity.archaic.work through edge's
   challenge route; Kanidm requires a real certificate before startup. ACME
   renewals restart/reload Kanidm through the module. `/var/lib/acme` is persistent.
6. Use [credential enrollment](users.md#credential-enrollment) for each person;
   this is the sole human setup step after declared directory setup.

Provisioning connects locally to https://identity.archaic.work:8443 using a local
hosts entry and verified TLS. Public users use https://auth.archaic.work. No
hairpin connection through Caddy is needed for provisioning. If certificate
issuance fails, repair DNS/HTTP reachability and restart the failed ACME service,
then Kanidm; do not bypass TLS checks. Initial issuance needs outbound HTTPS.

## OIDC and acceptance

For each affected client, inspect its declaration/import and the consumer's
service reference for exact redirect URIs, scopes, claims and roles. Keep verified
TLS and PKCE enabled. Applications must enforce access; a successful login alone
does not grant permission. Coordinate matching secrets and deploy identity before
a dependent consumer when client contracts change. Preserve unrelated clients.

Require `systemctl is-active kanidm`, trusted external HTTPS, discovery and JWKS.
Test each affected client's allowed roles and a person without its allowed
membership (denied). Verify missing/unrelated claims cannot grant roles.
Test logout, reauthentication, credential enrollment and intended second-factor
behavior. Restart affected consumers and identity and repeat login/denial. Check
provisioning
returns the declared memberships/client settings without duplicating entities.
Back up Kanidm's database and keys together; see [recovery](recovery.md).

Sources: [pinned module](https://github.com/NixOS/nixpkgs/blob/26f4107e47e3ad0ffd0db220469ba83b6f6d96e8/nixos/modules/services/security/kanidm.nix),
[Kanidm OAuth2](https://kanidm.github.io/kanidm/stable/integrations/oauth2.html).
