# Operate Open WebUI

`systems/open-webui/` owns the NixOS application, ai/open-webui instance, seed,
state and machine key. It uses the [pinned package backport](../../../../nix/packages/README.md).
It depends on Kanidm for native OIDC, edge for public HTTPS and the private
inference endpoint for chat. Configuration comes from Nix on every startup;
ENABLE_PERSISTENT_CONFIG is false. No local password login or proxy-header auth.

For initial creation, provision this root and prepare its [secrets](secrets.md).
For configuration rollout, run
[deployment](deployment.md) from systems/open-webui. Identity must have the matching
client secret and directory declarations. Check `/var/lib/open-webui` and
`/var/lib/garden-secrets` are real mounts before deploying. UID/GID 990 belongs
to the application; root reads the 0400 environment file through systemd.

The OIDC webui_roles claim maps ai-users to user and admins to admin; unmatched users
remain pending/denied. The issuer scope map denies unrelated users. Upstream
first/sole-user admin promotion still exists: the operator must log in first
with the intended admins account, then verify ordinary-user and denied-user
behavior. Do not let an ordinary user initialize an empty database.

```fish
incus exec YOUR_REMOTE:open-webui --project ai -- systemctl is-active open-webui
incus exec YOUR_REMOTE:open-webui --project ai -- curl --fail --connect-timeout 5 --max-time 30 http://127.0.0.1:8080/health
```

Require browser login via https://ai.archaic.work, correct user/admin roles,
denial of a person without allowed membership, and successful generated chat.
Test missing/unrelated role claims as well as successful authentication.
Check inference from this actual caller, then restart and verify login, chat data
and secret-key persistence. Configuration/API catalog success alone is not chat.

On failure inspect WebUI journal, discovery/JWKS TLS, callback, scope/claim mapping,
matching client secrets and inference reachability. Never re-enable local login
or disable TLS to bypass an OIDC failure. Roll back configuration with matching
application data when a schema migration occurred.
