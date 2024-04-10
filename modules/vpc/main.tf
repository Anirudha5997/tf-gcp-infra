resource "random_password" "password" {
  length    = 16
  special   = false
  min_upper = 2
  min_lower = 7
}

resource "random_password" "name" {
  length    = 7
  special   = false
  min_upper = 2
  min_lower = 4
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
          purpose     = subnet_config.purpose
          role        = subnet_config.role
      }])

    ]) : idx => config
  }
  name          = each.value.subnet_name
  ip_cidr_range = each.value.cidr_range
  network       = each.value.network
  purpose       = each.value.purpose
  role          = each.value.role
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

  name             = each.value.name
  database_version = each.value.database_version
  depends_on = [
    google_service_networking_connection.private_vpc_connection,
  ]
  deletion_protection = each.value.deletion_protection
  encryption_key_name = google_kms_crypto_key.cloudsql_keys.id

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

resource "google_storage_bucket" "cloud_bucket" {
  name                     = var.cloud_bucket_name
  location                 = var.cloud_bucket_location
  force_destroy            = var.cloud_bucket_force_destroy
  public_access_prevention = var.cloud_bucket_public_access_prevention
  depends_on               = [google_kms_crypto_key_iam_binding.bucket_key_bind]
  encryption {
    default_kms_key_name = google_kms_crypto_key.bucket_keys.id
  }
}

resource "google_storage_bucket_object" "bucket_object" {
  name       = var.cloud_bucket_object_name                     # folder name should end with '/'
  source     = "${path.module}/${var.cloud_bucket_object_name}" # content is ignored but should be non-empty
  bucket     = google_storage_bucket.cloud_bucket.name
  depends_on = [google_storage_bucket.cloud_bucket]
}

resource "google_cloudfunctions2_function" "function" {
  for_each    = var.cloud_function_properties
  name        = each.value.name
  location    = each.value.location
  description = each.value.description
  depends_on  = [google_service_account.service_account, google_sql_database_instance.postgresInstance, google_sql_database.postgres, random_password.password, google_sql_user.user, google_storage_bucket.cloud_bucket, google_storage_bucket_object.bucket_object]

  dynamic "build_config" {
    for_each = tolist([each.value.build_config])
    content {
      runtime     = build_config.value.runtime
      entry_point = build_config.value.entry_point #check correct entry point
      source {
        storage_source {
          bucket = google_storage_bucket.cloud_bucket.name
          object = google_storage_bucket_object.bucket_object.name
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

resource "google_dns_record_set" "DNSrecords" {
  for_each = {
    for idx, config in flatten([
      for vm_name, config in var.webapp_instance_template_properties : flatten([
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
  rrdatas      = each.value.type == "A" ? [google_compute_global_forwarding_rule.google_compute_forwarding_rule.ip_address] : each.value.rrdatas
  depends_on   = [google_compute_global_forwarding_rule.google_compute_forwarding_rule]
}

resource "google_compute_region_instance_template" "webapp_instance_template" {
  for_each    = var.webapp_instance_template_properties
  name        = each.value.name
  description = each.value.description
  # instance_description = "description assigned to instances"
  region         = each.value.region
  machine_type   = each.value.machine_type
  can_ip_forward = each.value.can_ip_forward
  tags           = each.value.tags
  labels         = each.value.labels

  depends_on = [
    google_compute_subnetwork.subnet,
    google_sql_database_instance.postgresInstance,
    google_sql_database.postgres,
    google_sql_user.user,
    google_service_account.service_account,
    google_kms_crypto_key.template_keys
  ]
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

  dynamic "disk" {
    for_each = tolist([each.value.disk])

    content {
      auto_delete  = disk.value.auto_delete
      device_name  = disk.value.device_name
      mode         = disk.value.mode
      source_image = disk.value.source_image
      disk_type    = disk.value.disk_type
      disk_size_gb = disk.value.disk_size_gb
      disk_encryption_key {
        kms_key_self_link = google_kms_crypto_key.template_keys.id
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

resource "google_compute_health_check" "health_check" {
  for_each            = var.health_check
  name                = each.value.name
  description         = each.value.description
  timeout_sec         = each.value.timeout_sec
  check_interval_sec  = each.value.check_interval_sec
  healthy_threshold   = each.value.healthy_threshold
  unhealthy_threshold = each.value.unhealthy_threshold

  dynamic "http_health_check" {
    for_each = tolist([each.value.http_health_check])
    content {
      port         = http_health_check.value.port
      request_path = http_health_check.value.request_path
      proxy_header = http_health_check.value.proxy_header
    }
  }
}

# resource "google_compute_target_pool" "target_pool" {
#   name    = var.pool_name
#   project = var.project_id
# }
resource "google_compute_region_instance_group_manager" "group_manager" {
  for_each                  = var.group_manager
  name                      = each.value.name
  base_instance_name        = each.value.base_instance_name
  region                    = each.value.region
  distribution_policy_zones = each.value.distribution_policy_zones
  depends_on = [
    google_compute_region_instance_template.webapp_instance_template,
    # google_compute_target_pool.target_pool,
    google_compute_health_check.health_check
  ]

  version {
    instance_template = google_compute_region_instance_template.webapp_instance_template["vm1"].self_link
  }

  all_instances_config {
    labels = {
      igm = "igm-label"
    }
  }

  # target_pools = [google_compute_target_pool.target_pool.id]
  # target_size  = each.value.target_size

  dynamic "named_port" {
    for_each = tolist([each.value.named_port])
    content {
      name = named_port.value.name
      port = named_port.value.port
    }
  }

  dynamic "auto_healing_policies" {
    for_each = tolist([each.value.auto_healing_policies])
    content {
      health_check      = google_compute_health_check.health_check["health_check1"].id
      initial_delay_sec = auto_healing_policies.value.initial_delay_sec
    }
  }
}

resource "google_compute_region_autoscaler" "autoscaler" {
  for_each   = var.autoscaler
  name       = each.value.name
  region     = each.value.region
  target     = google_compute_region_instance_group_manager.group_manager["group_manager1"].id
  depends_on = [google_compute_region_instance_group_manager.group_manager]

  dynamic "autoscaling_policy" {
    for_each = tolist([each.value.autoscaling_policy])
    content {
      max_replicas    = autoscaling_policy.value.max_replicas
      min_replicas    = autoscaling_policy.value.min_replicas
      cooldown_period = autoscaling_policy.value.cooldown_period
      dynamic "cpu_utilization" {
        for_each = tolist([autoscaling_policy.value.cpu_utilization])
        content {
          target = cpu_utilization.value.target
        }
      }
    }
  }
}

###################### EXTERNAL LOAD BALANCER ###########################
resource "google_compute_target_https_proxy" "target_proxy" {
  name             = var.target_proxy_name
  url_map          = google_compute_url_map.url_mapper.id
  ssl_certificates = [google_compute_managed_ssl_certificate.ssl_cert.id]
  depends_on = [
    google_compute_url_map.url_mapper,
    google_compute_managed_ssl_certificate.ssl_cert
  ]
}

resource "google_compute_managed_ssl_certificate" "ssl_cert" {
  name = var.ssl_cert_name
  managed {
    domains = var.ssl_domain
  }
}

resource "google_compute_url_map" "url_mapper" {
  name            = var.url_mapper
  default_service = google_compute_backend_service.backend_service["backend_service1"].id
  depends_on      = [google_compute_backend_service.backend_service]
}

resource "google_compute_backend_service" "backend_service" {
  for_each              = var.backend_service
  name                  = each.value.name
  project               = var.project_id
  provider              = google-beta
  port_name             = each.value.port_name
  protocol              = each.value.protocol
  load_balancing_scheme = each.value.load_balancing_scheme
  locality_lb_policy    = each.value.locality_lb_policy

  depends_on = [
    google_compute_region_instance_group_manager.group_manager,
    google_compute_health_check.health_check
  ]

  dynamic "backend" {
    for_each = tolist([each.value.backend])
    content {
      balancing_mode  = backend.value.balancing_mode
      group           = google_compute_region_instance_group_manager.group_manager["group_manager1"].instance_group
      capacity_scaler = backend.value.capacity_scaler
      max_utilization = backend.value.max_utilization
    }
  }

  health_checks = [google_compute_health_check.health_check["health_check1"].id]
  dynamic "log_config" {
    for_each = tolist([each.value.log_config])
    content {
      enable = log_config.value.enable
    }
  }
}

resource "google_compute_global_forwarding_rule" "google_compute_forwarding_rule" {
  name                  = var.ext_lb_name
  ip_protocol           = var.ext_lb_ip_protocol
  load_balancing_scheme = var.ext_lb_scheme
  port_range            = var.ext_lb_port_range
  target                = google_compute_target_https_proxy.target_proxy.id

  # network               = google_compute_network.vpc_network.id 
  # subnetwork            = google_compute_subnetwork.subnet[2].id
  depends_on = [
    google_compute_target_https_proxy.target_proxy,
    google_compute_network.vpc_network,
    google_compute_subnetwork.subnet
  ]
}

locals {
  timestamp_value = formatdate("YYYYMMDDhhmmss", timestamp())
  key_rotation    = 86400
  cloud_function_environmental_variables = {
    HOST     = google_sql_database_instance.postgresInstance[0].ip_address[0].ip_address
    DATABASE = google_sql_database.postgres[0].name
    PASSWORD = random_password.password.result
    PGUSER   = google_sql_user.user[0].name
    DBPORT   = 5432
  }

  secret_manager = {
    startup_script       = data.template_file.init.rendered
    kms                  = "${google_kms_key_ring.keyring.name}\n${google_kms_crypto_key.template_keys.name}"
    vm_props             = var.template_properties_cd
    webapp_template_name = "webapp-v2${local.timestamp_value}"
  }
}

resource "google_kms_key_ring" "keyring" {
  name     = "WEBAPP_KEYRING_V3_-${local.timestamp_value}"
  location = "us-east1"
}

resource "google_kms_crypto_key" "template_keys" {
  name            = "cryptokey-webapp-${local.timestamp_value}"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = "${30 * local.key_rotation}s"
}

resource "google_kms_crypto_key" "cloudsql_keys" {
  name            = "cryptokey-cloudsql-${local.timestamp_value}"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = "${30 * local.key_rotation}s"
}

resource "google_kms_crypto_key" "bucket_keys" {
  name            = "cryptokey-bucket-${local.timestamp_value}"
  key_ring        = google_kms_key_ring.keyring.id
  rotation_period = "${30 * local.key_rotation}s"
}

resource "google_kms_crypto_key_iam_binding" "vm_key_bind" {
  provider      = google-beta
  crypto_key_id = google_kms_crypto_key.template_keys.id
  # role          = "roles/owner"
  role = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  depends_on = [
    google_kms_key_ring.keyring,
    google_kms_crypto_key.template_keys
  ]
  members = ["serviceAccount:service-628977860635@compute-system.iam.gserviceaccount.com"]
}

resource "google_project_service_identity" "cloudsql_email" {
  provider = google-beta
  project  = var.project_id
  service  = "sqladmin.googleapis.com"
}

resource "google_kms_crypto_key_iam_binding" "cloudsql_key_bind" {
  provider      = google-beta
  crypto_key_id = google_kms_crypto_key.cloudsql_keys.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  depends_on = [
    google_kms_key_ring.keyring,
    google_kms_crypto_key.cloudsql_keys,
    google_project_service_identity.cloudsql_email
  ]
  members = ["serviceAccount:${google_project_service_identity.cloudsql_email.email}"]
}

resource "google_kms_crypto_key_iam_binding" "bucket_key_bind" {
  provider      = google-beta
  crypto_key_id = google_kms_crypto_key.bucket_keys.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  depends_on = [
    google_kms_key_ring.keyring,
    google_kms_crypto_key.bucket_keys,
  ]
  members = ["serviceAccount:service-628977860635@gs-project-accounts.iam.gserviceaccount.com"]
}

resource "google_secret_manager_secret" "secret-basic" {
  for_each  = local.secret_manager
  secret_id = each.key
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "secret-version-basic" {
  for_each    = local.secret_manager
  secret      = google_secret_manager_secret.secret-basic[each.key].id
  secret_data = each.value
}

data "template_file" "init" {
  template = file("${path.module}/init.sh")
  vars = {
    GCP_PROJECT_ID = var.project_id
    GCP_TOPIC      = google_pubsub_topic.topic_tf.name
    HOST           = google_sql_database_instance.postgresInstance[0].ip_address[0].ip_address
    DATABASE       = google_sql_database.postgres[0].name
    PASSWORD       = random_password.password.result
    PGUSER         = google_sql_user.user[0].name
    DBPORT         = 5432
    # could have used data in a single line
  }

  depends_on = [
    google_sql_database_instance.postgresInstance,
    google_pubsub_topic.topic_tf,
    random_password.password,
    google_sql_user.user,
    google_sql_database.postgres
  ]
}