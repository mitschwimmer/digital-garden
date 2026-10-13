# ADR: Use Kanidm as Identity Provider

**Status:** Accepted  
**Date:** 2026-10-12

## Context

A self-hosted identity provider is needed to provide centralized authentication for services running on NixOS.

The requirements are:

- Open-source software
- OpenID Connect (OIDC) support
- First-class passkey authentication (WebAuthn/FIDO2)
- Embedded database without external database dependencies
- Native NixOS integration
- Declarative management of users, groups, and OIDC clients
- Low operational complexity

Authelia, Pocket ID, Rauthy, and Kanidm were evaluated.

## Decision

**Use Kanidm as the identity provider.**

Kanidm provides an embedded database, passkey authentication, OIDC, and integrated identity management.

The decisive advantage is its **native NixOS provisioning module**, which supports declarative management of users, groups, and OIDC clients. This allows identity configuration to be version-controlled and deployed alongside the rest of the infrastructure.

## Alternatives Considered

| Alternative | Reason not selected |
|---|---|
| Authelia | File-based user management requires separate provisioning or an additional directory |
| Pocket ID | User and client provisioning is primarily UI/API-driven rather than natively declarative through NixOS |
| Rauthy | No comparably integrated declarative NixOS provisioning interface established |

All alternatives support embedded storage and passkey authentication.

## Consequences

**Positive:**
- Identity configuration follows the existing NixOS infrastructure-as-code approach.
- No external database or LDAP service is required.
- Users, groups, and OIDC clients can be provisioned declaratively.
- Passkeys provide modern passwordless authentication.

**Trade-offs:**
- Kanidm introduces its own identity-management concepts and provisioning lifecycle.
- Passkey credentials and other runtime identity state still require persistent storage and backups.
- OIDC compatibility must be verified for individual applications.

## References

- [Kanidm documentation](https://kanidm.github.io/kanidm/stable/)
- [NixOS Kanidm provisioning options](https://mynixos.com/options/services.kanidm.provision)
