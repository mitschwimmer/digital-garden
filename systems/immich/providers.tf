terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "= 1.2.0"
    }
  }
}

variable "incus_remote" {
  description = "Authenticated Incus client remote alias."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.-]*$", var.incus_remote))
    error_message = "Supply an Incus client remote alias without a colon."
  }
}

variable "storage_pool" {
  description = "Existing fast storage pool for the root, database and machine key (local on measerve)."
  type        = string
  default     = "local"
}

variable "media_storage_pool" {
  description = "Existing bulk storage pool for the Immich media library (data on measerve)."
  type        = string
  default     = "data"
}

provider "incus" {
  default_remote = var.incus_remote

  remote {
    name     = "garden-ghcr"
    address  = "https://ghcr.io"
    protocol = "oci"
    public   = true
  }

  remote {
    name = var.incus_remote
  }
}

# Existing IncusOS pools are host prerequisites, not managed lifecycle here.
data "incus_storage_pool" "root" {
  name   = var.storage_pool
  remote = var.incus_remote
}

data "incus_storage_pool" "media" {
  name   = var.media_storage_pool
  remote = var.incus_remote
}
