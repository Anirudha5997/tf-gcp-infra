resource "google_compute_network" "vpc_network" {
  for_each                        = var.vpc
  nam                            = each.value.vpc_name
  auto_create_subnetworks         = each.value.auto_create_subnets
  routing_mode                    = each.value.route_mode
  delete_default_routes_on_create = each.value.del_default_routes
  mtu                             = 1460
}


resource "google_compute_subnetwork" "subnet" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([for subnet_name, subnet_config in config.subnets :
        {
          subnet_name = subnet_config.subnet_name
          cidr_range  = subnet_config.cidr_range
          network     = google_compute_network.vpc_network[vpc_name].id
      }])

    ]) : idx => config
  }
  name          = each.value.subnet_name
  ip_cidr_range = each.value.cidr_range
  network       = each.value.network
}

resource "google_compute_route" "route" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([for route, route_config in config.routes :
        {
          route_name        = route_config.route_name
          destination_range = route_config.destination_range
          network           = google_compute_network.vpc_network[vpc_name].id
          next_hop_gateway  = route_config.next_hop_gateway
      }])

    ]) : idx => config

  }

  name             = each.value.route_name
  dest_range       = each.value.destination_range
  network          = each.value.network
  next_hop_gateway = each.value.next_hop_gateway
}


