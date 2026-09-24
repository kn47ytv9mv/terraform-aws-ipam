resource "aws_vpc_ipam" "resource" {
  description = var.description
  tier        = var.tier
  cascade     = var.cascade

  dynamic "operating_regions" {
    for_each = local.operating_regions

    content {
      region_name = operating_regions.value
    }
  }

  tags = merge(var.tags, { name = "ipam" })
}

resource "aws_vpc_ipam_pool" "root" {
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.resource.private_default_scope_id

  tags = merge(var.tags, { name = "root" })
}

resource "aws_vpc_ipam_pool_cidr" "root" {
  ipam_pool_id = aws_vpc_ipam_pool.root.id
  cidr         = var.cidr
}

resource "aws_vpc_ipam_pool" "root_ipv6" {
  count = var.ipv6_cidr != null ? 1 : 0

  address_family = "ipv6"
  ipam_scope_id  = aws_vpc_ipam.resource.private_default_scope_id

  tags = merge(var.tags, { name = "root-ipv6" })
}

resource "aws_vpc_ipam_pool_cidr" "root_ipv6" {
  count = var.ipv6_cidr != null ? 1 : 0

  ipam_pool_id = aws_vpc_ipam_pool.root_ipv6[0].id
  cidr         = var.ipv6_cidr
}

resource "aws_vpc_ipam_pool" "intermediate" {
  for_each = var.intermediate_pools

  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.resource.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.root.id

  tags = merge(var.tags, { name = "${each.key}-intermediate" })
}

resource "aws_vpc_ipam_pool_cidr" "intermediate" {
  for_each = var.intermediate_pools

  ipam_pool_id   = aws_vpc_ipam_pool.intermediate[each.key].id
  netmask_length = each.value.ipv4_netmask_length
}

resource "aws_vpc_ipam_pool" "intermediate_ipv6" {
  for_each = { for k, v in var.intermediate_pools : k => v if v.ipv6_netmask_length != null }

  address_family      = "ipv6"
  ipam_scope_id       = aws_vpc_ipam.resource.private_default_scope_id
  source_ipam_pool_id = aws_vpc_ipam_pool.root_ipv6[0].id

  tags = merge(var.tags, { name = "${each.key}-intermediate-ipv6" })
}

resource "aws_vpc_ipam_pool_cidr" "intermediate_ipv6" {
  for_each = aws_vpc_ipam_pool.intermediate_ipv6

  ipam_pool_id   = each.value.id
  netmask_length = var.intermediate_pools[each.key].ipv6_netmask_length
}

resource "aws_vpc_ipam_pool" "regional" {
  for_each = var.regional_pools

  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.resource.private_default_scope_id
  locale         = each.key
  source_ipam_pool_id = each.value.intermediate_pool != null ? (
    aws_vpc_ipam_pool.intermediate[each.value.intermediate_pool].id
  ) : aws_vpc_ipam_pool.root.id

  tags = merge(var.tags, { name = each.key })
}

resource "aws_vpc_ipam_pool_cidr" "regional" {
  for_each = var.regional_pools

  ipam_pool_id   = aws_vpc_ipam_pool.regional[each.key].id
  netmask_length = each.value.ipv4_netmask_length
}

resource "aws_vpc_ipam_pool" "regional_ipv6" {
  for_each = { for k, v in var.regional_pools : k => v if v.ipv6_netmask_length != null }

  address_family = "ipv6"
  ipam_scope_id  = aws_vpc_ipam.resource.private_default_scope_id
  locale         = each.key
  source_ipam_pool_id = each.value.intermediate_pool != null ? (
    aws_vpc_ipam_pool.intermediate_ipv6[each.value.intermediate_pool].id
  ) : aws_vpc_ipam_pool.root_ipv6[0].id

  tags = merge(var.tags, { name = "${each.key}-ipv6" })
}

resource "aws_vpc_ipam_pool_cidr" "regional_ipv6" {
  for_each = aws_vpc_ipam_pool.regional_ipv6

  ipam_pool_id   = each.value.id
  netmask_length = var.regional_pools[each.key].ipv6_netmask_length
}

locals {
  operating_regions = distinct(concat([data.aws_region.current.region], keys(var.regional_pools)))
}

data "aws_region" "current" {}

output "ipam_id" {
  description = "The ID of the IPAM."
  value       = aws_vpc_ipam.resource.id
}

output "ipam_arn" {
  description = "The ARN of the IPAM."
  value       = aws_vpc_ipam.resource.arn
}

output "root_pool_id" {
  description = "The ID of the top-level IPv4 pool. Only the regional pools below are meant to be handed to terraform-aws-vpc directly."
  value       = aws_vpc_ipam_pool.root.id
}

output "root_ipv6_pool_id" {
  description = "The ID of the top-level IPv6 pool, if ipv6_cidr is set."
  value       = try(aws_vpc_ipam_pool.root_ipv6[0].id, null)
}

output "intermediate_pool_ids" {
  description = "Map of intermediate_pools key to its IPv4 pool ID. Reference one of these keys from a regional_pools entry's intermediate_pool field to carve that region from this intermediate pool instead of directly from the top-level pool."
  value       = { for k, p in aws_vpc_ipam_pool.intermediate : k => p.id }
}

output "intermediate_ipv6_pool_ids" {
  description = "Map of intermediate_pools key to its IPv6 pool ID, for entries where intermediate_pools set ipv6_netmask_length."
  value       = { for k, p in aws_vpc_ipam_pool.intermediate_ipv6 : k => p.id }
}

output "regional_pool_ids" {
  description = "Map of region to its IPv4 regional pool ID. Feed one of these into terraform-aws-vpc's ipv4_ipam_pool_id in that region, so every region's VPCs draw from non-overlapping address space."
  value       = { for k, p in aws_vpc_ipam_pool.regional : k => p.id }
}

output "regional_ipv6_pool_ids" {
  description = "Map of region to its IPv6 regional pool ID, for regions where regional_pools set ipv6_netmask_length. Feed one of these into terraform-aws-vpc's ipv6_ipam_pool_id."
  value       = { for k, p in aws_vpc_ipam_pool.regional_ipv6 : k => p.id }
}
