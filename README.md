# Digital garden

Experimental XML desired state for [Tend](https://github.com/archaic-java/tend), independent of
[mitschwimmer/homelab](https://github.com/mitschwimmer/homelab).

Tend monitors `main` and reads `incus.xml` plus referenced files from one immutable commit.
The active declaration is initially empty: no instances or volumes are requested.

`examples/first-slice.xml` demonstrates a named Configuration and controller-generated Secret,
consumed as read-only mounts beside a persistent data volume and explicit Incus disk devices.
`examples/requirements.xml` adds Caddy/Authelia ingress with two-factor group authorization and
an OVN NIC egress allowlist. Both are review fixtures with placeholder image fingerprints.
Neither example supplies a complete application configuration or working service image.

To exercise it later in a disposable Incus project:

1. Bootstrap project `garden` and storage pool `pool`, or adjust their names in the XML.
2. Cache an appropriate container image in Incus and replace the placeholder with its full fingerprint.
3. Copy `examples/first-slice.xml` to `incus.xml`, retaining the `examples/service.conf` reference.
4. Commit to `main`; the separately bootstrapped Tend controller reconciles that commit.

The first example mounts data at `/data`, configuration at `/etc/demo/service.conf` and the secret
at `/run/secrets/session/value`. The chosen image must consume those files. Tend stores the stable
named secret on its own persistent state volume; Git contains its generator and reference only.

The requirements example additionally needs a separately bootstrapped managed OVN network named
`garden-net`, cached service images and their startup configuration. The current homelab bridge is
not accepted by the experimental egress adapter. Caddy must load `/etc/caddy/Caddyfile`; Authelia
must load its separately provided base configuration, followed by Tend's access-control JSON via
`X_AUTHELIA_CONFIG`. That base configuration must supply authentication, sessions, storage and
notifier settings and must not define competing access-control rules. Image command-line arguments
must not override the binding. DNS, TLS reachability and protection from direct backend access are
operator concerns. This is not a complete replacement of the current OIDC-enabled homelab.

Read Tend's [resource model](https://github.com/archaic-java/tend/blob/offline-proof-of-concept/docs/resource-model.md)
for the exact model, enforcement boundaries and remaining requirements.

The schema and supported semantics live in Tend's `schema/tend.xsd` and README. The first slice
retains removed resources, rejects image/type replacement and uses stop/start configuration activation.
No credentials, generated secrets, Incus machine access or modifications to the existing homelab are
included here. Secret export and backup will be handled later.
