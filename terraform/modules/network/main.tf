// VPC for the platform. Nodes are private (no external IPs), so all egress — image pulls and the
// public data source APIs every project reads from — flows through Cloud NAT.

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Data platform VPC"
}

resource "google_compute_subnetwork" "this" {
  project       = var.project_id
  name          = "${var.network_name}-subnet"
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr

  // Required for private nodes to reach Google APIs without an external IP.
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = var.pods_range_name
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = var.services_range_name
    ip_cidr_range = var.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.1
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "this" {
  project = var.project_id
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project = var.project_id
  name    = "${var.network_name}-nat"
  router  = google_compute_router.this.name
  region  = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

// --- Firewall ----------------------------------------------------------------------------------

resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${var.network_name}-allow-internal"
  network = google_compute_network.this.name

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
}

// A private cluster's control plane may only reach nodes on 443 and 10250 by default. Several of
// the operators this platform runs (Flink, StarRocks, Strimzi, CloudNativePG) expose admission and
// conversion webhooks on other ports; without this rule their installs hang on webhook timeouts.
resource "google_compute_firewall" "allow_master_webhooks" {
  project     = var.project_id
  name        = "${var.network_name}-allow-master-webhooks"
  network     = google_compute_network.this.name
  description = "Control plane to node admission/conversion webhooks"

  source_ranges = [var.master_cidr]
  target_tags   = [var.node_tag]

  allow {
    protocol = "tcp"
    ports    = ["8443", "9443", "9440", "6443", "15017"]
  }
}

// Google Cloud Load Balancer health check ranges, for any Gateway/Ingress fronted service.
resource "google_compute_firewall" "allow_health_checks" {
  project     = var.project_id
  name        = "${var.network_name}-allow-health-checks"
  network     = google_compute_network.this.name
  description = "Google load balancer health check probes"

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = [var.node_tag]

  allow {
    protocol = "tcp"
  }
}
