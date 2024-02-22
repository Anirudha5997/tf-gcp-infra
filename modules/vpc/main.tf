resource "google_compute_network" "vpc_network" {
  for_each                        = var.vpc
  name                            = each.value.vpc_name
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
 
resource "google_compute_firewall" "firewall" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([for firewall, firewall_config in config.firewalls :
        {
          firewall_name = firewall_config.firewall_name
          network = google_compute_network.vpc_network[vpc_name].id
          allow = firewall_config.allow
          source_tags = firewall_config.source_tags
        }])

    ]) : idx => config
  }

  name    = each.value.firewall_name
  network = each.value.network
  source_tags = each.value.source_tags

  dynamic "allow" {
    for_each = each.value.allow
    content {
      protocol = allow.value.protocol
      ports = allow.value.ports
    }
  }
}

# dynamic "google_service_account" {
#   for_each = var.service_account
#   content{

#   }
# }

resource "google_compute_instance" "vm" {
    for_each = var.vm-properties
  
    name         = each.value.name
    machine_type = each.value.machine_type
    can_ip_forward      = each.value.can_ip_forward
    zone = each.value.zone

    dynamic "boot_disk" {
      for_each = tolist([each.value.boot_disk])

      content {
        auto_delete = boot_disk.value.auto_delete
        device_name = boot_disk.value.device_name
        mode = boot_disk.value.mode

        dynamic "initialize_params" {
          for_each = tolist([boot_disk.value.initialize_params])

          content {
            image = initialize_params.value.image
            size  = initialize_params.value.size
            type  = initialize_params.value.type
          }
        }
      }
    }

    dynamic "network_interface" {
      for_each = each.value.network_interface
      content {
        queue_count = network_interface.value.queue_count
        stack_type  = network_interface.value.stack_type
        subnetwork  = network_interface.value.subnetwork

        dynamic "access_config" {
            for_each = tolist([network_interface.value.access_config])
            content {
              network_tier = access_config.value.network_tier
            }
        }
      }
    }

    dynamic "scheduling" {
        for_each = each.value.scheduling

        content {
            automatic_restart   = scheduling.value.automatic_restart
            on_host_maintenance = scheduling.value.on_host_maintenance
            preemptible         = scheduling.value.preemptible
            provisioning_model  = scheduling.value.provisioning_model
        }
      
    }

    dynamic "service_account" {
        for_each = each.value.service_account
        
        content {
            email  = service_account.value.email
            scopes = service_account.value.scopes
        }
    }

    dynamic "shielded_instance_config" {
        for_each = each.value.shielded_instance_config

        content {
            enable_integrity_monitoring = shielded_instance_config.value.enable_integrity_monitoring
            enable_secure_boot          = shielded_instance_config.value.enable_secure_boot
            enable_vtpm                 = shielded_instance_config.value.enable_vtpm
        }
    }
}

