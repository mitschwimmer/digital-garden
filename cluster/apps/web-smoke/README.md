# Public HTTP and HTTPS smoke tests

Two disposable, unauthenticated websites on **separate Pods and Services**:

| Browser URL | Gateway listener | Backend | Verification |
| --- | --- | --- | --- |
| http://test.archaic.work/ | HTTP on 80 | `web-smoke` | DNS, router, Cilium, routing |
| https://secure-test.archaic.work/ | HTTPS on 443 | `web-smoke-secure` | Same path plus production Let's Encrypt TLS |

Both Pods serve simple static pages on internal port 8080. Cilium Envoy
terminates HTTPS at the Gateway, and forwards plaintext HTTP **inside
Kubernetes** to the second isolated Pod. There is no external
authentication, OIDC, session, database or persistent volume.

The router forwards TCP/80 and TCP/443 to the Talos node
`192.168.1.49`. The operator previously used wildcard
`*.archaic.work` with an external Caddy server. **Verify** the current
A/AAAA records and that no other listener on the node owns 80/443.
There is no Caddy sidecar or additional ingress controller.

All Kubernetes manifests and the Cilium Helm chart are installed or
reconciled through **Argo CD**. There is no manual `kubectl apply` or
`helm upgrade` in this workflow. Root registers children without
auto-sync; explicitly synchronize each in dependency order.

## 1. Gateway API CRDs (Argo CD)

The `gateway-api-crds` Argo CD Application fetches the **upstream**
`kubernetes-sigs/gateway-api` Git repository with tag `v1.6.3`
and Kustomize path `config/crd/experimental`. Cilium v1.20.4 requires
the experimental `TLSRoute` resource in addition to stable
`GatewayClass`, `Gateway`, `HTTPRoute`, `ReferenceGrant` etc.
There is one CRD owner; never install a second copy with kubectl.

```sh
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"
kubectl -n argocd get applications gateway-api-crds cilium-platform web-smoke
argocd --core app sync gateway-api-crds
kubectl get crd gatewayclasses.gateway.networking.k8s.io \
  gateways.gateway.networking.k8s.io \
  httproutes.gateway.networking.k8s.io \
  tlsroutes.gateway.networking.k8s.io
```

Do not prune the CRD Application. Existing Gateway API CRDs, if any,
must be inspected before the first sync; the pinned upstream resources
are intended as their sole declarative owner.

## 2. Cilium handoff (Argo CD)

The original Cilium v1.20.4 was installed by bootstrap Helm.
A Helm release is *not* a running reconciler, but its release metadata
and Argo's tracking record can coexist confusingly unless an explicit
handoff is made. The `cilium-platform` Argo CD Application renders
the **same pinned** `quay.io/cilium/charts/cilium:1.20.4` chart
using the same `cluster/bootstrap/cilium/values.yaml` as the bootstrap,
including the known Talos settings. Git becomes the only change owner
after successful adoption. **Do not run another Helm upgrade or
uninstall Cilium.** Retain the historic Helm release record for audit
until separately retired without deleting live workloads.

Before first sync, inspect the current chart/release, live values and
Argo diff carefully to catch drift (notably Cilium API endpoint,
capabilities, PodCIDR/IPAM, cgroup settings, operator replicas):

```sh
kubectl get nodes
cilium status --wait
helm -n kube-system list
helm -n kube-system get values cilium
argocd --core app diff cilium-platform
```

Only when the proposed changes amount to the expected Gateway API
feature enablement, Envoy `NET_BIND_SERVICE` and controlled Cilium
reconciliation (not network identity or storage changes), sync:

```sh
argocd --core app sync cilium-platform
cilium status --wait
kubectl get gatewayclass cilium
kubectl -n kube-system get ds cilium cilium-envoy
kubectl -n kube-system get deployment cilium-operator
```

The changed `rollOutCiliumPods` value is intended to restart the agent
as necessary for Gateway enablement. This is a **single-node CNI
control-plane change**; don't synchronize if the Helm release still
has unknown live overrides. Inspect Cilium pod events and Argo
differences on failure. No second CNI is installed.

## 3. Enable cert-manager Gateway solver via Argo

The existing `cert-manager` Application now sets
`config.gatewayAPI.enabled: true`. It is already a distinct
Argo-owned OCI Helm chart; wait until Gateway API CRDs are present,
then sync it once:

```sh
argocd --core app sync cert-manager
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
```

The chart updates the controller's configuration so it discovers
Gateway API on startup. Keep the existing `identity-test-tls`
certificates intact.

## 4. HTTP website in a browser

`web-smoke` owns the namespace's HTTP Gateway with a
`*.archaic.work` listener on **80**, the HTTPRoute for
`test.archaic.work` and **both** web-smoke Pod/Service pairs. Its
listener accepts other hostnames under `*.archaic.work` only when
an HTTPRoute explicitly attaches; that permits temporary ACME
HTTP-01 solver routes for `secure-test.archaic.work`.

```sh
argocd --core app sync web-smoke
kubectl -n web-smoke rollout status deployment/web-smoke
kubectl -n web-smoke rollout status deployment/web-smoke-secure
kubectl -n web-smoke get pods,svc,gateway,httproute
kubectl -n web-smoke describe gateway web-smoke
curl -v -H 'Host: test.archaic.work' http://192.168.1.49/
```

Then use a phone on **mobile data** (not home Wi-Fi) to open
**http://test.archaic.work/**. Expected heading:
`Digital Garden is reachable`.

## 5. ACME HTTP-01 staging and production

Two independently manually synchronized Argo CD applications provide
the `Issuer` and `Certificate` resources; both are scoped to
`web-smoke`. Only the production certificate is used by the HTTPS
Gateway, but staging tests public challenge reachability first.

```sh
argocd --core app sync web-smoke-acme-staging
kubectl -n web-smoke get issuer,certificate,order,challenge
kubectl -n web-smoke wait --for=condition=Ready \
  certificate/web-smoke-staging --timeout=300s
```

The staging Secret `web-smoke-staging-tls` is **not publicly trusted**.
Inspect the temporary `cm-acme-http-solver-*` HTTPRoute/Pod/Service
if issuance stalls; check WAN reachability and DNS A/AAAA first.
The existing static root path route is less specific than cert-manager's
exact `/.well-known/acme-challenge/<token>` solver route.

After staging is Ready, sync the production cert and wait:

```sh
argocd --core app sync web-smoke-acme-production
kubectl -n web-smoke wait --for=condition=Ready \
  certificate/web-smoke-production --timeout=300s
kubectl -n web-smoke get certificate web-smoke-production
kubectl -n web-smoke get secret web-smoke-production-tls
```

The certificate is issued by Let's Encrypt's **production** endpoint
for `secure-test.archaic.work`, without a DNS API token. HTTP-01
requires port 80 to remain reachable for **renewals**. No wildcard
certificate can be obtained using HTTP-01, even though a wildcard DNS
record resolves the two test names.

## 6. HTTPS website in a browser

The separate `web-smoke-https` Application creates an HTTPS Gateway
on **443** with TLS termination referencing the now-Ready
`web-smoke-production-tls` Secret, and an HTTPRoute to the second
Pod's Service. It does not modify or replace the HTTP Gateway.

```sh
argocd --core app sync web-smoke-https
kubectl -n web-smoke get gateway,httproute,pods,svc
kubectl -n web-smoke describe gateway web-smoke-https
curl -v --resolve secure-test.archaic.work:443:192.168.1.49 \
  https://secure-test.archaic.work/
```

Finally browse to **https://secure-test.archaic.work/** from mobile
data or another external network. Expected heading:
`Digital Garden HTTPS is verified`, with no browser trust warning.
Verify the certificate subject and issuer in the browser.

If HTTP works but HTTPS does not, inspect Gateway `Accepted`,
`Programmed` and `ResolvedRefs` status and the production TLS
Secret before touching the private test Kanidm. No additional
`kubectl apply`, `helm upgrade`, public Kanidm route or auth
configuration is needed.

## Known limitations

- cert-manager v1.21.3 and Cilium v1.20.4 are ahead of their official
  Kubernetes v1.37.1 compatibility test ranges.
- Public A/AAAA records and port forwarding remain an independent
  external validation, despite the operator's reported router rules.
- The previous reboot cause, off-host backups, and Kanidm database
  persistence remain unverified. Both public pages are stateless.
- Applications have **manual sync and no prune**. There is no automatic
  resource cleanup.
