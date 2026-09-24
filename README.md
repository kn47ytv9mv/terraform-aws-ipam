# terraform-aws-ipam

Terraform module for an AWS VPC IP Address Manager (IPAM), structured as a
top-level pool with one regional child pool per AWS region, and an
optional intermediate pool layer for a multi-team org.

## Cost

The IPAM itself is free at the 'free' tier, which covers a single account
managing its own private address space — the common case this module is
built for. The 'advanced' tier bills per active region per month and is
only needed for cross-account resource discovery, more than three pools,
or allocation tagging enforcement. Pools and CIDR allocations carry no
charge of their own. See AWS's
[IPAM pricing](https://aws.amazon.com/vpc/pricing/) page for current
rates.

## Design

Every regional VPC needs a CIDR block that does not overlap with any other
region's, or inter-region connectivity (Transit Gateway peering, VPC
peering) cannot work. This module enforces that with a pool hierarchy
instead of leaving CIDR math to the caller:

- One **top-level pool**, provisioned with the literal address space this
  IPAM owns (`cidr`, e.g. `10.0.0.0/8`).
- Optionally, one or more **intermediate pools** (`intermediate_pools`),
  each requesting a netmask length out of the top-level pool. Useful for a
  multi-team org that needs its own address-space allocation — a business
  unit or a set of accounts — before regions are carved further, on top of
  the per-region isolation regional pools already give every caller.
- One **regional pool** per entry in `regional_pools`, each requesting a
  netmask length (`ipv4_netmask_length`) rather than a literal CIDR block.
  By default a regional pool is carved directly from the top-level pool;
  setting that entry's `intermediate_pool` to a key from
  `intermediate_pools` carves it from that intermediate pool instead. AWS
  itself carves every pool's block out of its source pool's remaining
  space, so two siblings can never be handed the same address range — the
  guarantee comes from AWS's own allocation, not from Terraform-side
  arithmetic.

Hand a regional pool's ID (see the `regional_pool_ids` output) to
`terraform-aws-vpc`'s `ipv4_ipam_pool_id` in that region, and that VPC's
CIDR is guaranteed clear of every other region using this same IPAM,
regardless of how many intermediate levels sit above it.

IPv6 follows the identical shape via `ipv6_cidr` and
`ipv6_netmask_length`, for BYOIP IPv6 address space — including through an
intermediate pool, provided that intermediate pool also set its own
`ipv6_netmask_length`.

**Consuming a regional pool ID in the same `apply` that creates it can
transiently fail** — a VPC's `CreateVpc` call rejected with `The
allocation size is too big for the pool`, even though the size clearly
fits. IPAM and EC2 are separate services with a real propagation gap
between them; no Terraform-level wait closes it. The failure is clean
and retry-safe — a second `terraform apply` succeeds once AWS catches
up, typically within a couple of minutes.

**The same gap shows up on `destroy` too, past around a dozen regional
pools.** Once every consuming VPC is gone, releasing the pool CIDRs can
still fail with `waiting for IPAM Pool allocations to be released:
timeout... ipam-cidr-allocations-exist`, outlasting AWS's own internal
32-minute wait. Also clean and retry-safe — a second `terraform destroy`
succeeds once AWS's release-side propagation has caught up.

## Usage

```hcl
module "ipam" {
  source = "kn47ytv9mv/ipam/aws"

  cidr = "10.0.0.0/8"

  regional_pools = {
    "us-east-1" = { ipv4_netmask_length = 12 }
    "eu-west-1" = { ipv4_netmask_length = 12 }
  }
}

module "vpc_us_east_1" {
  source = "kn47ytv9mv/vpc/aws"

  providers = { aws = aws.us_east_1 }

  ipv4_ipam_pool_id   = module.ipam.regional_pool_ids["us-east-1"]
  ipv4_netmask_length = 16
}
```

Or directly from this repository, a multi-team org giving each business
unit its own intermediate pool before regions are carved further:

```hcl
module "ipam" {
  source = "github.com/kn47ytv9mv/terraform-aws-ipam"

  cidr = "10.0.0.0/8"

  intermediate_pools = {
    "platform" = { ipv4_netmask_length = 12 }
    "data-eng" = { ipv4_netmask_length = 12 }
  }

  regional_pools = {
    "us-east-1" = { ipv4_netmask_length = 16, intermediate_pool = "platform" }
    "eu-west-1" = { ipv4_netmask_length = 16, intermediate_pool = "data-eng" }
  }
}
```

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| description | Description of the IPAM. | `null` | no |
| tier | IPAM tier (`'free'` or `'advanced'`). Advanced is required for more than three pools, cross-account resource discovery, or allocation tagging enforcement. If null, AWS's own default applies. | `null` | no |
| cascade | Whether to delete the IPAM's pools, scopes, and allocations along with the IPAM itself on destroy, instead of requiring them to be emptied first. | `false` | no |
| cidr | Top-level IPv4 CIDR this IPAM owns (e.g. `'10.0.0.0/8'`). Every regional pool in `regional_pools` is carved out of this block by AWS itself, so regions can never be allocated overlapping address space. | `null` | no |
| ipv6_cidr | Top-level IPv6 CIDR this IPAM owns, if using BYOIP IPv6. Same role as `cidr`, for IPv6. Amazon-provided (non-BYOIP) IPv6 through IPAM is not supported by this module. | `null` | no |
| intermediate_pools | Intermediate child pools to create between the top-level pool and `regional_pools`, keyed by an arbitrary name (e.g. a business unit or account name — `'platform'`, `'data-eng'`). Each entry needs `ipv4_netmask_length`, the prefix length AWS carves out of `cidr` for that pool; `ipv6_netmask_length` is optional and requires `ipv6_cidr` to also be set. Useful for a multi-team org that needs its own address-space allocation before regions are carved further, on top of the per-region isolation `regional_pools` already gives every caller. A `regional_pools` entry opts into sourcing from one of these via its own `intermediate_pool` field; leaving `intermediate_pools` empty (the default) leaves every existing 2-level (root -> regional) configuration unaffected. | `{}` | no |
| regional_pools | Regional child pools to create, keyed by AWS region name (e.g. `'us-east-1'`). Each entry needs `ipv4_netmask_length` — the prefix length AWS carves out of its source pool for that region (e.g. `12` for a `/12` out of a `/8`). `ipv6_netmask_length` is optional and requires `ipv6_cidr` to also be set. `intermediate_pool` is optional — set it to a key from `intermediate_pools` to carve this regional pool from that intermediate pool instead of directly from the top-level pool. Feed the resulting pool ID (see the `regional_pool_ids` and `regional_ipv6_pool_ids` outputs) into `terraform-aws-vpc`'s `ipv4_ipam_pool_id`/`ipv6_ipam_pool_id` for that region. | `{}` | no |
| tags | A map of tags to assign to all resources created by this module. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| ipam_id | The ID of the IPAM. |
| ipam_arn | The ARN of the IPAM. |
| root_pool_id | The ID of the top-level IPv4 pool. Only the regional pools below are meant to be handed to `terraform-aws-vpc` directly. |
| root_ipv6_pool_id | The ID of the top-level IPv6 pool, if `ipv6_cidr` is set. |
| intermediate_pool_ids | Map of `intermediate_pools` key to its IPv4 pool ID. Reference one of these keys from a `regional_pools` entry's `intermediate_pool` field to carve that region from this intermediate pool instead of directly from the top-level pool. |
| intermediate_ipv6_pool_ids | Map of `intermediate_pools` key to its IPv6 pool ID, for entries where `intermediate_pools` set `ipv6_netmask_length`. |
| regional_pool_ids | Map of region to its IPv4 regional pool ID. Feed one of these into `terraform-aws-vpc`'s `ipv4_ipam_pool_id` in that region, so every region's VPCs draw from non-overlapping address space. |
| regional_ipv6_pool_ids | Map of region to its IPv6 regional pool ID, for regions where `regional_pools` set `ipv6_netmask_length`. Feed one of these into `terraform-aws-vpc`'s `ipv6_ipam_pool_id`. |

## License

MIT — see [LICENSE.md](LICENSE.md).
