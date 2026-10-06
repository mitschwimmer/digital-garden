# Pinned Open WebUI exception

`open-webui-oidc.patch` is a package source patch, applied by Nix's native patch
phase to WebUI 0.11.4 from the locked Nixpkgs revision. It prevents first/sole-user
admin promotion bypassing configured IdP roles, rejects missing roles even when
userinfo rather than the access token supplies claims, and disables callback
access logging. Native environment options do not fix these pinned-source paths.

Cost: review the four authorization replacements and two logging replacements
on every WebUI upgrade. Remove each hunk when upstream enforces the same behavior
or provides the equivalent setting. A changed source must pass the full package
build and the runbook's first/sole-user, denied-group and normal-login tests;
patch application alone does not prove authorization.

Upstream: https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/utils/oauth.py
and https://github.com/open-webui/open-webui/blob/v0.11.4/backend/open_webui/__init__.py.
