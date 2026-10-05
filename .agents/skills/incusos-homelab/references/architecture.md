# Architecture and ownership

## Baseline

Internet traffic reaches Caddy on a NixOS edge container through manually configured DNS and router/firewall rules. Authelia shares that guest and remains behind Caddy. Open WebUI runs in a private NixOS system container with native Authelia OIDC. llama.cpp runs directly as a private Incus OCI container with explicit AMD GPU/KFD devices.

Keep the Open WebUI-to-llama path private. Verify actual network reachability and document trusted callers; bridge separation alone is not an access-control policy.

## Ownership boundaries

| Concern | Authoritative owner |
|---|---|
| Incus resource lifecycle, image digest, limits, devices and mounts | OpenTofu |
| OCI process launch settings and simple non-secret provider-supported configuration delivery | OpenTofu |
| NixOS packages, services, guest network/firewall and application configuration | NixOS |
| Optional generated non-secret configuration artifact | Nix |
| Stable credentials and cryptographic identity | SOPS plus age |
| Runtime guest secret files | sops-nix |
| Database, uploads, model cache and ACME state | Application on explicit persistent storage |
| Application/acceptance sequence | Operator runbook using native commands |

Select one authoritative owner per setting. Do not maintain duplicate launch settings or generate application configuration independently in HCL, Nix and helper scripts.

## Direct OCI configuration

Use upstream images pinned by immutable digest. Prefer arguments, non-secret environment settings or application-supported files using the existing provider/runtime interfaces. Public ordinary configuration may enter OpenTofu state; secret plaintext may not.

Use Nix generation only when it improves configuration clarity or reproducibility. Keep delivery as a documented native command or provider operation where practical. Do not require a derived image, registry publishing pipeline, installer, or custom deployment engine just to distribute a small configuration file.

If delivery requires a separate activation step, specify readiness and restart behavior. A host reboot between instance creation and configuration delivery must not unexpectedly start an unprepared service. Document who owns running state and how drift or a failed activation is reconciled.

Prefer application-owned model downloads/cache to a separate model installer. Distinguish pinned source identity from verified downloaded bytes; naming a file after a checksum does not check its contents.

## Infrastructure versus guest updates

Keep seed image identity separate from ongoing NixOS guest configuration. Guest maintenance must not unintentionally replace the instance or its data. Document closure build, transfer, activation, verification and previous-generation restoration with existing tools.

Keep stateful volumes independently recoverable. Persistence and deletion protection help guest replacement but do not protect against host/storage loss.

## Identity and public ingress

Keep public URL, callback URI, issuer, client ID, scopes and claims in ordinary configuration. Encrypt client secrets and signing/private material. Verify authorization as well as successful login.

Use Caddy for explicit hostname certificates; wildcard DNS does not require wildcard certificates or DNS-01. Let Caddy persist and rotate ACME state. Record manual A/AAAA and router arrangements, including the actual public IPv6 path to edge. Keep backend services and management listeners private.
