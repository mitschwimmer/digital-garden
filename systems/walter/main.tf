data "incus_network" "private" {
  name    = "gardenbr0"
  project = "default"
  remote  = var.incus_remote
}

variable "start" {
  description = "Enable only after runtime secret delivery, OIDC discovery and model-profile acceptance."
  type        = bool
  default     = false
}

variable "quick_profile" {
  description = "Verified nonempty Walter quick-mode settings for qwen38-chat; public JSON object."
  type        = string
  default     = "{}"

  validation {
    condition     = can(keys(jsondecode(var.quick_profile)))
    error_message = "quick_profile must encode a JSON object."
  }
}

variable "thoughtful_profile" {
  description = "Verified nonempty Walter thoughtful-mode settings for qwen38-chat; public JSON object."
  type        = string
  default     = "{}"

  validation {
    condition     = can(keys(jsondecode(var.thoughtful_profile)))
    error_message = "thoughtful_profile must encode a JSON object."
  }
}

locals {
  image = jsondecode(file("${path.module}/image.lock.json"))
}

resource "incus_storage_volume" "data" {
  name    = "walter-data"
  pool    = data.incus_storage_pool.root.name
  project = "ai"
  remote  = var.incus_remote

  config = {
    "initial.uid"  = "65532"
    "initial.gid"  = "65532"
    "initial.mode" = "0700"
    "size"         = "4GiB"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Runtime secret bytes are transferred outside OpenTofu; no file/content block.
resource "incus_storage_volume" "secrets" {
  name    = "walter-secrets"
  pool    = data.incus_storage_pool.root.name
  project = "ai"
  remote  = var.incus_remote

  config = {
    "initial.uid"  = "65532"
    "initial.gid"  = "65532"
    "initial.mode" = "0700"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "incus_instance" "walter" {
  name        = "walter"
  description = "Digital Garden native OIDC chat with private inference"
  image       = "garden-ghcr:${local.image.repository}@${local.image.digest}"
  type        = "container"
  project     = "ai"
  remote      = var.incus_remote
  profiles    = []
  running     = var.start

  lifecycle {
    precondition {
      condition     = !var.start || (length(keys(jsondecode(var.quick_profile))) > 0 && length(keys(jsondecode(var.thoughtful_profile))) > 0)
      error_message = "Starting Walter requires both verified model profiles."
    }
  }

  config = {
    "boot.autostart"                             = tostring(var.start)
    "boot.autorestart"                           = tostring(var.start)
    "boot.host_shutdown_timeout"                 = "30"
    "limits.cpu"                                 = "2"
    "limits.memory"                              = "512MiB"
    "security.privileged"                        = "false"
    "oci.uid"                                    = "65532"
    "oci.gid"                                    = "65532"
    "environment.WALTER_LISTEN"                  = "0.0.0.0:8080"
    "environment.WALTER_DATA_DIR"                = "/data"
    "environment.WALTER_PUBLIC_URL"              = "https://walter.archaic.work"
    "environment.WALTER_OIDC_ISSUER"             = "https://auth.archaic.work/oauth2/openid/walter"
    "environment.WALTER_OIDC_CLIENT_ID"          = "walter"
    "environment.WALTER_OIDC_CLIENT_SECRET_FILE" = "/run/secrets/oidc-client"
    "environment.WALTER_ALLOWED_GROUPS"          = "ai-users"
    "environment.WALTER_LLAMA_ENDPOINT"          = "http://garden-llama.garden.internal:8080/v1/chat/completions"
    "environment.WALTER_MODEL"                   = "qwen38-chat"
    "environment.WALTER_QUICK_JSON"              = var.quick_profile
    "environment.WALTER_THOUGHTFUL_JSON"         = var.thoughtful_profile
    "environment.WALTER_GENERATION_TIMEOUT"      = "2h"
    "environment.WALTER_MAX_HISTORY_BYTES"       = "48000"
    "environment.WALTER_MAX_OUTPUT_TOKENS"       = "4096"
  }

  device {
    name       = "root"
    type       = "disk"
    properties = { path = "/", pool = data.incus_storage_pool.root.name, size = "1GiB" }
  }

  device {
    name       = "eth0"
    type       = "nic"
    properties = { name = "eth0", network = data.incus_network.private.name }
  }

  device {
    name = "data"
    type = "disk"
    properties = {
      path   = "/data"
      pool   = incus_storage_volume.data.pool
      source = incus_storage_volume.data.name
    }
  }

  device {
    name = "secrets"
    type = "disk"
    properties = {
      path     = "/run/secrets"
      pool     = incus_storage_volume.secrets.pool
      source   = incus_storage_volume.secrets.name
      readonly = "true"
    }
  }
}

output "walter_ipv4" {
  value = incus_instance.walter.ipv4_address
}
