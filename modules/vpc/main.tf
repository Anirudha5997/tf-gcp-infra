resource "random_password" "password" {
  length    = 16
  special   = false
  min_upper = 2
  min_lower = 7
}

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

resource "google_vpc_access_connector" "vpc_connector" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([
        for vpc_connector, vpc_connector_config in tolist([config.vpc_connector]) : {
          name          = vpc_connector_config.name
          ip_cidr_range = vpc_connector_config.ip_cidr_range
          machine_type  = vpc_connector_config.machine_type
          min_instances = vpc_connector_config.min_instances
          max_instances = vpc_connector_config.max_instances
          network       = google_compute_network.vpc_network[vpc_name].id
      }])
    ]) : idx => config
  }
  name          = each.value.name
  ip_cidr_range = each.value.ip_cidr_range
  machine_type  = each.value.machine_type
  min_instances = each.value.min_instances
  max_instances = each.value.max_instances
  network       = each.value.network
  depends_on    = [google_compute_network.vpc_network]
}

resource "google_compute_network_peering_routes_config" "peering_primary_routes" {
  for_each = {
    for idx, config in flatten([
      for vpc_name, config in var.vpc : flatten([
        for private_ip_alloc, private_ip_alloc_config in tolist([config.private_ip_alloc]) : flatten([
          for vpc_connector_peering_routes, vpc_connector_peering_routes_config in tolist([private_ip_alloc_config.vpc_connector_peering_routes]) :
          {
            import_custom_routes = vpc_connector_peering_routes_config.import_custom_routes
            export_custom_routes = vpc_connector_peering_routes_config.export_custom_routes
            network              = vpc_name
            peering              = private_ip_alloc_config
          }
      ])])
    ]) : idx => config
  }
  peering = google_service_networking_connection.private_vpc_connection[0].peering
  network = google_compute_network.vpc_network[each.value.network].name

  import_custom_routes = each.value.import_custom_routes
  export_custom_routes = each.value.export_custom_routes
  depends_on           = [google_service_networking_connection.private_vpc_connection, google_compute_network.vpc_network]
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
    echo -e "GCP_PROJECT_ID=${var.project_id}\nGCP_TOPIC=${google_pubsub_topic.topic_tf.name}\nHOST=${google_sql_database_instance.postgresInstance[0].ip_address[0].ip_address}\nDATABASE=${google_sql_database.postgres[0].name}\nPASSWORD=${random_password.password.result}\nPGUSER=${google_sql_user.user[0].name}\nDBPORT=5432" > /tmp/.env
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
    google_sql_user.user,
    google_service_account.service_account
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
      email  = google_service_account.service_account[service_account.value.service_account_name].email
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
      for vpc_name, config in var.vpc : flatten([for private_ip_alloc, private_ip_alloc_config in tolist([config.private_ip_alloc]) :
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

resource "google_dns_record_set" "DNSrecords" {
  for_each = {
    for idx, config in flatten([
      for vm_name, config in var.vm-properties : flatten([
        for cloud_dns_properties, cloud_dns_properties_config in config.cloud_dns_properties :
        {
          type            = cloud_dns_properties_config.type
          ttl             = cloud_dns_properties_config.ttl
          name            = vm_name
          dns_record_name = cloud_dns_properties_config.dns_record_name
          rrdatas         = cloud_dns_properties_config.rrdatas
      }])
    ]) : idx => config
  }

  name         = each.value.dns_record_name == "" ? data.google_dns_managed_zone.prod.dns_name : each.value.dns_record_name
  managed_zone = data.google_dns_managed_zone.prod.name
  type         = each.value.type
  ttl          = each.value.ttl
  rrdatas      = each.value.type == "A" ? [google_compute_instance.vm[each.value.name].network_interface[0].access_config[0].nat_ip] : each.value.rrdatas
  depends_on   = [google_compute_instance.vm]
}

data "google_dns_managed_zone" "prod" {
  name = var.manage_zone_name
}

resource "google_service_account" "service_account" {
  for_each                     = var.service_accounts_properties
  account_id                   = each.value.account_id
  display_name                 = each.value.display_name
  create_ignore_already_exists = each.value.create_ignore_already_exists
}

resource "google_project_iam_binding" "project_roles" {
  for_each = {
    for idx, config in flatten([
      for service_acc, service_acc_config in var.service_accounts_properties : flatten([
        for iam_role in service_acc_config.iam_binding_roles : {
          role            = iam_role
          service_account = service_acc
        }
      ])
    ]) : idx => config
  }

  project    = var.project_id
  role       = each.value.role
  depends_on = [google_service_account.service_account]

  members = [
    "serviceAccount:${google_service_account.service_account[each.value.service_account].email}",
  ]
}

resource "google_pubsub_topic" "topic_tf" {
  name = var.pubsub_topic_name
  labels = {
    pubsubtopic = "pubsubtopic"
  }
}

resource "google_pubsub_subscription" "pull_sub" {
  for_each = var.pubsub_pull_subscription
  name     = each.value.name
  topic    = google_pubsub_topic.topic_tf.id

  labels = {
    pbsubscription = "pbsubscription"
  }

  # 7 Days
  message_retention_duration = each.value.message_retention_duration
  retain_acked_messages      = each.value.retain_acked_messages

  ack_deadline_seconds    = each.value.ack_deadline_seconds
  enable_message_ordering = each.value.enable_message_ordering
}

data "google_storage_bucket" "cloud_bucket" {
  name = var.cloud_bucket_name
}

data "google_storage_bucket_object" "archive" {
  name   = var.archive_name
  bucket = data.google_storage_bucket.cloud_bucket.name
}

resource "google_cloudfunctions2_function" "function" {
  for_each    = var.cloud_function_properties
  name        = each.value.name
  location    = each.value.location
  description = each.value.description
  depends_on  = [google_service_account.service_account, google_sql_database_instance.postgresInstance, google_sql_database.postgres, random_password.password, google_sql_user.user]

  dynamic "build_config" {
    for_each = tolist([each.value.build_config])
    content {
      runtime     = build_config.value.runtime
      entry_point = build_config.value.entry_point #check correct entry point
      source {
        storage_source {
          bucket = data.google_storage_bucket.cloud_bucket.name
          object = data.google_storage_bucket_object.archive.name
        }
      }
    }
  }

  dynamic "service_config" {
    for_each = tolist([each.value.service_config])
    content {
      max_instance_count             = service_config.value.max_instance_count
      min_instance_count             = service_config.value.min_instance_count
      available_memory               = service_config.value.available_memory
      timeout_seconds                = service_config.value.timeout_seconds
      environment_variables          = merge(service_config.value.environment_variables, local.cloud_function_environmental_variables)
      ingress_settings               = service_config.value.ingress_settings
      all_traffic_on_latest_revision = service_config.value.all_traffic_on_latest_revision
      service_account_email          = google_service_account.service_account[service_config.value.service_account_email].email
      vpc_connector                  = google_vpc_access_connector.vpc_connector[service_config.value.vpc_connector].name
      vpc_connector_egress_settings  = service_config.value.vpc_connector_egress_settings
    }
  }

  dynamic "event_trigger" {
    for_each = tolist([each.value.event_trigger])
    content {
      trigger_region = event_trigger.value.trigger_region
      event_type     = event_trigger.value.event_type
      pubsub_topic   = google_pubsub_topic.topic_tf.id
      retry_policy   = event_trigger.value.retry_policy
    }
  }
}

locals {
  timestamp_value = formatdate("YYYYMMDDhhmmss", timestamp())
  cloud_function_environmental_variables = {
    HOST     = google_sql_database_instance.postgresInstance[0].ip_address[0].ip_address
    DATABASE = google_sql_database.postgres[0].name
    PASSWORD = random_password.password.result
    PGUSER   = google_sql_user.user[0].name
    DBPORT   = 5432
  }
}