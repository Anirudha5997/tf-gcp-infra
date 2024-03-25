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

    private_ip_alloc = optional(object({
      name          = optional(string, "private-ip-alloc")
      address_type  = optional(string, "INTERNAL")
      purpose       = optional(string, "VPC_PEERING")
      prefix_length = optional(number, 24)
    }), {})

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
      email  = string
      scopes = list(string)
    }))

    shielded_instance_config = map(object({
      enable_integrity_monitoring = bool
      enable_secure_boot          = bool
      enable_vtpm                 = bool
    }))

    cloud_dns_properties = map(object({
      type = string
      dns_record_name = optional(string, "")
      ttl  = number
      rrdatas = optional(list(string), [])
    }))

  }))
}

variable "manage_zone_name" {
  type = string
}

variable "account_id" {
  type = string
}

variable "display_name" {
  type = string
}

variable "create_ignore_already_exists" {
  type = bool
}

variable "iam_binding_roles" {
  type = list(string)
}