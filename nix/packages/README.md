# Open WebUI package backport

`open-webui.nix` updates the backend and frontend to 0.12.0 while retaining the
shared NixOS 26.05 pin. Source/npm hashes and the new `pyotp` and `qrcode`
dependencies follow [Nixpkgs PR 572794](https://github.com/NixOS/nixpkgs/pull/572794).
The existing frontend recipe, Pyodide pin and runtime packaging remain in use.
Override Python dependencies through `passthru.dependencies`, which the pinned
Python builder uses to calculate runtime inputs. Override the frontend and its
`npmDeps` fetch explicitly so both use the new source and dependency hash.

There is no local OIDC source patch. The operator intentionally accepts upstream
first/sole-user admin promotion and will initialize the application as its admin.
Upstream also owns missing-role handling and callback access logging.

Remove this backport when the shared locked package reaches 0.12.0 or newer;
review any newer package before removing it. The version assertion forces that
review on platform updates. Build the complete WebUI closure and verify OIDC,
existing data, inference integration and restart persistence before deployment.
Database rollback requires the matching pre-upgrade data backup.
