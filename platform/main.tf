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
