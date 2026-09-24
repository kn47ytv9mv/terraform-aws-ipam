mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }
}

run "regional_ipv6_requires_top_level_ipv6_cidr" {
  command = plan

  variables {
    cidr = "10.0.0.0/8"
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 12, ipv6_netmask_length = 44 }
    }
  }

  expect_failures = [var.regional_pools]
}

run "intermediate_ipv6_requires_top_level_ipv6_cidr" {
  command = plan

  variables {
    cidr = "10.0.0.0/8"
    intermediate_pools = {
      "platform" = { ipv4_netmask_length = 12, ipv6_netmask_length = 32 }
    }
  }

  expect_failures = [var.intermediate_pools]
}

run "regional_intermediate_pool_reference_must_exist" {
  command = plan

  variables {
    cidr = "10.0.0.0/8"
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 16, intermediate_pool = "nonexistent" }
    }
  }

  expect_failures = [var.regional_pools]
}

run "regional_ipv6_via_intermediate_requires_intermediate_ipv6" {
  command = plan

  variables {
    cidr      = "10.0.0.0/8"
    ipv6_cidr = "2001:db8::/32"
    intermediate_pools = {
      "platform" = { ipv4_netmask_length = 12 }
    }
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 16, ipv6_netmask_length = 44, intermediate_pool = "platform" }
    }
  }

  expect_failures = [var.regional_pools]
}

run "root_and_regional_pools_created" {
  command = apply

  variables {
    cidr = "10.0.0.0/8"
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 12 }
      "eu-west-1" = { ipv4_netmask_length = 12 }
    }
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.root.cidr == "10.0.0.0/8"
    error_message = "The root pool should be provisioned with the literal top-level CIDR."
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.regional) == 2
    error_message = "One regional pool should be created per entry in regional_pools."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["us-east-1"].locale == "us-east-1"
    error_message = "A regional pool's locale should match its map key."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["us-east-1"].source_ipam_pool_id == aws_vpc_ipam_pool.root.id
    error_message = "Every regional pool should be carved from the root pool, guaranteeing non-overlap."
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["eu-west-1"].netmask_length == 12
    error_message = "A regional pool's CIDR should be requested by netmask_length, not a literal cidr, so AWS auto-allocates it."
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.regional_ipv6) == 0
    error_message = "No regional_pools entry requested IPv6, so no IPv6 regional pools should exist."
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.root_ipv6) == 0
    error_message = "ipv6_cidr was not set, so no root IPv6 pool should exist."
  }
}

run "intermediate_pool_created_and_regional_carved_from_it" {
  command = apply

  variables {
    cidr = "10.0.0.0/8"
    intermediate_pools = {
      "platform" = { ipv4_netmask_length = 12 }
    }
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 16, intermediate_pool = "platform" }
      "eu-west-1" = { ipv4_netmask_length = 16 }
    }
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.intermediate) == 1
    error_message = "One intermediate pool should be created per entry in intermediate_pools."
  }

  assert {
    condition     = aws_vpc_ipam_pool.intermediate["platform"].source_ipam_pool_id == aws_vpc_ipam_pool.root.id
    error_message = "An intermediate pool should be carved from the root pool."
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.intermediate["platform"].netmask_length == 12
    error_message = "An intermediate pool's CIDR should be requested by netmask_length."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["us-east-1"].source_ipam_pool_id == aws_vpc_ipam_pool.intermediate["platform"].id
    error_message = "A regional pool naming an intermediate_pool should be carved from that intermediate pool, not the root pool."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["eu-west-1"].source_ipam_pool_id == aws_vpc_ipam_pool.root.id
    error_message = "A regional pool with no intermediate_pool set should still be carved directly from the root pool — existing 2-level configurations stay unaffected."
  }
}

run "no_intermediate_pools_by_default" {
  command = plan

  variables {
    cidr = "10.0.0.0/8"
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 12 }
    }
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.intermediate) == 0
    error_message = "Leaving intermediate_pools unset should create no intermediate pools."
  }
}

run "operating_regions_includes_current_region_deduped" {
  command = plan

  variables {
    cidr = "10.0.0.0/8"
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 12 }
    }
  }

  assert {
    condition     = length(aws_vpc_ipam.resource.operating_regions) == 1
    error_message = "The mock's current region (us-east-1) and the one listed regional pool are the same region, so operating_regions should be deduplicated down to one entry."
  }
}

run "operating_regions_adds_current_region_when_not_listed" {
  command = plan

  variables {
    cidr = "10.0.0.0/8"
    regional_pools = {
      "eu-west-1" = { ipv4_netmask_length = 12 }
    }
  }

  assert {
    condition     = length(aws_vpc_ipam.resource.operating_regions) == 2
    error_message = "The IPAM's own home region should always be included in operating_regions, even when not explicitly listed in regional_pools."
  }
}

run "ipv6_root_and_regional_pools_created" {
  command = apply

  variables {
    cidr      = "10.0.0.0/8"
    ipv6_cidr = "2001:db8::/32"
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 12, ipv6_netmask_length = 44 }
    }
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.root_ipv6) == 1
    error_message = "ipv6_cidr was set, so a root IPv6 pool should be created."
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.root_ipv6[0].cidr == "2001:db8::/32"
    error_message = "The root IPv6 pool should be provisioned with the literal ipv6_cidr."
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.regional_ipv6) == 1
    error_message = "The one regional_pools entry that set ipv6_netmask_length should get its own IPv6 regional pool."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional_ipv6["us-east-1"].source_ipam_pool_id == aws_vpc_ipam_pool.root_ipv6[0].id
    error_message = "The IPv6 regional pool should be carved from the IPv6 root pool."
  }
}

run "ipv6_regional_pool_via_intermediate_carved_from_intermediate_ipv6" {
  command = apply

  variables {
    cidr      = "10.0.0.0/8"
    ipv6_cidr = "2001:db8::/32"
    intermediate_pools = {
      "platform" = { ipv4_netmask_length = 12, ipv6_netmask_length = 36 }
    }
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 16, ipv6_netmask_length = 44, intermediate_pool = "platform" }
    }
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.intermediate_ipv6) == 1
    error_message = "The intermediate pool that set ipv6_netmask_length should get its own IPv6 intermediate pool."
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional_ipv6["us-east-1"].source_ipam_pool_id == aws_vpc_ipam_pool.intermediate_ipv6["platform"].id
    error_message = "A regional IPv6 pool naming an intermediate_pool should be carved from that intermediate pool's own IPv6 pool, not the root IPv6 pool."
  }
}

run "readme_default_example" {
  command = plan

  variables {
    cidr = "10.0.0.0/8"
    regional_pools = {
      "us-east-1" = { ipv4_netmask_length = 12 }
      "eu-west-1" = { ipv4_netmask_length = 12 }
    }
  }

  assert {
    condition     = length(aws_vpc_ipam_pool.regional) == 2
    error_message = "The README's usage example should plan two regional pools."
  }
}

run "readme_intermediate_pools_example" {
  command = plan

  variables {
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

  assert {
    condition     = length(aws_vpc_ipam_pool.intermediate) == 2
    error_message = "The README's multi-team example should plan two intermediate pools."
  }
}
