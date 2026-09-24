variable "description" {
  default     = null
  description = "Description of the IPAM."
}

variable "tier" {
  default     = null
  description = "IPAM tier ('free' or 'advanced'). Advanced is required for more than three pools, cross-account resource discovery, or allocation tagging enforcement. If null, AWS's own default applies."
}

variable "cascade" {
  default     = false
  description = "Whether to delete the IPAM's pools, scopes, and allocations along with the IPAM itself on destroy, instead of requiring them to be emptied first."
}

variable "cidr" {
  default     = null
  description = "Top-level IPv4 CIDR this IPAM owns (e.g. '10.0.0.0/8'). Every regional pool in regional_pools is carved out of this block by AWS itself, so regions can never be allocated overlapping address space."
}

variable "ipv6_cidr" {
  default     = null
  description = "Top-level IPv6 CIDR this IPAM owns, if using BYOIP IPv6. Same role as cidr, for IPv6. Amazon-provided (non-BYOIP) IPv6 through IPAM is not supported by this module."
}

variable "intermediate_pools" {
  default     = {}
  description = "Intermediate child pools to create between the top-level pool and regional_pools, keyed by an arbitrary name (e.g. a business unit or account name — 'platform', 'data-eng'). Each entry needs ipv4_netmask_length, the prefix length AWS carves out of cidr for that pool; ipv6_netmask_length is optional and requires ipv6_cidr to also be set. Useful for a multi-team org that needs its own address-space allocation before regions are carved further, on top of the per-region isolation regional_pools already gives every caller. A regional_pools entry opts into sourcing from one of these via its own intermediate_pool field; leaving intermediate_pools empty (the default) leaves every existing 2-level (root -> regional) configuration unaffected."
  type = map(object({
    ipv4_netmask_length = number
    ipv6_netmask_length = optional(number)
  }))

  validation {
    condition     = var.ipv6_cidr != null || alltrue([for k, v in var.intermediate_pools : v.ipv6_netmask_length == null])
    error_message = "An intermediate pool's ipv6_netmask_length can only be set when ipv6_cidr is also set."
  }
}

variable "regional_pools" {
  default     = {}
  description = "Regional child pools to create, keyed by AWS region name (e.g. 'us-east-1'). Each entry needs ipv4_netmask_length — the prefix length AWS carves out of its source pool for that region (e.g. 12 for a /12 out of a /8). ipv6_netmask_length is optional and requires ipv6_cidr to also be set. intermediate_pool is optional — set it to a key from intermediate_pools to carve this regional pool from that intermediate pool instead of directly from the top-level pool. Feed the resulting pool ID (see the regional_pool_ids and regional_ipv6_pool_ids outputs) into terraform-aws-vpc's ipv4_ipam_pool_id/ipv6_ipam_pool_id for that region."
  type = map(object({
    ipv4_netmask_length = number
    ipv6_netmask_length = optional(number)
    intermediate_pool   = optional(string)
  }))

  validation {
    condition     = var.ipv6_cidr != null || alltrue([for k, v in var.regional_pools : v.ipv6_netmask_length == null])
    error_message = "A regional pool's ipv6_netmask_length can only be set when ipv6_cidr is also set."
  }

  validation {
    condition     = alltrue([for k, v in var.regional_pools : v.intermediate_pool == null || contains(keys(var.intermediate_pools), v.intermediate_pool)])
    error_message = "A regional_pools entry's intermediate_pool must reference a key present in intermediate_pools."
  }

  validation {
    condition = alltrue([
      for k, v in var.regional_pools :
      v.intermediate_pool == null || v.ipv6_netmask_length == null ||
      (contains(keys(var.intermediate_pools), v.intermediate_pool) && var.intermediate_pools[v.intermediate_pool].ipv6_netmask_length != null)
    ])
    error_message = "A regional_pools entry with both intermediate_pool and ipv6_netmask_length set requires that intermediate pool to also have ipv6_netmask_length set."
  }
}

variable "tags" {
  default     = null
  description = "A map of tags to assign to all resources created by this module."
}
