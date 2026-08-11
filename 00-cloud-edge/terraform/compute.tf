data "oci_identity_availability_domains" "ads" {
  compartment_id = var.oci_tenancy_ocid
}

locals {
  availability_domain = (
    trimspace(var.instance_availability_domain) != ""
    ? trimspace(var.instance_availability_domain)
    : data.oci_identity_availability_domains.ads.availability_domains[var.instance_availability_domain_index].name
  )
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.oci_compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = local.instance.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "edge" {
  compartment_id      = var.oci_compartment_ocid
  availability_domain = local.availability_domain
  display_name        = local.instance.hostname
  shape               = local.instance.shape

  shape_config {
    ocpus         = local.instance.ocpus
    memory_in_gbs = local.instance.memory_gb
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu.images[0].id
    boot_volume_size_in_gbs = local.instance.boot_volume_gb
  }

  create_vnic_details {
    subnet_id                 = oci_core_subnet.public.id
    display_name              = "${local.instance.hostname}-vnic"
    assign_private_dns_record = true

    assign_public_ip = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key

    user_data = base64encode(<<-EOF
      #!/bin/bash
      set -eu
      mkdir -p /root/.ssh
      cp /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
      install -d -m 0755 /etc/ssh/sshd_config.d
      echo 'PermitRootLogin prohibit-password' > /etc/ssh/sshd_config.d/00-root-login.conf
      systemctl restart sshd
    EOF
    )
  }

  lifecycle {
    ignore_changes = [
      source_details[0].source_id,
      availability_domain,
      metadata,
    ]
    replace_triggered_by = [terraform_data.vcn_cidr_marker]
  }
}
