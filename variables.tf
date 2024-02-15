variable "vpc" {
    type = map(object({
            project_name = string
            project_id = string
            auto_create_subnets = bool
            route_mode = string
            del_default_routes = bool

            subnets = map(object({
                subnet_name = string
                cidr_range = string
            }))

            routes = map(object({
                route_name = string
                destination_range = string
                next_hop_gateway = string
            }))
    }))
}
