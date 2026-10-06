variable "stage" {
  description = "Cumulative capability: 1 private, 2 ingress, 3 identity, 4 WebUI, 5 inference. Never decrease to troubleshoot."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2, 3, 4, 5], var.stage)
    error_message = "Select an integer stage from 1 through 5."
  }
}

locals {
  webui_enabled = var.stage >= 4
  llama_enabled = var.stage >= 5
}
