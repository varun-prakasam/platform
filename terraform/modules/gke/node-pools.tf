// Two pools with different reliability guarantees, because the workloads have different needs.
//
//   base   on-demand, always at least one node. Hosts the always-on stateful engines whose
//          downtime would show up as a red dashboard on the public portfolio.
//
//   batch  Spot, scales from zero. Hosts Spark jobs, which are retry-safe and idle most of the
//          day. There is no uptime argument for paying on-demand prices for these, and running
//          them on preemptible capacity is the honest production choice.

resource "google_container_node_pool" "base" {
  project  = var.project_id
  name     = "base"
  cluster  = google_container_cluster.this.name
  location = var.zone

  initial_node_count = var.base_node_min_count

  autoscaling {
    min_node_count = var.base_node_min_count
    max_node_count = var.base_node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.base_node_machine_type
    disk_size_gb = var.base_node_disk_size_gb
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags   = [var.node_tag]
    labels = merge(var.labels, { pool = "base", workload_class = "stateful" })

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    // Node count drifts with the autoscaler; only the bounds are managed here.
    ignore_changes = [initial_node_count]
  }
}

resource "google_container_node_pool" "batch" {
  project  = var.project_id
  name     = "batch-spot"
  cluster  = google_container_cluster.this.name
  location = var.zone

  initial_node_count = 0

  autoscaling {
    min_node_count = 0
    max_node_count = var.batch_node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.batch_node_machine_type
    disk_size_gb = var.batch_node_disk_size_gb
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"
    spot         = true

    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags   = [var.node_tag]
    labels = merge(var.labels, { pool = "batch", workload_class = "batch" })

    // Nothing lands here unless it explicitly tolerates preemption. Stateful services must never
    // be scheduled onto Spot capacity by accident.
    taint {
      key    = "workload-class"
      value  = "batch"
      effect = "NO_SCHEDULE"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}
