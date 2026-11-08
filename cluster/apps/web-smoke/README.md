# Public HTTP smoke test

A disposable, unauthenticated static page at **http://test.archaic.work/**.
This proves the public DNS/NAT -> Talos -> Cilium hostNetwork Gateway ->
HTTPRoute -> ClusterIP Service -> unprivileged NGINX path. It neither
deploys Let's Encrypt nor exposes the existing Kanidm test.

The operator reports router NAT forwarding external TCP 80 and 443 to the
Talos VM at `192.168.1.49`; previous DNS used `*.archaic.work` with an
external Caddy server. This does **not** prove today's public DNS or
external reachability. Only port 80 is consumed by this test. No TLS
listener is configured yet; browsers may try HTTPS automatically.

## 1. Enable Cilium Gateway API (manual Helm owner)

Follow [Cilium's bootstrap instructions](../../bootstrap/cilium/README.md)
under **Public HTTP Gateway smoke test**. It includes pinning Gateway API
CRDs to v1.6.3, reviewing the installed Helm values, and upgrading the
**existing** Cilium v1.20.4 Helm release with hostNetwork and port-80
binding capabilities. Do not install a second Cilium release.

Afterward check:

```sh
cilium status --wait
kubectl get gatewayclass cilium
kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io
```

## 2. Deploy the website

The root Application adds the `web-smoke` namespace (restricted PSA)
and registers the `web-smoke` child, which is **manual-sync only**.
From a workstation shell with `nix develop` and the repository
kubeconfig:

```sh
export KUBECONFIG="$PWD/.operations/talos/kubeconfig"
kubectl -n argocd get applications garden-root web-smoke
kubectl get namespace web-smoke
argocd --core app sync web-smoke
kubectl -n web-smoke rollout status deployment/web-smoke --timeout=180s
kubectl -n web-smoke get deployment,pods,svc,gateway,httproute
kubectl -n web-smoke describe gateway web-smoke
kubectl -n web-smoke describe httproute web-smoke
```

Gateway `Accepted=True` and `Programmed=True`, HTTPRoute
`Accepted=True` and `ResolvedRefs=True`, and a Ready web-smoke
Deployment are the desired state.

## 3. Manual browser test

First test from the workstation on the LAN (routing without the public
DNS dependency):

```sh
curl -v -H 'Host: test.archaic.work' http://192.168.1.49/
```

Then check that `test.archaic.work` resolves publicly to the
router's current reachable WAN IP. If an AAAA record exists, IPv6 must
also reach the Gateway or the incorrect AAAA must be removed.

From a phone on **mobile data**, with Wi-Fi disabled, open:

**http://test.archaic.work/**

Expected text: **Digital Garden is reachable**.

Use the explicit `http://` URL: the Gateway has no TLS listener yet.
An HTTPS-first browser or HSTS inherited from a prior Caddy site may
try port 443 instead; use an HTTP-specific curl request to distinguish
that issue from routing failures.

If LAN works but mobile data fails, focus on wildcard DNS public A/AAAA
records, router WAN-IP/CGNAT, and router/firewall forwarding. If the
Gateway/Route is not accepted, inspect its status conditions and Cilium
operator/Envoy logs. Don't change Kanidm or OpenEBS to fix an HTTP
routing problem.

## 4. After the browser test

Reuse this port-80 Gateway for a **staging** Let's Encrypt HTTP-01
challenge on `test.archaic.work`; enable cert-manager's Gateway API
solver, keep the solver and Gateway in the same namespace, and request
a separate disposable Certificate/Secret. After challenge issuance
passes, add HTTPS deliberately.

This website stores no data, but its Application has no automated
prune. Uninstall or cleanup needs an explicit operator decision.
