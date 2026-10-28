# Manage Kanidm users

Use [identity](identity.md) for server, client or provisioning-interface changes.
For source-only work, edit and validate; perform backups, deployment, enrollment
and live access checks only when that live work is requested.

- [Add a person or change roles](#add-a-person-or-change-roles)
- [Remove a person](#remove-a-person)
- [Credential enrollment](#credential-enrollment)

These are Kanidm people who sign in to applications. NixOS `users.users` entries
are guest-local accounts (including service identities); Kanidm enrollment does
not grant shell/Incus access. Keep stable service UIDs and volume ownership when
changing guest accounts through their owning NixOS configuration.

## Add a person or change roles

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
3. Validate/build identity using [directory checks](validation.md#select-checks).
   For rollout, use [deployment](deployment.md) from `systems/identity`. Provisioning runs as
   Kanidm's startup step; require successful deployment and inspect its journal
   for reconciliation failures. No infrastructure apply is needed for directory
   changes alone.
4. For a new person, use [credential enrollment](#credential-enrollment) below
   and deliver the reset link privately. Existing persons retain credentials
   when changing display name, mail address or membership.
5. Test fresh login and the intended roles in each affected application, denied
   access for an unassigned person, and continued administrator access. For a downgrade, also check
   existing sessions and API tokens; new OIDC claims alone are not proof that
   previously issued application access has ended.

## Remove a person

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
3. Validate/build and deploy identity as above. Verify reconciliation completed,
   the person is absent and fresh authentication fails. Verify surviving users
   and administrator access still work.
4. Inspect each affected application's supported session/token revocation and
   account-retention controls. Revoke remaining access there and test a previously
   authenticated session/token as well as fresh OIDC login. Kanidm deletion does
   not establish that application sessions, API keys or data were removed.
   Record pending revocation explicitly; do not claim offboarding is complete
   while existing access remains.

For a failed deployment, inspect the journal and selected generation, then repair/retry or use
[deployment rollback](deployment.md#resume-and-rollback). Directory deletion is
persistent database state: rolling back a NixOS closure does not undo it. A prior
person declaration may recreate an account without its former credentials or
application linkage; recover the matching identity backup when those must be
restored. Never restore a directory backup casually: it can restore revoked access
for other people too.

## Credential enrollment

After declaring the person in Nix and deploying identity, authenticate the
workstation client interactively with the provisioned idm-admin password. Keep
the password out of arguments and shell history. For an existing declared person:

```bash
kanidm login --url https://auth.archaic.work --name idm_admin
kanidm person credential create-reset-token PERSON_NAME --url https://auth.archaic.work --name idm_admin
```

Run in a private operator terminal: the returned enrollment URL/token is a
credential. Deliver it securely to the intended person; do not paste it into
logs, PRs or chat. The person opens it and enrolls the required passkey/MFA.
This enrolls credentials only; persons, membership and clients remain Nix-owned.
See [Kanidm credential enrollment](https://kanidm.github.io/kanidm/stable/accounts/authentication_and_credentials.html).
