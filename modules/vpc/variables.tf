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
  }))
}