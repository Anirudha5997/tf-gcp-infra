resource "google_compute_network" "vpc_network" {
  project = "proud-stage-414320"
  name = "vpc-network"
  auto_create_subnetworks = false
  routing_mode = "REGIONAL"
  delete_default_routes_on_create = true
  mtu = 1460
}


resource "google_compute_subnetwork" "webapp" {
  name          = "webapp"
  ip_cidr_range = "10.0.0.0/24"
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "db" {
  name          = "db"
  ip_cidr_range = "10.1.0.0/24"
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_route" "route" {
  name        = "route"
  dest_range  = "0.0.0.0/0"
  network     = google_compute_network.vpc_network.name
  next_hop_gateway = "default-internet-gateway"
}


