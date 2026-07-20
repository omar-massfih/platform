terraform {
  required_version = ">= 1.5.0" # import blocks
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

# Auth comes from ~/.oci/config (the same profile the `oci` CLI uses).
provider "oci" {
  region = var.region
}
