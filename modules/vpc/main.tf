resource "random_password" "password" {
  length    = 16
  special   = false
  min_upper = 2
  min_lower = 7
}

# data "template_file" "startup_script_config" {
#   template = file("${path.module}/startup_script.sh")
#   vars = {
#     database_host     = google_sql_database_instance.postgressInstance.ip_address[0].ip_address
#     database_name     = google_sql_database.postgres.name
#     database_password = random_password.password.result
#     database_username = google_sql_database.postgres.username
#   }
# }

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
          network       = google_compute_network.vpc_network[vpc_name].id
          allow         = firewall_config.allow
          deny          = firewall_config.deny
          source_tags   = firewall_config.source_tags
          source_ranges = firewall_config.source_ranges
      }])
    ]) : idx => config
  }

  name          = each.value.firewall_name
  network       = each.value.network
  source_tags   = each.value.source_tags
  source_ranges = each.value.source_ranges

  dynamic "allow" {
    for_each = each.value.allow
    content {
      protocol = allow.value.protocol
      ports    = allow.value.ports
    }
  }

  dynamic "deny" {
    for_each = each.value.deny
    content {
      protocol = deny.value.protocol
      ports    = deny.value.ports
    }
  }
}

resource "google_compute_global_address" "private" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([for private_ip_alloc, private_ip_alloc_config in tolist([config.private_ip_alloc]) :
        {
          name          = private_ip_alloc_config.name
          address_type  = private_ip_alloc_config.address_type
          purpose       = private_ip_alloc_config.purpose
          prefix_length = private_ip_alloc_config.prefix_length
          network       = google_compute_network.vpc_network[vpc_name].id
      }])
    ]) : idx => config
  }

  name          = each.value.name
  address_type  = each.value.address_type
  purpose       = each.value.purpose
  prefix_length = each.value.prefix_length
  network       = each.value.network
}

resource "google_compute_instance" "vm" {
  for_each = var.vm-properties

  metadata = {
    startup-script = <<-EOT
    #!/bin/bash
    echo -e "HOST=${google_sql_database_instance.postgresInstance[0].ip_address[0].ip_address}\nDATABASE=${google_sql_database.postgres[0].name}\nPASSWORD=${random_password.password.result}\nPGUSER=${google_sql_user.user[0].name}\nDBPORT=5432" > /tmp/.env
    sudo mv -f /tmp/.env /home/prodApp/.env
    cd /home/prodApp
    sudo /bin/bash bootstrap.sh
    sudo chown -R csye6225:csye6225 /home/prodApp
    sudo systemctl restart csye6225
    EOT 
  }

  name                = each.value.name
  machine_type        = each.value.machine_type
  zone                = each.value.zone
  can_ip_forward      = each.value.can_ip_forward
  deletion_protection = each.value.deletion_protection
  enable_display      = each.value.enable_display
  tags                = each.value.tags
  depends_on = [
    google_compute_subnetwork.subnet,
    google_sql_database_instance.postgresInstance,
    google_sql_database.postgres,
    google_sql_user.user
  ]

  labels = each.value.labels

  dynamic "boot_disk" {
    for_each = tolist([each.value.boot_disk])

    content {
      auto_delete = boot_disk.value.auto_delete
      device_name = boot_disk.value.device_name
      mode        = boot_disk.value.mode

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
      dynamic "access_config" {
        for_each = tolist([network_interface.value.access_config])
        content {
          network_tier = access_config.value.network_tier
        }
      }

      queue_count = network_interface.value.queue_count
      stack_type  = network_interface.value.stack_type
      subnetwork  = network_interface.value.subnetwork
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

resource "google_service_networking_connection" "private_vpc_connection" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([for private_ip_alloc, private_ip_alloc_config in config.private_ip_alloc :
        {
          network          = google_compute_network.vpc_network[vpc_name].id
          reserved_peering = google_compute_global_address.private[0].name
      }])
    ]) : idx => config
  }

  network                 = each.value.network
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [each.value.reserved_peering]
  deletion_policy         = "ABANDON"
  depends_on              = [google_compute_network.vpc_network, google_compute_global_address.private]
}

resource "google_sql_database_instance" "postgresInstance" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([
        for databaseInstance, databaseInstance_config in tolist([config.databaseInstance]) : {
          vpc_name            = vpc_name
          name                = databaseInstance_config.name
          database_version    = databaseInstance_config.database_version
          deletion_protection = databaseInstance_config.deletion_protection
          settings            = databaseInstance_config.settings
      }])
    ]) : idx => config
  }

  name                = each.value.name
  database_version    = each.value.database_version
  depends_on          = [google_service_networking_connection.private_vpc_connection]
  deletion_protection = each.value.deletion_protection

  dynamic "settings" {
    for_each = tolist([each.value.settings])
    content {
      tier              = settings.value.tier
      edition           = settings.value.edition
      disk_size         = settings.value.disk_size
      disk_type         = settings.value.disk_type
      availability_type = settings.value.availability_type
      location_preference {
        zone = var.zone
      }

      dynamic "ip_configuration" {
        for_each = tolist([settings.value.ip_configuration])
        content {
          ipv4_enabled                                  = ip_configuration.value.ipv4_enabled
          private_network                               = google_compute_network.vpc_network[each.value.vpc_name].id
          enable_private_path_for_google_cloud_services = ip_configuration.value.enable_private_path_for_google_cloud_services
        }
      }

      dynamic "backup_configuration" {
        for_each = tolist([settings.value.backup_configuration])
        content {
          enabled                        = backup_configuration.value.enabled
          point_in_time_recovery_enabled = backup_configuration.value.point_in_time_recovery_enabled
        }
      }
    }
  }
}

resource "google_sql_user" "user" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([
        for databaseInstance, databaseInstance_config in tolist([config.databaseInstance]) : flatten([
          for user, user_config in tolist([databaseInstance_config.user]) : {
            name = user_config.name
            # instance = user_config.instance
            # host     = user_config.host
            password = random_password.password.result
      }])])
    ]) : idx => config
  }
  name     = each.value.name
  instance = google_sql_database_instance.postgresInstance[0].name
  # host     = each.value.host
  password   = each.value.password
  depends_on = [google_sql_database_instance.postgresInstance]
}

resource "google_sql_database" "postgres" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([
        for databaseInstance, databaseInstance_config in tolist([config.databaseInstance]) : flatten([
          for database, database_config in tolist([databaseInstance_config.database]) : {
            name = database_config.name
      }])])
    ]) : idx => config
  }
  name       = each.value.name
  instance   = google_sql_database_instance.postgresInstance[0].name
  depends_on = [google_sql_database_instance.postgresInstance]
}

locals {
  timestamp_value = formatdate("YYYYMMDDhhmmss", timestamp())
}
