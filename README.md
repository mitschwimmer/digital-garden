# Digital garden

Experimental XML desired state for [Tend](https://github.com/archaic-java/tend), independent of
[mitschwimmer/homelab](https://github.com/mitschwimmer/homelab).

Tend monitors `main` and reads `incus.xml` plus referenced files from one immutable commit.
The active declaration is initially empty: no instances or volumes are requested.

`examples/first-slice.xml` demonstrates a custom filesystem volume, a configuration file, a
controller-generated secret and a running instance with explicit disk devices. It is illustrative,
not an operational application deployment. Its repeated `a` fingerprint is a placeholder.

To exercise it later in a disposable Incus project:

1. Bootstrap project `garden` and storage pool `pool`, or adjust their names in the XML.
2. Cache an appropriate container image in Incus and replace the placeholder with its full fingerprint.
3. Copy `examples/first-slice.xml` to `incus.xml`, retaining the `examples/service.conf` reference.
4. Commit to `main`; the separately bootstrapped Tend controller reconciles that commit.

The example uses a root disk and mounts `demo-data` at `/data`. The chosen image determines whether
anything consumes the example configuration or secret. Neither file makes an arbitrary image into
a service. Tend's controller state volume stores the stable generated `session` secret; Git contains
only its declaration and reference.

The schema and supported semantics live in Tend's `schema/tend.xsd` and README. The first slice
retains removed resources, rejects image/type replacement and uses stop/start configuration activation.
No credentials, generated secrets, Incus machine access or modifications to the existing homelab are
included here. Secret export and backup will be handled later.
