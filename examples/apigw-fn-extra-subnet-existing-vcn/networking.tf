module "vcn" {
  source = "github.com/oracle-quickstart/terraform-oci-networking//modules/vcn?ref=0.2.0"

  # Oracle Cloud Infrastructure Tenancy and Compartment OCID
  compartment_ocid = var.compartment_ocid

  # Deployment Tags + Freeform Tags + Defined Tags
  vcn_tags = local.oci_tag_values

  # Virtual Cloud Network (VCN) arguments
  create_new_vcn    = false
  existent_vcn_ocid = var.existent_vcn_ocid
}

module "subnets" {
  for_each = { for map in local.subnets : map.subnet_name => map }
  source   = "github.com/oracle-quickstart/terraform-oci-networking//modules/subnet?ref=0.2.0"

  # Oracle Cloud Infrastructure Tenancy and Compartment OCID
  compartment_ocid = var.compartment_ocid
  vcn_id           = module.vcn.vcn_id

  # Deployment Tags + Freeform Tags + Defined Tags
  subnet_tags = local.oci_tag_values

  # Subnet arguments
  create_subnet              = true
  subnet_name                = each.value.subnet_name
  cidr_block                 = each.value.cidr_block
  display_name               = each.value.display_name # If null, is autogenerated
  dns_label                  = each.value.dns_label    # If null, is autogenerated
  prohibit_public_ip_on_vnic = each.value.prohibit_public_ip_on_vnic
  prohibit_internet_ingress  = each.value.prohibit_internet_ingress
  route_table_id             = each.value.route_table_id    # If null, the VCN's default route table is used
  dhcp_options_id            = each.value.dhcp_options_id   # If null, the VCN's default set of DHCP options is used
  security_list_ids          = each.value.security_list_ids # If null, the VCN's default security list is used
  ipv6cidr_block             = each.value.ipv6cidr_block    # If null, no IPv6 CIDR block is assigned
}
locals {
  subnets = [
    {
      subnet_name                = "api_gw_fn_subnet"
      cidr_block                 = lookup(local.network_cidrs, "APIGW-FN-REGIONAL-SUBNET-CIDR")
      display_name               = "API Gateway and Fn subnet (${local.deploy_id})"
      dns_label                  = "apigwfn${local.deploy_id}"
      prohibit_public_ip_on_vnic = false
      prohibit_internet_ingress  = false
      route_table_id             = module.route_tables["apigw_fn_public"].route_table_id # TODO: implement data.oci_core_route_tables to get existent
      dhcp_options_id            = module.vcn.default_dhcp_options_id
      security_list_ids          = [module.security_lists["apigw_fn_security_list"].security_list_id]
      ipv6cidr_block             = null
    }
  ]
}

module "route_tables" {
  for_each = { for map in local.route_tables : map.route_table_name => map }
  source   = "github.com/oracle-quickstart/terraform-oci-networking//modules/route_table?ref=0.2.0"

  # Oracle Cloud Infrastructure Tenancy and Compartment OCID
  compartment_ocid = local.vcn_compartment_ocid
  vcn_id           = module.vcn.vcn_id

  # Deployment Tags + Freeform Tags + Defined Tags
  route_table_tags = local.oci_tag_values

  # Route Table attributes
  create_route_table = true
  route_table_name   = each.value.route_table_name
  display_name       = each.value.display_name
  route_rules        = each.value.route_rules
}
locals {
  route_tables = [{
    route_table_name = "apigw_fn_public"
    display_name     = "API Gateway and Fn Gatw Route Table (${local.deploy_id})"
    route_rules = [
      {
        description       = "Traffic to/from internet"
        destination       = lookup(local.network_cidrs, "ALL-CIDR")
        destination_type  = "CIDR_BLOCK"
        network_entity_id = (var.existent_internet_gateway_ocid == "") ? module.gateways.internet_gateway_id : var.existent_internet_gateway_ocid
    }]
  }]
}

module "gateways" {
  source = "github.com/oracle-quickstart/terraform-oci-networking//modules/gateways?ref=0.2.0"

  # Oracle Cloud Infrastructure Tenancy and Compartment OCID
  compartment_ocid = local.vcn_compartment_ocid
  vcn_id           = module.vcn.vcn_id

  # Deployment Tags + Freeform Tags + Defined Tags
  gateways_tags = local.oci_tag_values

  # Internet Gateway
  create_internet_gateway       = (var.existent_internet_gateway_ocid == "") ? true : false
  internet_gateway_display_name = "Internet Gateway (${local.deploy_id})"
  internet_gateway_enabled      = true
}

module "security_lists" {
  for_each = { for map in local.security_lists : map.security_list_name => map }
  source   = "github.com/oracle-quickstart/terraform-oci-networking//modules/security_list?ref=0.2.0"

  # Oracle Cloud Infrastructure Tenancy and Compartment OCID
  compartment_ocid = local.vcn_compartment_ocid
  vcn_id           = module.vcn.vcn_id

  # Deployment Tags + Freeform Tags + Defined Tags
  security_list_tags = local.oci_tag_values

  # Security List attributes
  create_security_list   = true
  security_list_name     = each.value.security_list_name
  display_name           = each.value.display_name
  egress_security_rules  = each.value.egress_security_rules
  ingress_security_rules = each.value.ingress_security_rules
}
locals {
  security_lists = [
    {
      security_list_name = "apigw_fn_security_list"
      display_name       = "API Gateway and Fn Security List (${local.deploy_id})"
      egress_security_rules = [
        {
          description      = "Allow API Gateway to forward requests to Functions via service conduit"
          destination      = lookup(data.oci_core_services.all_services_network.services[0], "cidr_block")
          destination_type = "SERVICE_CIDR_BLOCK"
          protocol         = local.security_list_ports.all_protocols
          stateless        = false
          tcp_options      = { max = -1, min = -1, source_port_range = null }
          udp_options      = { max = -1, min = -1, source_port_range = null }
          icmp_options     = null
      }]
      ingress_security_rules = [
        {
          description  = "Allow API Gateway to receive requests"
          source       = lookup(local.network_cidrs, "ALL-CIDR")
          source_type  = "CIDR_BLOCK"
          protocol     = local.security_list_ports.tcp_protocol_number
          stateless    = false
          tcp_options  = { max = local.security_list_ports.https_port_number, min = local.security_list_ports.https_port_number, source_port_range = null }
          udp_options  = { max = -1, min = -1, source_port_range = null }
          icmp_options = null
      }]
    }
  ]
  security_list_ports = {
    http_port_number                        = 80
    https_port_number                       = 443
    k8s_api_endpoint_port_number            = 6443
    k8s_worker_to_control_plane_port_number = 12250
    ssh_port_number                         = 22
    tcp_protocol_number                     = "6"
    icmp_protocol_number                    = "1"
    all_protocols                           = "all"
  }
}

data "oci_core_services" "all_services_network" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

locals {
  # vcn_cidr_blocks = split(",", var.vcn_cidr_blocks)
  vcn_compartment_ocid = var.compartment_ocid
  pre_vcn_cidr_blocks  = split(",", var.vcn_cidr_blocks)
  vcn_cidr_blocks      = contains(module.vcn.cidr_blocks, local.pre_vcn_cidr_blocks[0]) ? distinct(concat([local.pre_vcn_cidr_blocks[0]], module.vcn.cidr_blocks)) : module.vcn.cidr_blocks
  network_cidrs = {
    APIGW-FN-REGIONAL-SUBNET-CIDR = cidrsubnet(local.vcn_cidr_blocks[0], 8, 30) # e.g.: "10.20.30.0/24" = 254 usable IPs (10.20.30.0 - 10.20.30.255)
    ALL-CIDR                      = "0.0.0.0/0"
  }
}
