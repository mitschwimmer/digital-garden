# Permanent-domain Kanidm, staged for operator acceptance

This creates a **new Kanidm database** for the proposed permanent
identity domain **`auth.archaic.work`**. Its resources are independent
of the disposable `identity/kanidm-test` domain, database, credentials,
OpenEBS PVC and private CA. **Confirm the exact permanent domain
before the FIRST `kanidm-primary` sync:** Kanidm identity domains
cannot be renamed after database initialization.

The previous Kanidm installation at `auth.archaic.work` ran
**outside Kubernetes and has been deleted**, as confirmed by the
operator. This deployment **reuses the hostname only**; it creates
a new identity database, administrator credentials, and TLS key.
Old cached CLI tokens for the deleted server are not valid on the
fresh server and must not be reused. Isolate the new client's token
cache, as shown below. The wildcard DNS under `*.archaic.work`
should resolve to the current Talos Gateway; verify
`auth.archaic.work` before certificate issuance.

## Ownership and version contract

- `kanidm-primary-tls` Argo Application owns an `identity`-scoped
  cert-manager ACME `Issuer` and `Certificate`. The dedicated
  Let's Encrypt production account and leaf private key live in
  Kubernetes Secrets only, not in Git. HTTP-01 validation uses the
  existing `web-smoke/web-smoke` HTTP Gateway's port-80 listener.
  That Gateway admits solver `HTTPRoute` objects from *only*
  `identity` and `web-smoke` namespaces.
- `kanidm-primary` Argo Application owns the independent
  `identity/kanidm-primary` Kanidm CR. Kaniop v0.21.0 manages
  `kanidm/server:1.11.2`; keep the operator's version compatibility
  checks enabled. Kaniop creates the Service and admin passwords
  Secret; it does not create public Gateway routes.
- `kanidm-primary-route` Argo Application owns the
  `identity/kanidm-primary` TLSRoute. It attaches to a **new**
  `auth.archaic.work` TLS passthrough listener on the *existing*
  `web-smoke/web-smoke-https` Gateway (which remains owned by
  `web-smoke-https` and continues serving the HTTPS smoke site).
  This keeps all traffic encrypted end-to-end between browser and
  Kanidm, using Kanidm's **own** Let's Encrypt certificate.
- All new Argo children use manual synchronization and no prune.
  Neither the existing test instance nor the two public smoke
  websites is deleted or repurposed.

The new PVC is 10Gi RWO on OpenEBS `nvme`, with `Retain`; ensure
the Talos NVMe mount guard and existing Cilium/cert-manager/Kaniop
controllers remain healthy before introducing identity state.

**Data safety status:** no off-node backup, verified Kanidm restore,
or demonstrated persistence across a new Pod exists yet. The initial
deployment may be externally reachable for validation, but do **not**
enroll irreplaceable people, OIDC relying parties or external clients
or designate it production-ready before a verified backup/restore path.

## Deploy using Argo CD only

Run from the repository root in `nix develop`:

```sh
git pull --ff-only origin bootstrap/talos-foundation
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"
kubectl config set-context --current --namespace=argocd
argocd login --core
kubectl -n argocd get applications \
  web-smoke web-smoke-https kanidm-primary-tls kanidm-primary kanidm-primary-route
cilium status --wait
kubectl -n identity get kanidm,certificates,pvc
```

### 1. Enable the HTTP-01 route namespace

The `web-smoke` Application owns the HTTP Gateway listener which
was changed to accept routes only from the named `identity` and
`web-smoke` namespaces. Re-sync that child and verify the HTTP
smoke site still works:

```sh
argocd --core app sync web-smoke
kubectl -n web-smoke get gateway web-smoke -o yaml
curl --fail --show-error --resolve test.archaic.work:80:192.168.1.49 \
  http://test.archaic.work/
```

If the HTTP Gateway listener or the old HTTPRoute is not Accepted,
fix that before ACME issuance. This step does **not** expose Kanidm.

### 2. Issue a certificate in the identity namespace

Confirm `auth.archaic.work` resolves to the same public ingress as
`test.archaic.work`; check A and AAAA records and public port 80.
Then:

```sh
argocd --core app sync kanidm-primary-tls
kubectl -n identity get issuers,certificates,orders,challenges
kubectl -n identity wait --for=condition=Ready \
  certificate/kanidm-primary-tls --timeout=300s
kubectl -n identity get secret kanidm-primary-tls
```

If issuance fails, inspect the `Challenge` and temporary
`cm-acme-http-solver-*` HTTPRoute (namespace `identity`).
No DNS API credentials or additional LoadBalancer are required.
The current `identity-test-tls` private CA stays untouched.

### 3. Start the new Kanidm instance

**Confirm no earlier `kanidm-primary` database was initialized
under `idm.archaic.work` before the name correction.** If it was
already synchronized, stop and inspect before attempting the change:
the Kanidm domain is immutable. Otherwise `auth.archaic.work`
is the explicitly selected permanent domain.
Then:

```sh
argocd --core app sync kanidm-primary
kubectl -n identity get kanidm kanidm-primary
kubectl -n identity get sts,pods,svc,pvc
kubectl -n identity wait --for=condition=Ready pod \
  -l kanidm.kaniop.rs/cluster=kanidm-primary --timeout=300s
kubectl -n identity get secret kanidm-primary-admin-passwords
```

Retrieve passwords only in a private terminal. Do not print them into
shared logs or use `kanidmd recover-account` to regenerate credentials
behind Kaniop's back. Do not mount or copy the test's database or PVC.

### 4. Expose TLS passthrough on 443

`web-smoke-https` now declares a second, exact SNI listener
`auth.archaic.work` using `TLS` / `Passthrough`. It shares port
443 with the existing `secure-test.archaic.work` HTTPS listener.
The hostnames do **not overlap**; a wildcard HTTPS listener here
would risk conflicts. Check *each listener's* status.

```sh
argocd --core app sync web-smoke-https
kubectl -n web-smoke get gateway web-smoke-https -o yaml
argocd --core app sync kanidm-primary-route
kubectl -n identity get tlsroute kanidm-primary -o yaml
```

Require `Accepted=True` for the new TLS listener, the existing
HTTPS smoke listener, and `TLSRoute.status.parents[].conditions`.
If either listener is `Conflicted`, stop and revert the Gateway
change through GitOps, rather than accepting a broken prior service.
Cilium v1.20.4 can distinguish these exact TLS hostnames using SNI
on the same port. Envoy does **not** terminate Kanidm's TLS and
does **not** forward the original client source IP through this
TCP proxy; the server sees Envoy's source address.

Verify both endpoints (no `-k`, no custom CA file):

```sh
curl --fail --show-error --verbose \
  --resolve auth.archaic.work:443:192.168.1.49 \
  https://auth.archaic.work/status
curl --fail --show-error --verbose \
  --resolve secure-test.archaic.work:443:192.168.1.49 \
  https://secure-test.archaic.work/
```

Repeat the `auth.archaic.work` request **without** `--resolve`
from an external network, then open
**https://auth.archaic.work/** in a browser and inspect the publicly
trusted certificate.

For CLI auth, isolate new tokens from stale sessions cached for the
deleted, pre-Kubernetes `auth.archaic.work` server and from the
disposable `idm.localhost` test:

```sh
export KANIDM_TOKEN_CACHE_PATH="$PWD/.operations/kanidm-primary/tokens"
mkdir -p "$PWD/.operations/kanidm-primary"
chmod 700 "$PWD/.operations/kanidm-primary"
kanidm login -H https://auth.archaic.work -D idm_admin@auth.archaic.work
kanidm self whoami -H https://auth.archaic.work -D idm_admin@auth.archaic.work
```

Store the generated password privately and never paste it into chat.

## Before production identities

Establish an **off-host** Kanidm-consistent database backup, its
decryption/restore key custody, documented secrets/CA recovery, and
perform a restore to a disposable environment with login success.
Independently verify the certificate renews and Kanidm uses renewed
key material after cert-manager's Secret rotates. Restore behavior,
high availability and node reboot are not implied by successful
login. A single Talos VM remains a single failure domain.

References:
- [TLS runbook](../identity-certificates/README.md)
- [Test instance runbook](../kanidm/README.md)
- https://gateway-api.sigs.k8s.io/guides/user-guides/tls-routing/
- https://cert-manager.io/docs/configuration/acme/http01/
