# Incus project guidance

## Choose boundaries by purpose

Use `default` for shared homelab infrastructure: the Caddy/Authelia edge guest, its certificate and identity state, its secret volume, and shared managed bridge networks. Retain the built-in project; Incus does not permit deleting or renaming it. Treat shared-service placement as this homelab's convention, not special service-discovery or authentication behavior supplied by Incus.

Group application workloads by common ownership, lifecycle, privileges, and resource budget. Keep an application and its dedicated database or workers together when their operation and recovery belong together. Avoid one project per instance or grouping by runtime alone. Create another project when a distinct access policy, hardware permission, capacity budget, or maintenance boundary justifies it.

Use this initial placement for the current baseline:

| Project | Workloads and owned volumes | Reason |
|---|---|---|
| `default` | Caddy/Authelia edge; certificate, identity, and edge-secret volumes; shared bridges | Shared ingress and identity infrastructure |
| `ai` | Open WebUI; user data and application secrets | User-facing AI application without GPU privileges |
| `inference` | llama.cpp; model cache and public configuration | GPU/KFD access and larger memory/storage requirements |

Re-evaluate future workloads rather than placing every application in `ai`. Describe each project's purpose and dependencies in the operator runbook.

## Configure resource scope explicitly

Instances always belong to one project; they are never inherited. For resource categories controlled by `features.*`, enabling the feature creates a project-local namespace; disabling it uses the corresponding namespace in `default`. This is sharing, not copying. For example, importing an image with `features.images=false` adds it to `default`. Do not model arbitrary parent projects or inheritance from `ai` or another named project.

Choose and declare feature settings before creating workloads, and verify changes against the target Incus version and pinned provider schema:

- Set `features.storage.volumes=true` and `features.profiles=true` for application projects. Keep their persistent volumes, secrets, and profiles with their workloads.
- Prefer `features.images=true` for application projects. Import the same immutable seed into each consuming project as needed; do not assume an image fingerprint imported into another project is available locally. Use shared images only as an explicit decision.
- Keep `features.networks=false` with the existing managed-bridge architecture. Those bridges belong to `default`; named projects use them subject to access restrictions. Project-local managed networks require OVN in the documented current implementation. Do not introduce OVN solely to avoid `default`; verify current support before changing network design.
- Treat storage pools as host-wide infrastructure, distinct from project-scoped volumes. A separate pool per project is not required.

Do not rely on creation defaults or confuse a project's `default` profile with the `default` project. Scope OpenTofu resources, data sources, activation commands, acceptance checks, exports, imports, and recovery instructions to the intended project explicitly.

## Separate permissions from connectivity

Reach Caddy and Authelia through explicitly configured network endpoints. Hosting them in `default` does not automatically grant another project ingress, OIDC configuration, or authentication. Project boundaries alone do not block packet traffic; document and enforce required paths with supported network ACLs and guest firewalls, including public IPv6 exposure.

Apply appropriate project restrictions and resource limits. Keep GPU/KFD exceptions in `inference`; permit NixOS nesting only where required. Verify restriction compatibility with actual NIC and disk devices, backups, activation, and recovery before applying. Shared bridges do not imply that every application should have LAN access. Keep operator administration separate from any delegated project access.

## Changes to an existing installation

Inspect resource identity and data impacts before changing project ownership.
A project-field edit is not a safe resource move by itself. Review replacement,
volume/image namespace and recovery effects separately. For surviving or restored
resources, use the [recovery procedure](recovery.md).

Sources: [Incus project semantics](https://linuxcontainers.org/incus/docs/main/explanation/projects/), [project features and restrictions](https://linuxcontainers.org/incus/docs/main/reference/projects/), and [project API implementation](https://github.com/lxc/incus/blob/main/cmd/incusd/api_project.go). Recheck version-sensitive capabilities against official documentation or pinned source.
