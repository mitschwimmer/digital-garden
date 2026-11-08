# Test identity TLS via cert-manager

The Garden uses cert-manager as the certificate issuer. Cilium Gateway API
(and Envoy) only consumes TLS Secrets referenced by a Gateway; it does not
provide this issuer. This first step **does not change** Cilium or enable
Gateway API: the bootstrap Cilium Helm values still have
`gatewayAPI.enabled: false`.

## Status and compatibility gate

- Official chart: `oci://quay.io/jetstack/charts/cert-manager` **v1.21.3**
  (https://cert-manager.io/docs/installation/helm/).
- Upstream cert-manager v1.21 is officially supported on Kubernetes
  **1.33–1.36**, not the Garden's **v1.37.1**. Treat deployment as an
  explicitly *experimental compatibility test*. Verify admission
  webhooks and issuance before depending on it.
- `cert-manager` and `identity-test-tls` are separate Argo CD
  Applications with **manual synchronization and no prune**.
- The `identity-test-tls` Application creates namespace-scoped Issuers
  and Certificates in the existing `identity` namespace. It does not
  deploy Kanidm or publish an HTTPRoute/Ingress.
- A local self-signed root CA (`kanidm-test-ca`) signs only the test
  `idm.localhost` leaf (`kanidm-test-tls`). Its private key is held in
  a Kubernetes Secret, **not Git**. Neither the CA nor leaf is publicly
  trusted. No real user identity, credentials or production clients
  should depend on them. Backups and CA-key custody are **not solved**.

## Stage 1: cert-manager controller

From the repository root in `nix develop`, with the kubeconfig for the
working Garden cluster:

```sh
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"
kubectl config set-context --current --namespace=argocd
argocd login --core

kubectl get node
kubectl -n argocd get application garden-root cert-manager identity-test-tls
helm list -A
kubectl -n cert-manager get deployments --ignore-not-found
kubectl get crd certificates.cert-manager.io --ignore-not-found
kubectl -n identity get secret kanidm-test-ca kanidm-test-tls --ignore-not-found
```

Stop and inspect ownership if those names already exist: do not let
cert-manager silently adopt an unrelated Secret or overwrite manually
issued certificates. Kaniop is already installed separately and must
remain healthy throughout the test.

**Stop** if cert-manager is already installed under another owner. There
must be only one cert-manager controller/CRD owner. Inspect the pinned
chart render on the workstation (CRDs, RBAC, webhook and startup check):

```sh
mkdir -p .operations/cert-manager
helm template cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version v1.21.3 \
  --namespace cert-manager \
  --set crds.enabled=true \
  --set crds.keep=true \
  > .operations/cert-manager/rendered.yaml
```

Review the file for cluster-scoped webhook/CRD changes. The root
Application only registers the child; **manual sync** is needed:

```sh
argocd --core app sync cert-manager
kubectl -n cert-manager get deployments,pods,jobs
kubectl -n cert-manager rollout status deployment/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deployment/cert-manager-webhook --timeout=180s
kubectl -n cert-manager rollout status deployment/cert-manager-cainjector --timeout=180s
kubectl get crd certificates.cert-manager.io issuers.cert-manager.io
argocd --core app get cert-manager --refresh
```

Require the controller, webhook, cainjector and CRDs to be healthy
before going on. If an installation fails, inspect the Application's
operation state, controller logs and cert-manager events. Never
reinstall over an existing release or delete its CRDs as a shortcut.

## Stage 2: private CA and leaf issuance

Only after cert-manager is ready, sync the independent test TLS child:

```sh
argocd --core app sync identity-test-tls
kubectl -n identity get issuers,certificates
kubectl -n identity wait --for=condition=Ready certificate/kanidm-test-ca --timeout=180s
kubectl -n identity wait --for=condition=Ready certificate/kanidm-test-tls --timeout=180s
kubectl -n identity get secret kanidm-test-ca kanidm-test-tls
```

The child has explicit Argo CD sync waves: bootstrap SelfSigned Issuer,
CA Certificate, CA Issuer, then leaf Certificate. If a wave completes
before the previous Certificate becomes Ready, check issuer conditions
and certificate events; let cert-manager reconcile instead of
generating key material manually.

Inspect the leaf certificate for identity, issuer and dates without
printing the private key. Export **only the public CA certificate** to
verify subsequent HTTPS from the workstation:

```sh
mkdir -p .operations/kanidm-test
chmod 700 .operations/kanidm-test
kubectl -n identity get secret kanidm-test-ca \
  -o jsonpath='{.data.tls\.crt}' | base64 --decode > .operations/kanidm-test/ca.crt

kubectl -n identity get certificate kanidm-test-tls -o json \
  | jq '{ready: .status.conditions, notAfter: .status.notAfter, renewalTime: .status.renewalTime}'
openssl x509 -in .operations/kanidm-test/ca.crt -noout -subject -dates
```

The issued leaf is stored in the Kubernetes
`kubernetes.io/tls` Secret `identity/kanidm-test-tls`; Kaniop's
existing `Kanidm.spec.tlsSecretName` points there. Do not reveal the
Secret's `tls.key` or copy it to Git. **Only then**, after checking
OpenEBS `nvme`/mount guard, sync `kanidm-test` and verify HTTPS using
the public CA, as documented in `../kanidm/README.md`.

## Preparing Let's Encrypt HTTP-01 (not deployed yet)

**Decision, 2026-11-08:** use **HTTP-01**, not DNS-01, to avoid
granting the cluster DNS-provider API access. The operator has explicitly
deferred further disposable Kanidm person/data-persistence testing.
The existing `idm.localhost` leaf and CA stay unchanged. Public ACME
cannot issue for `localhost` names. A future real Kanidm installation
will need a new FQDN **and a new database**; the test DB's domain is
immutable.

HTTP-01 verifies the response to
`http://<REAL_FQDN>/.well-known/acme-challenge/<TOKEN>` on **public
TCP port 80**. It still requires control of an ordinary public A/AAAA
record, but **no DNS automation or DNS API credentials**. It does not
support wildcard certificates. The port-80 challenge must be reachable
for renewals too; it cannot be a one-time firewall exception.

### Prerequisites / stop conditions

1. Select a permanent or throwaway **publicly resolvable hostname**
   under a domain controlled by the operator, and an ACME account email.
   Verify CAA restrictions when present. Never reuse `idm.localhost`.
2. Establish how worldwide inbound **TCP/80** reaches the cluster's
   Envoy gateway. The VM currently has the private LAN address
   `192.168.1.49`. The operator reports **router TCP/80 and TCP/443
   forwards to this address**, but an external connection has **not**
   been validated, and public-IP, upstream firewall, ISP, and CGNAT
   status remain unknown. Port 80 is sufficient for initial HTTP-01;
   disable the TCP/443 forwarding rule until an intentional, reviewed
   HTTPS Gateway exists. Do not assume a public LoadBalancer exists.
   Test reachability **from outside the LAN** after the Gateway is live.
3. Inspect the hostname's public **A and AAAA** records. If AAAA is
   published, its IPv6 destination must answer the same HTTP-01
   challenge; an incorrect IPv6 record can cause validation failure.
4. Confirm Gateway API CRDs (at least `GatewayClass`, `Gateway`,
   `HTTPRoute`) are installed at a version supported by the pinned
   **Cilium v1.20.4** and **cert-manager v1.21.3**. Inspect existing
   GatewayClass ownership; do not install another ingress/controller.
5. Confirm the node, Cilium, cert-manager controllers and OpenEBS
   remain healthy before a Cilium Helm change. Cilium v1.20.4 and
   cert-manager v1.21.3 are not officially compatibility-tested against
   Kubernetes v1.37.1. Gateway behavior is an additional acceptance gate.

Read-only preflight from the workstation:

```sh
kubectl get nodes
cilium status --wait
helm -n kube-system get values cilium
kubectl get crd gatewayclasses.gateway.networking.k8s.io \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io
kubectl get gatewayclass,gateways -A
kubectl -n cert-manager get deploy
```

### Platform enablement (requires separate review)

The bootstrap Cilium Helm release **still owns Cilium** and has
`cluster/bootstrap/cilium/values.yaml`:
`gatewayAPI.enabled: false`. Do **not** install a second CNI or
simultaneously add an Argo CD Cilium Application. A change to enable
Gateway API must be a separately reviewed **Helm release upgrade**
using the currently installed values, the same pinned chart, rendered
diff and tested rollback. Enabling/disrupting Cilium on the single-node
control plane can interrupt the entire cluster.

The final traffic plumbing choice is pending the public network facts.
On a single node without a Kubernetes LoadBalancer implementation,
Cilium's **Gateway API hostNetwork mode** is a candidate:
`gatewayAPI.hostNetwork.enabled: true`. That binds HTTP listeners
directly to node interfaces, requiring an externally reachable path to
node TCP/80. For a privileged 80 listener, Cilium's Envoy also needs
the chart's `envoy.securityContext.capabilities.keepCapNetBindService`
and `NET_BIND_SERVICE` capability set correctly. Inspect current
Envoy capabilities and bind conflicts before enabling it. Alternative
LB/NodePort arrangements require their own explicit service and
external forwarding design; do not assume them here.

cert-manager also requires `config.gatewayAPI.enabled: true`
in the **existing** Argo-managed Helm chart values. Install Gateway
API CRDs before cert-manager starts or restart the cert-manager
controller after enabling them. Review this chart-values change
separately, keep the existing CRDs and local issuer intact, and verify
`identity-test-tls` remains Ready.

### First certificate: isolated staging issuance

Once the prerequisites pass and the operator approves the external
port-80 exposure:

1. Create a dedicated small Gateway/ACME test namespace and a
   GitOps-managed **Cilium Gateway with only an HTTP listener on port
   80**. Initially allow solver `HTTPRoute` objects from **the same
   namespace only**, and do not create application routes.
2. Configure a manual-sync, no-prune staging `Issuer` in that same
   namespace, pointing at
   `https://acme-staging-v02.api.letsencrypt.org/directory`.
   Set `spec.acme.solvers[].http01.gatewayHTTPRoute.parentRefs`
   to the verified Gateway (namespace must match). Use
   `serviceType: ClusterIP` for the temporary challenge Service
   if compatible with the chosen network policies.
3. Issue a disposable `Certificate` for the selected **real public**
   FQDN, storing its TLS Secret exclusively in that namespace.
   cert-manager creates a temporary `cm-acme-http-solver-*` Pod,
   Service and HTTPRoute on `/.well-known/acme-challenge/<TOKEN>`.
   Inspect Challenge/Order state and Gateway route acceptance; test
   HTTP-01 retrieval from an **external** network.
4. Confirm the certificate reaches Ready and the Secret exists.
   Staging certificates are deliberately **not browser-trusted**.
   Test renewal separately. Never expose the disposable Kanidm
   application as part of this test.
5. After staging acceptance, use a distinct **production** Issuer
   with `https://acme-v02.api.letsencrypt.org/directory` and its own
   ACME account Secret, with no automatic sync or prune until
   explicitly reviewed. Plan target-namespace TLS Secret placement
   and cross-namespace route admission separately before onboarding
   real services.

**Do not** prematurely enable public Gateway API, open the router,
or sync any ACME resource just to prepare source. The real FQDN,
public TCP/80 reachability and Helm owner handoff decision remain
outstanding. Account private key Secrets stay in Kubernetes, never
plaintext Git; off-host recovery still needs design.

References:
- https://cert-manager.io/docs/configuration/acme/http01/
- https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
- https://letsencrypt.org/docs/challenge-types/
- https://letsencrypt.org/docs/ipv6-support/

## What this proves—and what it does not

Reaching Ready on both Certificates proves cert-manager's issuer chain,
webhook acceptance and Secret creation work on this cluster.
Certificate renewal still requires a separate observed test; simply
reading `renewalTime` is not renewal acceptance. Kaniop is expected
to roll its Kanidm StatefulSet on TLS Secret changes.

The CA's key and test database live on a single node with no tested
off-host restore. CA renewal does **not** automatically distribute a new
trust anchor to external clients. Do not generalize this local test CA
into a production private PKI. Choose the real DNS name, public ACME
issuer or reviewed private PKI, trust distribution and restore design
before production identities.

Gateway support is separate: when Cilium Gateway API and its CRDs are
enabled, review cert-manager's `config.gatewayAPI.enabled: true` and
restart behavior. Future Gateway listeners can reference cert-manager
TLS Secrets. The current deployment does not expose anything publicly.
