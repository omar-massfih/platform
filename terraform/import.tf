# Adopt the EXISTING live infrastructure instead of recreating it. Run
# `terraform plan` with these in place: Terraform imports the current resources
# into state. Review the plan for drift, then remove this file once imported
# (or keep it — import blocks are no-ops once the resource is in state).
#
# If you're provisioning a NEW environment from scratch, delete this file.

import {
  to = oci_core_vcn.main
  id = "ocid1.vcn.oc1.eu-stockholm-1.amaaaaaadm4yxuaacs7wd6oyo3ojyqdi7vjyc5pd6vpplqy3fnxh65qvoyuq"
}

import {
  to = oci_core_internet_gateway.igw
  id = "ocid1.internetgateway.oc1.eu-stockholm-1.aaaaaaaa3plritxgiufwln4jkweirkwqdagucctcnlvplgwicadolfijuvxa"
}

import {
  to = oci_core_security_list.sl
  id = "ocid1.securitylist.oc1.eu-stockholm-1.aaaaaaaalheqxfz4fnpc4fw2snpx3musmumpeg4b7tfgisaio3qcdjgg6moa"
}

import {
  to = oci_core_subnet.public
  id = "ocid1.subnet.oc1.eu-stockholm-1.aaaaaaaac56ualuz2jrvrhlammdl52iflphudhvvjujf3xeiqt2aonx4ch4q"
}

import {
  to = oci_core_instance.vm
  id = "ocid1.instance.oc1.eu-stockholm-1.anqxeljrdm4yxuacmits4slr7vyolppwvv5c566kpad3kh2zrctpeyctu6mq"
}

# Note: the live VCN's route table is the default one created with the VCN. After
# import you may want to reconcile oci_core_route_table.public with it (or import
# the default route table id) — check `terraform plan` output.
