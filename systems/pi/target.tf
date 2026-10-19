locals {
  target = jsondecode(file("${path.module}/target.json"))
}
output "deployment" {
  value = merge(local.target, { remote = var.incus_remote })
}
