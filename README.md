# Digital Garden

Henner's new IncusOS homelab, rebuilt incrementally from fresh desired state.

## Architecture

- OpenTofu owns Incus infrastructure and instance devices.
- NixOS owns guest services and configuration.
- Direct Incus OCI containers run suitable single applications.
- SOPS + age owns stable managed secrets; sops-nix delivers guest secrets at runtime. Plaintext secrets must never pass through OpenTofu.
- Caddy and Authelia share a NixOS edge container. Prefer native application OIDC.
- Open WebUI runs in a NixOS container; llama.cpp runs privately as an OCI container with AMD GPU access.
- Persistent application state lives on explicit volumes. Caddy owns its ACME state.
- Manual wildcard A/AAAA DNS for *.archaic.work remains outside automation. Public IPv6 needs explicit firewall policy.

The former mitschwimmer/homelab repository is reference material. No old state or data is imported.

## Iteration 0: establish current prerequisites

Goal: obtain actual host, GPU, network, storage and instance facts before provisioning.
Acceptance: all inventory commands succeed against the intended IncusOS host.

Run from a workstation with Bash, Git and an authenticated Incus client:

```sh
git clone https://github.com/mitschwimmer/digital-garden.git
cd digital-garden
git switch homelab/bootstrap-inventory
incus remote list
bash scripts/inventory.sh YOUR_REMOTE
```

The script only reads. It uses the client's selected project and does not enumerate other projects.
Review the output before sharing it in our conversation; host inventory can include addresses and hardware identifiers.
Do not commit inventory output to this public repository.

Also show the chosen private bridge configuration:

```sh
incus network show YOUR_REMOTE:YOUR_BRIDGE
```

Confirm whether this is a fresh IncusOS installation or the host still running the old setup.
Describe the router's current IPv4 port forwarding and IPv6 routing/firewall arrangement.
The example values measerve, local, incusbr0 and enp129s0 in the old repo are unconfirmed.

## Verify

Expected: the inventory exits zero and identifies the intended server, available storage, bridge and GPU.
If a command fails, report the command and error; do not provision around it.

Local validation: Bash syntax and an isolated mock-client execution, including missing/invalid arguments and read-only command selection.
Real-host execution is pending; no infrastructure has been deployed.

## Roll back

No host rollback is needed because this iteration performs no writes.
To discard the checkout, switch to main. The branch can be closed without changing the homelab.

## Next iteration

Create a private network and one minimal NixOS edge container that boots, using confirmed host facts.
Add HTTPS, Authelia, and applications in later independently verified iterations.

## Useful requirements from the old configuration

- Auth, Grafana, Prometheus, llama.cpp, Open WebUI and a shared Pi service are present in the old code; confirm which to recreate.
- llama.cpp uses a model router, persistent cache, an AMD physical GPU and /dev/kfd.
- Open WebUI's public example hostname is ai.archaic.work.
- The old base-domain example is mitschwimmer.de; the new skill baseline is archaic.work.
- The old code puts workload secret content into storage resources. That pattern will be replaced.

## CLI references

- https://linuxcontainers.org/incus/docs/main/reference/manpages/incus/info/
- https://linuxcontainers.org/incus/docs/main/reference/manpages/incus/network/list/
- https://linuxcontainers.org/incus/docs/main/reference/manpages/incus/storage/list/
- https://linuxcontainers.org/incus/docs/main/reference/manpages/incus/list/
