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
