# Declare Kanidm through its NixOS module

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

Immich uses a separate staged client and the `photos-users` group; see
[Immich credentials and acceptance](immich.md). Its additional ciphertext does
not replace identity's existing admin or WebUI credentials.

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

WebUI uses client open-webui, callback https://ai.archaic.work/oauth/oidc/callback,
PKCE S256, client_secret_basic and discovery at
https://auth.archaic.work/oauth2/openid/open-webui/.well-known/openid-configuration.
The scope map grants openid/profile/email only to ai-users/admins. The custom
webui_roles claim returns those names as an array; WebUI reads that claim for
role management. Do not request the built-in groups scope: Kanidm fills groups
with UUIDs and SPNs, overwriting a custom claim of the same name. Applications
never infer permissions merely from a successful login. Keep TLS verification
and PKCE enabled.

For this claim migration, deploy identity first, then WebUI using
[deployment](deployment.md), and test fresh login after both deployments.
Kanidm's consent screen lists selected personal-information fields, not every
scope or custom claim; an email-only prompt does not prove roles are missing.

Require `systemctl is-active kanidm`, trusted external HTTPS, discovery and JWKS.
Test an enrolled ai-users person (user), an admins person (admin), and a person
without either group (denied). Verify missing/unrelated claims cannot grant roles.
Test logout, reauthentication, credential enrollment and intended second-factor
behavior. Restart identity and WebUI and repeat login/denial. Check provisioning
returns the declared memberships/client settings without duplicating entities.
Back up Kanidm's database and keys together; see [recovery](recovery.md).

Sources: [pinned module](https://github.com/NixOS/nixpkgs/blob/0d9e9b832d03ac387417e16ce1febf73b2e631e1/nixos/modules/services/security/kanidm.nix),
[Kanidm OAuth2](https://kanidm.github.io/kanidm/stable/integrations/oauth2.html).
