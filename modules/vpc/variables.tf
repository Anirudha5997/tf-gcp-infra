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

      allow = list(object({
        protocol = string
        ports = list(string)
      }))
      
      source_tags = list(string)
    }))
  }))
}


variable "service_account" {
  type = object({
    account_id = string
    display_name = string
  })
}

variable "vm-properties" {
  description = "Configuration(s) for VMs"
  type = map(object({
    name                = string
    machine_type        = string
    zone                = string
    can_ip_forward      = bool


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

    network_interface = map(object({
      queue_count = number
      stack_type  = string
      subnetwork  = string

      access_config = object({
        network_tier = string
      })
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


