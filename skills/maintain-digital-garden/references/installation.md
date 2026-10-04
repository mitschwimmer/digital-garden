# Installation inputs and inventory

The operator supplies one public JSON object. `scripts/prepare.py:inputs` is the executable
validation contract; the keys below describe it. Private values never belong in this object.

| Key | Required public value |
|---|---|
| `project`, `owner`, `pool`, `private_network` | Recorded Incus scope/ownership/ZFS pool and private bridge identifiers |
| `private_cidr`, `addresses` | Reviewed private IPv4 subnet; exactly caddy/authelia/grafana/prometheus/llama/openwebui/pi usable distinct static addresses |
| `domain`, `hosts` | Cookie domain and four distinct auth/grafana/ai/pi hostnames beneath it |
| `lan` | Exactly `nictype` (bridged or macvlan), real `parent`, reviewed `hwaddr`; router DHCP reservation/routing supplies gateway LAN access |
| `gpu_pci` | Recorded full physical PCI address for the RX 9060 XT; never a guessed address |
| `incus_metrics` | Exactly `target` (hostname/IP:port) and matching TLS `server_name` |
| `images` | Exactly seven app records, each `source`, `platform=linux/amd64`, resolved cached full `fingerprint` |
| `pi` | Explicit `cpu`, `memory` and `root_size` capacity |
| optional `smtp` | Exactly public `address`, `username`, `sender`, `startup_check_address`; password supplied privately |

OCI source digests are listed in `scripts/prepare.py:PINS`; cache those exact sources before
preparation. Record linux/amd64, cached Incus image metadata/fingerprint and verification date.
The Debian 13 cloud VM is resolved once from `images:debian/13/cloud`, with its immutable cached
fingerprint recorded; the rolling family name alone is not a deployment pin. No runtime pulls
are needed for these seven images. Pi's first-boot installer still requires normal internet access
for guest packages, Node 24.19.0 and its checksum-pinned service release. Node's archive checksum
and service release/checksum are retained in the installer; do not replace them with latest.

| Workload | Private service ports | Process IDs | Retained volumes |
|---|---|---|---|
| Caddy | public LAN 80/443; private 9180 metrics | 0:0 in unprivileged OCI | caddy-data, caddy-config |
| Authelia | 9091 auth, 9959 metrics | 1000:1000 | authelia-data (SQLite/passkeys/notifier) |
| Grafana | 3000 app/metrics | 472:0 | grafana-data |
| Prometheus | 9090 | 65534:65534 | prometheus-data (TSDB/WAL) |
| llama.cpp ROCm | 8080 private model/inference/metrics API | 1000:1000 | llama-cache 0750 |
| Open WebUI | 8080 app | 0:0 in unprivileged OCI | webui-data |
| Pi Debian cloud VM | 3001 app HTTP/WebSocket | service 1000:1000 | pi-agent, pi-workspace |

Other retained volumes use explicit 0700 process ownership and shifted file delivery. Public
configurations are read-only with explicit readable IDs; generated values are 0400. Grafana
settings, datasource, provider and flat dashboard each mount at separate non-overlapping paths.
The existing dashboard UID is `homelab-incus`, datasource UID `prometheus`.

Operator prerequisites: project, ZFS pool, private network/NAT/DNS, LAN attachment/DHCP reservation,
verified Incus TLS and cached images; private-users (UID 1000), incus-metrics (UID 65534), optional
private-smtp (UID 1000); Tend's private TLS/Git arguments and retained controller volumes. Tend
creates every application volume/instance/configuration after these prerequisites. Use Tend's
reviewed remote IncusOS bootstrap and private-volume tools. Do not execute CI cleanup on IncusOS.

1. Record actual IncusOS/kernel/network/storage/GPU state and public DNS/router 80/443 reachability.
2. Cache and record the exact images, then prepare/review the public state with the real site inputs.
3. Provision **new** private user identities and separate metrics-only TLS; no old credential/data
   restore. Mark volumes with the same `owner` and private kind. Mount users/metrics/SMTP read-only.
4. Import/bootstrap the reviewed Tend OCI build with read-only private credentials and a writable
   UID-1000 state volume. Its watch command selects this repository main and the same project/owner.
5. Start Tend; bounded service/VM agent/cloud-init/HTTP checks establish readiness outside Tend.
6. Verify password login, enroll new passkeys, test Grafana admins and protected Pi ai-users.
   Open WebUI's **first** approved account must have both admins and ai-users. v0.11.4 promotes
   its first user and independently accepts admins; the Authelia ai-users policy is required.
7. Verify actual dashboard queries, private metrics TLS, idle autoload=false scrapes, model load,
   context/parallel/MTP and Open WebUI/Pi streaming. Reboot the host and prove retained new data.

Pi model metadata and Prometheus labels derive from the literal current presets: mimo 131072,
qwen36 65536 context tokens per slot (parallel 1), thinking enabled, Qwen draft-mtp max 2. The MiMo
comment contradicts literal no-mmproj=false; preserve that reviewed flag and record unexpected
projector downloads as a commissioning blocker. HF filenames do not pin content; record downloaded
file hashes/revisions and actual VRAM/disk requirements. Health is router readiness, not inference.

`--validate` checks seven workloads, duplicate addresses, source files, model IDs and context
agreement. Tend owns XSD, duplicate ingress hosts, references, ownership and mount conflicts.
Run both before activation. Preparation must write into an empty output directory; re-prepare
rather than manually patching application config when inputs change.

Optional `ci` contains exactly `controlled_llama`, `local_ca`, `nameserver`; it is only for the
reviewed disposable composition. It replaces ROCm with the pinned Open WebUI image's Python runtime,
removes GPU/KFD and runs the controlled protocol asset; it also mounts a verified public local CA.
An initial public trust file lets all seven instances be declared; after Caddy creates its local
CA, the test commits that actual **public** CA and activates the consumers before any login.
The test DNS is an operator network prerequisite. Provenance records every substitution.
A CPU runner does not commission production GPU, ZFS, LAN/router or public ACME.
