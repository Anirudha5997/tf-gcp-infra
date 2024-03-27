variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "vpc" {
  type = map(object({
    vpc_name            = string
    auto_create_subnets = bool
    route_mode          = string
    del_default_routes  = bool

    subnets = map(object({
      subnet_name = string
      cidr_range  = string
    }))

    vpc_connector = object({
      name          = string
      ip_cidr_range = string
      machine_type  = string
      min_instances = number
      max_instances = number
    })

    routes = map(object({
      route_name        = string
      destination_range = string
      next_hop_gateway  = string
    }))

    firewalls = map(object({
      firewall_name = string
      source_ranges = optional(list(string), [])

      allow = optional(list(object({
        protocol = string
        ports    = optional(list(string), [])
      })), [])

      deny = optional(list(object({
        protocol = string
        ports    = optional(list(string), [])
      })), [])
      source_tags = list(string)
    }))

    private_ip_alloc = object({
      name          = optional(string, "private-ip-alloc")
      address_type  = optional(string, "INTERNAL")
      purpose       = optional(string, "VPC_PEERING")
      prefix_length = optional(number, 24)

      vpc_connector_peering_routes = object({
        import_custom_routes = bool
        export_custom_routes = bool
      })
    })

    databaseInstance = object({
      name                = string
      database_version    = string
      deletion_protection = optional(bool, false)

      settings = object({
        tier              = string
        edition           = optional(string, "ENTERPRISE")
        disk_size         = optional(number, 100)
        disk_type         = optional(string, "PD_SSD")
        availability_type = optional(string, "REGIONAL")

        ip_configuration = object({
          ipv4_enabled = optional(bool, false)
          # private_network = string
          # allocated_ip_range = string
          enable_private_path_for_google_cloud_services = optional(bool, false)
        })

        backup_configuration = object({
          enabled                        = optional(bool, true)
          point_in_time_recovery_enabled = optional(bool, true)
        })
      })

      database = object({
        name = optional(string, "webapp")
      })

      user = object({
        name = optional(string, "webapp")
      })
    })
  }))
}

variable "vm-properties" {
  description = "Configurations for VMs"
  type = map(object({
    name                = string
    machine_type        = string
    zone                = string
    can_ip_forward      = bool
    deletion_protection = bool
    enable_display      = bool
    tags                = list(string)

    boot_disk = object({
      auto_delete = bool
      device_name = string
      mode        = string

      initialize_params = object({
        image = string
        size  = number
        type  = string
      })
    })

    labels = object({
      goog-ec-src = string
    })


    network_interface = map(object({
      access_config = object({
        network_tier = string
      })
      queue_count = number
      stack_type  = string
      subnetwork  = string
    }))

    scheduling = map(object({
      automatic_restart   = bool
      on_host_maintenance = string
      preemptible         = bool
      provisioning_model  = string
    }))

    service_account = map(object({
      email                = string
      service_account_name = string
      scopes               = list(string)
    }))

    shielded_instance_config = map(object({
      enable_integrity_monitoring = bool
      enable_secure_boot          = bool
      enable_vtpm                 = bool
    }))

    cloud_dns_properties = map(object({
      type            = string
      dns_record_name = optional(string, "")
      ttl             = number
      rrdatas         = optional(list(string), [])
    }))

  }))
}

variable "manage_zone_name" {
  type = string
}

variable "service_accounts_properties" {
  type = map(object({
    account_id                   = string
    display_name                 = string
    create_ignore_already_exists = bool
    iam_binding_roles            = list(string)
  }))
}

variable "cloud_bucket_name" {
  type = string
}

variable "archive_name" {
  type = string
}

variable "pubsub_topic_name" {
  type = string
}

variable "pubsub_pull_subscription" {
  type = map(object({
    name                       = string
    message_retention_duration = string
    retain_acked_messages      = bool
    ack_deadline_seconds       = optional(number, 120)
    enable_message_ordering    = bool
  }))
}

variable "cloud_function_properties" {
  type = map(object({
    name        = string
    location    = string
    description = string

    build_config = object({
      runtime     = string
      entry_point = string
    })

    service_config = object({
      max_instance_count = number
      min_instance_count = number
      available_memory   = string
      timeout_seconds    = number

      environment_variables = map(string)

      ingress_settings               = string
      all_traffic_on_latest_revision = bool
      service_account_email          = string
      vpc_connector_egress_settings  = string
      vpc_connector                  = number
    })

    event_trigger = object({
      trigger_region = string
      event_type     = string
      retry_policy   = string
    })
  }))
}
