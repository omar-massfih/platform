# The A1.Flex (arm64) instance that runs single-node k3s. cloud-init just creates
# the omar user + installs base packages; the platform Ansible (ansible/site.yml)
# installs k3s and everything on top.

# Latest Ubuntu 24.04 image for the shape (arm64 for A1.Flex).
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "vm" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = var.instance_name
  shape               = var.shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = "agentic"
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gbs
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      ssh_authorized_keys = trimspace(file(pathexpand(var.ssh_public_key_path)))
    }))
  }

  # The image is looked up dynamically; don't recreate the box when a newer
  # Ubuntu image is published.
  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}
