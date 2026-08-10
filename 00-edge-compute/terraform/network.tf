locals {
  edge     = jsondecode(file("${path.module}/../edge.json"))
  instance = local.edge.instance
}

resource "terraform_data" "vcn_cidr_marker" {
  input = var.vcn_cidr
}

resource "oci_core_vcn" "edge" {
  compartment_id = var.oci_compartment_ocid
  display_name   = "${local.instance.hostname}-vcn"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "edgevcn"

  lifecycle {
    replace_triggered_by = [terraform_data.vcn_cidr_marker]
  }
}

resource "oci_core_internet_gateway" "edge" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.edge.id
  display_name   = "${local.instance.hostname}-igw"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.edge.id
  display_name   = "${local.instance.hostname}-public-rt"

  route_rules {
    network_entity_id = oci_core_internet_gateway.edge.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_security_list" "edge" {
  compartment_id = var.oci_compartment_ocid
  vcn_id         = oci_core_vcn.edge.id
  display_name   = "${local.instance.hostname}-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  ingress_security_rules {
    protocol    = "6" # TCP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "HTTPS — HAProxy"

    tcp_options {
      min = 443
      max = 443
    }
  }
  ingress_security_rules {
    protocol    = "17" # UDP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "Tailscale direct connections"

    udp_options {
      min = 41641
      max = 41641
    }
  }

  # ingress_security_rules {
  #   protocol    = "6"
  #   source      = var.ssh_ingress_cidr
  #   stateless   = false
  #   description = "SSH — narrow once the tailnet is up"

  #   tcp_options {
  #     min = 22
  #     max = 22
  #   }
  # }

  ingress_security_rules {
    protocol    = "1" # ICMP
    source      = "0.0.0.0/0"
    stateless   = false
    description = "ICMP fragmentation-needed (PMTUD)"

    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.oci_compartment_ocid
  vcn_id                     = oci_core_vcn.edge.id
  display_name               = "${local.instance.hostname}-public-subnet"
  cidr_block                 = var.public_subnet_cidr
  dns_label                  = "edgepub"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.edge.id]
  prohibit_public_ip_on_vnic = false

  lifecycle {
    replace_triggered_by = [oci_core_vcn.edge]
  }
}
