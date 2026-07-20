variable "region" {
  type    = string
  default = "eu-stockholm-1"
}

# The instance lives directly in the tenancy (root) compartment today.
variable "compartment_ocid" {
  type        = string
  description = "Compartment for all resources (tenancy root in the current setup)."
}

variable "availability_domain" {
  type    = string
  default = "beDq:EU-STOCKHOLM-1-AD-1"
}

variable "instance_name" {
  type    = string
  default = "agentic-assistant"
}

# VM.Standard.A1.Flex (Ampere/arm64) — matches the k3s node arch.
variable "shape" {
  type    = string
  default = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  type    = number
  default = 2
}

variable "memory_gbs" {
  type    = number
  default = 12
}

variable "boot_volume_gbs" {
  type    = number
  default = 47
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/24"
}

# Public SSH is intentionally closed — you reach the box over the OpenVPN tunnel
# (UDP 1194). Set true only if you want to also open TCP 22 to the internet.
variable "open_public_ssh" {
  type    = bool
  default = false
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}
