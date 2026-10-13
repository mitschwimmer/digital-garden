# Compose or extend a service

1. Define purpose, callers, dependencies, state, secrets, hardware and rollback.
   Choose [placement](app-placement.md) and [project ownership](projects.md).
2. Declare infrastructure, private connectivity, limits and persistent mounts.
   Keep unrelated services independent; require mounts before writing state.
3. For NixOS, compose native modules and a flake configuration. For OCI, pin an
   upstream image and define supported configuration delivery before startup.
4. Add [ingress](ingress.md), [OIDC](identity.md) and [secret delivery](secrets.md#secret-delivery-for-a-new-service)
   only where required. Configure both integration endpoints; preserve existing
   clients, including WebUI. Verify allowed and denied access.
5. Document interfaces, operation and recovery. Reconcile infrastructure and
   deploy using the corresponding procedure only when live work is authorized.
   Verify the service and affected dependencies.

Use [Open WebUI](open-webui.md) as a composition example, replacing its names,
paths and policy deliberately. Keep protected volumes separate from off-host
backups; define and test restoration before relying on either.
