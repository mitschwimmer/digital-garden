resource "incus_network" "private" {
  name        = "gardenbr0"
  description = "Digital Garden backend bridge"
  type        = "bridge"
  project     = "default"
  remote      = var.incus_remote

  config = {
    "ipv4.dhcp"     = "true"
    "ipv4.nat"      = "true"
    "ipv4.firewall" = "true"
    "ipv6.address"  = "none"
    "dns.domain"    = "garden.internal"
    "dns.mode"      = "managed"
  }

  # Omit the address so Incus allocates a subnet. The provider tracks it as computed.
}

# Read server-generated values only after the managed bridge exists.
data "incus_network" "private" {
  name       = incus_network.private.name
  project    = "default"
  remote     = var.incus_remote
  depends_on = [incus_network.private]
}

output "private_bridge_ipv4" {
  value = data.incus_network.private.config["ipv4.address"]
}

locals {
  agent_network = jsondecode(file("${path.module}/../agent-network.json"))
}

# Untrusted agents never join gardenbr0. No host address means no bridge DNS,
# DHCP or host gateway; only the vault and sandbox have static guest addresses.
resource "incus_network" "agent" {
  name        = local.agent_network.bridge
  description = "Unrouted Pi to Agent Vault link"
  type        = "bridge"
  project     = "default"
  remote      = var.incus_remote
  config = {
    "ipv4.address" = "none"
    "ipv6.address" = "none"
    "dns.mode"     = "none"
  }
}

resource "incus_project" "agents" {
  for_each = {
    agent-vault   = "Standalone credential broker"
    agent-sandbox = "Untrusted Pi development sandbox"
  }
  name        = each.key
  description = "Digital Garden ${each.value}"
  remote      = var.incus_remote
  config = {
    "features.images"          = "true"
    "features.profiles"        = "true"
    "features.storage.volumes" = "true"
    "features.storage.buckets" = "true"
    "features.networks"        = "false"
    "features.networks.zones"  = "false"
  }
}
# Edge and the shared bridge use default; identity and applications have their own projects.
resource "incus_project" "ai" {
  name        = "ai"
  description = "Digital Garden user-facing AI applications"
  remote      = var.incus_remote

  config = {
    "features.images"          = "true"
    "features.profiles"        = "true"
    "features.storage.volumes" = "true"
    "features.storage.buckets" = "true"
    "features.networks"        = "false"
    "features.networks.zones"  = "false"
  }
}

resource "incus_project" "inference" {
  name        = "inference"
  description = "Digital Garden GPU inference and model storage"
  remote      = var.incus_remote

  config = {
    "features.images"          = "true"
    "features.profiles"        = "true"
    "features.storage.volumes" = "true"
    "features.storage.buckets" = "true"
    "features.networks"        = "false"
    "features.networks.zones"  = "false"
  }
}

resource "incus_project" "identity" {
  name        = "identity"
  description = "Digital Garden identity provider"
  remote      = var.incus_remote

  config = {
    "features.images"          = "true"
    "features.profiles"        = "true"
    "features.storage.volumes" = "true"
    "features.storage.buckets" = "true"
    "features.networks"        = "false"
    "features.networks.zones"  = "false"
  }
}

resource "incus_project" "photos" {
  name        = "photos"
  description = "Digital Garden photo and video library"
  remote      = var.incus_remote

  config = {
    "features.images"          = "true"
    "features.profiles"        = "true"
    "features.storage.volumes" = "true"
    "features.storage.buckets" = "true"
    "features.networks"        = "false"
    "features.networks.zones"  = "false"
  }
}

resource "incus_project" "webdav" {
  name        = "webdav"
  description = "Digital Garden LAN-only WebDAV"
  remote      = var.incus_remote

  config = {
    "features.images"          = "true"
    "features.profiles"        = "true"
    "features.storage.volumes" = "true"
    "features.storage.buckets" = "true"
    "features.networks"        = "false"
    "features.networks.zones"  = "false"
  }
}
