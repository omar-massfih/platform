output "public_ip" {
  description = "Public IP of the instance (point the DNS A record here)."
  value       = oci_core_instance.vm.public_ip
}

output "private_ip" {
  value = oci_core_instance.vm.private_ip
}

output "instance_ocid" {
  value = oci_core_instance.vm.id
}

output "next_steps" {
  value = "Point assistant.<domain> at public_ip, then run: cd ../ansible && ansible-playbook site.yml"
}
