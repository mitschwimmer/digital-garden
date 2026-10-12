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
  description = "Existing storage pool for the system root and persistent volumes."
  type        = string
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
