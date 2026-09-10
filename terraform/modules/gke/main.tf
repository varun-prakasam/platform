// Zonal GKE Standard cluster hosting every stateful engine on the platform.
//
// Zonal rather than regional: the GKE free tier covers the control plane fee for exactly one
// zonal cluster, and a regional cluster would multiply both control plane and node cost for
// availability guarantees a portfolio does not need. The trade-off is a control plane outage
// during zone maintenance, which is acceptable here and documented in docs/cost.md.

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE node pool identity for ${var.cluster_name}"
  description  = "Least-privilege identity for cluster nodes. Workloads use Workload Identity instead of this account."
}

// Node identity is deliberately minimal. Anything a workload needs comes through Workload
// Identity, not the node service account, so a compromised pod cannot inherit node permissions.
resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.zone

  // Node pools are managed as separate resources so they can be replaced without recreating the
  // cluster. The default pool exists only long enough for the cluster to come up.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  network    = var.network_id
  subnetwork = var.subnet_id

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr

    master_global_access_config {
      enabled = false
    }
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  // GKE has not issued client certificates by default since 1.12, so this changes nothing today.
  // Stated anyway: a client certificate is a credential that cannot be rotated or revoked without
  // recreating the cluster, and "off because the default happens to be off" is not a control.
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  release_channel {
    channel = var.release_channel
  }

  // Pod identity without service account keys. Nothing in this platform downloads a key.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  // Breaks down cluster spend by namespace and label in the billing export, which is what lets
  // the portfolio hub attribute cost to individual projects rather than to "GKE".
  cost_management_config {
    enabled = true
  }

  monitoring_config {
    // Order matters. The provider compares this as an ordered list but the API returns its own
    // canonical order, so any other ordering yields a permanent no-op diff on every plan.
    enable_components = [
      "SYSTEM_COMPONENTS",
      "HPA",
      "POD",
      "DAEMONSET",
      "DEPLOYMENT",
      "STATEFULSET",
      "CADVISOR",
      "KUBELET",
    ]
    managed_prometheus {
      enabled = true
    }
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    // Lets Spark and Flink pods mount GCS buckets directly, avoiding a copy step for Iceberg
    // metadata and checkpoint access.
    gcs_fuse_csi_driver_config {
      enabled = true
    }
  }

  vertical_pod_autoscaling {
    enabled = true
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  // Dataplane V2. Required for network policy enforcement between project namespaces.
  datapath_provider = "ADVANCED_DATAPATH"

  security_posture_config {
    mode               = "BASIC"
    vulnerability_mode = "VULNERABILITY_BASIC"
  }

  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  resource_labels = var.labels

  lifecycle {
    ignore_changes = [
      // The provider re-reads a default pool that no longer exists.
      initial_node_count,
    ]
  }
}
