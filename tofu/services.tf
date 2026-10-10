variable "enable_edge_lan" {
  description = "Attach the inspected LAN NIC to edge. NixOS activation configures ingress separately."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_webui" {
  description = "Create the Open WebUI guest without changing inference selection or retained volumes."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_inference" {
  description = "Create the private GPU inference guest independently of WebUI and edge LAN attachment."
  type        = bool
  default     = false
  nullable    = false
}

# Reject old local inputs rather than silently disabling their existing guests.
variable "stage" {
  description = "Removed selector. Migrate local inputs to explicit enable_edge_lan, enable_webui and enable_inference settings."
  type        = number
  default     = null

  validation {
    condition     = var.stage == null
    error_message = "The stage selector has been removed. Migrate local inputs using the platform reference before planning; preserve existing resource selection."
  }
}
