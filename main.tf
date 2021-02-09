variable "ibmcloud_api_key" {}
variable "region" {}
variable "ibmcloud_timeout" { default = 900 }
variable "basename" { default = "vpe-example" }
variable "resource_group_name" { default = "" }
variable "tags" { default = ["terraform"] }
variable "cidr_blocks" { default = ["10.20.10.0/24", "10.20.11.0/24", "10.20.12.0/24"] }
variable "image_name" { default = "ibm-centos-8-2-minimal-amd64-2" }
variable "profile_name" { default = "cx2-2x4" }
variable "vpc_ssh_key_name" { default = "" }
variable "use_vpe" { default = false }

provider "ibm" {
  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region
  generation       = 2
  ibmcloud_timeout = var.ibmcloud_timeout
}

terraform {
  required_version = ">= 0.14"

  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">= 1.17"
    }
  }
}

# a resource group
resource "ibm_resource_group" "group" {
  count = var.resource_group_name != "" ? 0 : 1
  name  = "${var.basename}-group"
  tags  = var.tags
}

data "ibm_resource_group" "group" {
  count = var.resource_group_name != "" ? 1 : 0
  name  = var.resource_group_name
}

# a ssh key
data "ibm_is_ssh_key" "sshkey" {
  count = var.vpc_ssh_key_name != "" ? 1 : 0
  name  = var.vpc_ssh_key_name
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

output "generated_ssh_key" {
  value     = tls_private_key.ssh
  sensitive = true
}

resource "ibm_is_ssh_key" "generated_key" {
  name           = "${var.basename}-${var.region}-key"
  public_key     = tls_private_key.ssh.public_key_openssh
  resource_group = local.resource_group_id
  tags           = var.tags
}

resource "local_file" "ssh-key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "generated_key_rsa"
  file_permission = "0600"
}

locals {
  ssh_key_ids = var.vpc_ssh_key_name != "" ? [data.ibm_is_ssh_key.sshkey[0].id, ibm_is_ssh_key.generated_key.id] : [ibm_is_ssh_key.generated_key.id]
}

locals {
  resource_group_id = var.resource_group_name != "" ? data.ibm_resource_group.group.0.id : ibm_resource_group.group.0.id
}

# a VPC
resource "ibm_is_vpc" "vpc" {
  name                      = "${var.basename}-vpc"
  resource_group            = local.resource_group_id
  address_prefix_management = "manual"
  tags                      = var.tags
}

resource "ibm_is_vpc_address_prefix" "subnet_prefix" {
  count = "3"

  name = "${var.basename}-prefix-zone-${count.index + 1}"
  zone = "${var.region}-${(count.index % 3) + 1}"
  vpc  = ibm_is_vpc.vpc.id
  cidr = var.cidr_blocks[count.index]
}

resource "ibm_is_network_acl" "network_acl" {
  name           = "${var.basename}-acl"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = local.resource_group_id

  rules {
    name        = "egress"
    action      = "allow"
    source      = "0.0.0.0/0"
    destination = "0.0.0.0/0"
    direction   = "outbound"
  }
  rules {
    name        = "ingress"
    action      = "allow"
    source      = "0.0.0.0/0"
    destination = "0.0.0.0/0"
    direction   = "inbound"
  }
}

resource "ibm_is_security_group" "group" {
  name           = "${var.basename}-group"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = local.resource_group_id
}

resource "ibm_is_security_group_rule" "ssh" {
  group     = ibm_is_security_group.group.id
  direction = "inbound"
  remote    = "0.0.0.0/0"
  tcp {
    port_min = 22
    port_max = 22
  }
}

resource "ibm_is_security_group_rule" "egress_all" {
  group     = ibm_is_security_group.group.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

# 3 subnets
resource "ibm_is_subnet" "subnet" {
  count = "3"

  name            = "${var.basename}-subnet-${count.index + 1}"
  vpc             = ibm_is_vpc.vpc.id
  zone            = "${var.region}-${count.index + 1}"
  resource_group  = local.resource_group_id
  ipv4_cidr_block = ibm_is_vpc_address_prefix.subnet_prefix[count.index].cidr
  network_acl     = ibm_is_network_acl.network_acl.id
}

# one server per subnet
data "ibm_is_image" "image" {
  name = var.image_name
}

resource "ibm_is_instance" "instance" {
  count = 3

  name           = "${var.basename}-instance-${count.index + 1}"
  vpc            = ibm_is_vpc.vpc.id
  zone           = "${var.region}-${count.index + 1}"
  profile        = var.profile_name
  image          = data.ibm_is_image.image.id
  keys           = local.ssh_key_ids
  resource_group = local.resource_group_id

  primary_network_interface {
    subnet          = ibm_is_subnet.subnet[count.index].id
    security_groups = [ibm_is_security_group.group.id]
  }

  boot_volume {
    name = "${var.basename}-instance-${count.index + 1}-boot"
  }

  tags = var.tags
}

resource "ibm_is_floating_ip" "ip" {
  count = 3

  name           = "${var.basename}-ip-${count.index + 1}"
  target         = ibm_is_instance.instance[count.index].primary_network_interface.0.id
  resource_group = local.resource_group_id
}

output "instance_names" {
  value = ibm_is_instance.instance.*.name
}

output "instance_ips" {
  value = ibm_is_floating_ip.ip.*.address
}

# one Redis database
resource "ibm_database" "redis" {
  name              = "${var.basename}-redis"
  resource_group_id = local.resource_group_id
  plan              = "standard"
  service           = "databases-for-redis"
  location          = var.region

  service_endpoints = "private"
  tags              = var.tags
}

resource "ibm_resource_key" "redis_key" {
  name                 = "${var.basename}-redis-key"
  resource_instance_id = ibm_database.redis.id
  role                 = "Viewer"
}

locals {
  endpoints = [
    {
      name     = "redis",
      crn      = ibm_database.redis.id,
      hostname = ibm_resource_key.redis_key.credentials["connection.rediss.hosts.0.hostname"]
    },
    {
      name     = "cos",
      crn      = "crn:v1:bluemix:public:cloud-object-storage:global:::endpoint:s3.direct.${var.region}.cloud-object-storage.appdomain.cloud",
      hostname = "s3.direct.${var.region}.cloud-object-storage.appdomain.cloud"
    },
    {
      name     = "kms",
      crn      = "crn:v1:bluemix:public:kms:us-south:::endpoint:private.${var.region}.kms.cloud.ibm.com",
      hostname = "private.${var.region}.kms.cloud.ibm.com"
    }
  ]
}

output "endpoints" {
  value = local.endpoints
}

# and for each service, one gateway with one IP per subnet
resource "ibm_is_virtual_endpoint_gateway" "vpe" {
  for_each = { for target in local.endpoints : target.name => target if tobool(var.use_vpe) }

  name           = "${var.basename}-${each.key}-vpe"
  resource_group = local.resource_group_id
  vpc            = ibm_is_vpc.vpc.id

  target {
    crn           = each.value.crn
    resource_type = "provider_cloud_service"
  }

  # one Reserved IP for per zone in the VPC
  dynamic "ips" {
    for_each = { for subnet in ibm_is_subnet.subnet : subnet.id => subnet }
    content {
      subnet = ips.key
      name   = "${ips.value.name}-${each.key}-ip"
    }
  }

  tags = var.tags
}
