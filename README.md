# Digital Garden

Self-hosted services on IncusOS: isolated operation roots, NixOS system
containers, Nix-configured Caddy, declaratively provisioned Kanidm, SOPS + age,
and direct OCI GPU inference. Published user applications require native OIDC.
[LAN-only WebDAV](.agents/skills/digital-garden/references/webdav.md) is an explicit
exception, using source filtering and application credentials for Enpass.
Caddy performs no user authentication and has no mutable configuration API.

Start with [Work on Digital Garden](.agents/skills/digital-garden/SKILL.md).
Humans and agents share this handbook. Each system owns its infrastructure state,
seed, build operations, secrets and persistent volumes. Shared source and pins
remain reusable. The guarded deployment command rejects wrong-system closures.

This layout targets a fresh installation after an operator-managed host reset.
There is no migration from the old monolithic state or Authelia installation.
Do not apply it over surviving old resources or copy old state into these roots.

Provision platform, then the individual systems. Deploy edge before identity
certificate bootstrap, and identity before WebUI or Immich authentication. Use a Nix
workstation and authenticated Incus client; builds never run on IncusOS.
Inspect storage, network roles, AMD support, DNS and router rules first.

CI checks deployment guards, provider schemas, module options, seeds and edge.
Full secret-consuming closure builds and live acceptance are separate gates;
a successful apply alone does not establish service health.

[Immich](.agents/skills/digital-garden/references/immich.md) runs natively in a
NixOS container: media on measerve's `data` pool, root/database on `local`, and
Kanidm OIDC at `photos.archaic.work`. Credentials and first-admin bootstrap
are explicit deployment prerequisites.
