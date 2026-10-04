---
name: maintain-digital-garden
description: Prepare and review the fresh-install seven-workload Tend garden and its public application configuration.
---

# Maintain digital garden

Use JDK 25/JPMS and Archaic Java when working on the owning Tend controller. This repository
contains public deployment state and a narrow Python standard-library preparation script.

- Read [installation and resource inventory](references/installation.md) before changing inputs,
  image pins, application configuration, private-volume bindings or deployment order.
- The source baseline is homelab `8fc54492c6d75d9713061703c5a6667347e1481b`; assets retain its
  current model IDs/settings and Pi installer release/checksum. Record deliberate differences.
- Require explicit reviewed public site inputs, real cached fingerprints, exact OCI source digests
  and platform. Never create an active deployment with placeholders or inferred LAN/GPU values.
- Keep identities, SMTP passwords, private TLS keys and generated values outside Git. Private
  inputs are operator-owned; application credentials are generated/retained by Tend.
- Prepare all seven workloads together. Keep protected Pi password-or-passkey one_factor for
  ai-users, Grafana admins policy and Open WebUI issuer ai-users gate. Preserve Pi's shared
  session/workspace, permitted non-Bash tools and normal outbound access.
- Run `python3 scripts/test-prepare.py`; Tend's `CompleteGardenProjection` additionally validates
  this exact recipe through XSD, semantic lowering and mock reconciliation. Keep resource/file
  order consistent with `schema/tend.xsd`, explicit IDs/modes and non-overlapping mounts.
- Disposable composition uses the same recipe with explicit local CA/controlled CPU substitutions,
  never a second simplified seven-workload XML graph. Keep evidence provenance and manual gates
  visible. Never contact the existing homelab during development.
