# Declare Kanidm through its NixOS module

- [User lifecycle](#user-lifecycle)
- [Fresh bootstrap](#fresh-bootstrap)
- [OIDC and acceptance](#oidc-and-acceptance)
- [Credential enrollment](#credential-enrollment)

`systems/identity/configuration.nix` owns server settings and OAuth clients;
`directory.nix` owns persons, groups and membership. All supported administrative
configuration is declared under `services.kanidm`, including `provision`.
Do not run imperative person/group/client setup scripts or make UI configuration
changes that compete with Nix. User password/passkey enrollment and databases
remain persistent runtime state, not Nix configuration.

The pinned nixpkgs module supports users, groups, OAuth2 scope/claim maps and
runtime secret files. `pkgs.kanidm_1_11.withSecretProvisioning` is the nixpkgs-managed
patched variant (Kanidm 1.11.2 at this pin) needed for stable admin and client secrets.
Use the matching versioned workstation client; the unversioned kanidm alias is removed. Retain the pinned
revision; remove this variant only when upstream supports those interfaces and
fresh bootstrap plus restart/rotation checks pass without it. There is no local
Kanidm fork or custom provisioning service.

Provisioning uses explicit admin/idm-admin password files; omitting idm-admin
would reset its password on each restart. autoRemove is false: retain an explicit
`present = false` declaration for intentional entity deletion. Membership is
reconciled by the module; change authorization in Nix, not interactively.

## User lifecycle

These are Kanidm people who sign in to applications. NixOS `users.users` entries
are guest-local accounts (including service identities); Kanidm enrollment does
not grant shell/Incus access. Keep stable service UIDs and volume ownership when
changing guest accounts through their owning NixOS configuration.

### Add a person or change roles

1. Confirm the person's account name, display name, mail address and intended
   access. Preserve an enrolled working administrator. Back up identity state
   before directory changes; see [recovery](recovery.md).
2. Edit `systems/identity/directory.nix`. Add the person and extend the existing
   membership list without dropping other members. For example, add these
   entries inside `services.kanidm.provision` (replace example details):

   ```nix
   persons.alex = {
     displayName = "Alex";
     mailAddresses = [ "alex@example.org" ];
   };
   groups.ai-users.members = [ "henner" "alex" ];
   ```

   Keep `groups.admins.members` unchanged unless administrator access is intended.
   For role changes, edit the existing group lists; do not create a second owner
   using person-level group declarations. Account names must be unique across
   persons, groups and OAuth clients. Treat a rename as an identity migration,
   not a display-name edit; application accounts/data may reference the old identity.
3. Validate/build identity using [validation](validation.md), then activate from
   `systems/identity` using [activation](activation.md). Provisioning runs as
   Kanidm's startup step; require successful activation and inspect its journal
   for reconciliation failures. No infrastructure apply is needed for directory
   changes alone.
4. For a new person, use [credential enrollment](#credential-enrollment) below
   and deliver the reset link privately. Existing persons retain credentials
   when changing display name, mail address or membership.
5. Test fresh login and the intended WebUI role, denied access for an unassigned
   person, and continued administrator access. For a downgrade, also check
   existing sessions and API tokens; new OIDC claims alone are not proof that
   previously issued application access has ended.

### Remove a person

1. Identify memberships, application accounts/data, active sessions and API tokens.
   Decide data retention separately from access removal; preserve working operator
   access and back up identity before deletion.
2. Remove the name from every declared group membership list and replace that
   person's declaration with an explicit tombstone:

   ```nix
   persons.alex = { present = false; };
   ```

   Keep `autoRemove = false`. Omitting the entry does not delete the existing
   person. A remaining group reference to a person marked absent fails the
   pinned module's entity validation. Retain the tombstone while any installation
   may still contain the account.
3. Validate/build and activate identity as above. Verify reconciliation completed,
   the person is absent and fresh authentication fails. Verify surviving users
   and administrator access still work.
4. Inspect each affected application's supported session/token revocation and
   account-retention controls. Revoke remaining access there and test a previously
   authenticated session/token as well as fresh OIDC login. Kanidm deletion does
   not establish that WebUI sessions, API keys or application data were removed.
   Record pending revocation explicitly; do not claim offboarding is complete
   while existing access remains.

For a failed activation, inspect the attempt record and repair/retry or use
[activation rollback](activation.md#resume-and-rollback). Directory deletion is
persistent database state: rolling back a NixOS closure does not undo it. A prior
person declaration may recreate an account without its former credentials or
application linkage; recover the matching identity backup when those must be
restored. Never restore a directory backup casually: it can restore revoked access
for other people too.

## Fresh bootstrap

1. Provision platform, then edge and identity seeds with separate inputs/state.
2. Activate edge and configure DNS/public HTTP reachability as in [ingress](ingress.md).
3. Add real persons and mailAddresses to directory.nix; assign intended ai-users
   or admins membership. There is deliberately no guessed operator account.
4. Prepare [secrets](secrets.md), install identity's own age key, and stage ciphertext.
5. Activate identity. NixOS ACME obtains identity.archaic.work through edge's
   challenge route; Kanidm requires a real certificate before startup. ACME
   renewals restart/reload Kanidm through the module. `/var/lib/acme` is persistent.
6. Enroll each person's credentials/passkeys using Kanidm's supported enrollment
   flow. Enrollment is the sole human setup step after declared directory setup.

Provisioning connects locally to https://identity.archaic.work:8443 using a local
hosts entry and verified TLS. Public users use https://auth.archaic.work. No
hairpin connection through Caddy is needed for provisioning. If certificate
issuance fails, repair DNS/HTTP reachability and restart the failed ACME service,
then Kanidm; do not bypass TLS checks. Initial issuance needs outbound HTTPS.

## OIDC and acceptance

WebUI uses client open-webui, callback https://ai.archaic.work/oauth/oidc/callback,
PKCE S256, client_secret_basic and discovery at
https://auth.archaic.work/oauth2/openid/open-webui/.well-known/openid-configuration.
The scope map grants access only to ai-users/admins. The groups claim explicitly
returns those names as an array; applications never infer permissions merely
from a successful login. Keep TLS verification and PKCE enabled.

Require `systemctl is-active kanidm`, trusted external HTTPS, discovery and JWKS.
Test an enrolled ai-users person (user), an admins person (admin), and a person
without either group (denied). Verify missing/unrelated claims cannot grant roles.
Test logout, reauthentication, credential enrollment and intended second-factor
behavior. Restart identity and WebUI and repeat login/denial. Check provisioning
returns the declared memberships/client settings without duplicating entities.
Back up Kanidm's database and keys together; see [recovery](recovery.md).

Sources: [pinned module](https://github.com/NixOS/nixpkgs/blob/0d9e9b832d03ac387417e16ce1febf73b2e631e1/nixos/modules/services/security/kanidm.nix),
[Kanidm OAuth2](https://kanidm.github.io/kanidm/stable/integrations/oauth2.html).

## Credential enrollment

After declaring the person in Nix and activating identity, authenticate the
workstation client interactively with the provisioned idm-admin password. Keep
the password out of arguments and shell history. For an existing declared person:

```fish
kanidm login --url https://auth.archaic.work --name idm_admin
kanidm person credential create-reset-token PERSON_NAME --url https://auth.archaic.work --name idm_admin
```

Run in a private operator terminal: the returned enrollment URL/token is a
credential. Deliver it securely to the intended person; do not paste it into
logs, PRs or chat. The person opens it and enrolls the required passkey/MFA.
This enrolls credentials only; persons, membership and clients remain Nix-owned.
See [Kanidm credential enrollment](https://kanidm.github.io/kanidm/stable/accounts/authentication_and_credentials.html).
