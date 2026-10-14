# Create a system-specific NixOS seed

From the selected NixOS root (`systems/edge`, `systems/identity`, or
`systems/open-webui`, or `systems/immich`), build only its seed. Example for identity:

```fish
nix build ../..#identity-image --out-link result-seed
readlink -f result-seed
```

Put that immutable store directory in this root's local `image_directory` input.
The archive directory contains metadata.tar.xz, rootfs.tar.xz and garden-system.
OpenTofu checks that garden-system matches this root. Each seed also embeds its
hostname and `/etc/garden-system`; no generic edge seed is reused for WebUI.
The seed contains no application service or credentials.

Preserve the seed GC root and archive used for creation; do not replace
`image_directory` during a service update. Use a separate validation output when
checking a new seed definition. An image change may replace a disposable guest;
review it independently from service deployment and persistent data.

Apply this root using [infrastructure reconciliation](infrastructure.md), then
check [readiness](readiness.md). Install the consumer's machine key only on its
verified persistent mount. Build/deploy the full system with
[deployment](deployment.md); successful provisioning is not service readiness.
