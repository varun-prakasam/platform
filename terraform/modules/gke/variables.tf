variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "zone" {
  description = "Zone for the cluster. Zonal, not regional — see the note in main.tf."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name."
  type        = string
  default     = "data-platform"
}

variable "network_id" {
  description = "VPC network self link."
  type        = string
}

variable "subnet_id" {
  description = "Subnet self link."
  type        = string
}

variable "pods_range_name" {
  description = "Secondary range name for pods."
  type        = string
}

variable "services_range_name" {
  description = "Secondary range name for services."
  type        = string
}

variable "master_cidr" {
  description = "CIDR for the control plane. Must not overlap any subnet range."
  type        = string
  default     = "172.16.0.0/28"
}

variable "node_tag" {
  description = "Network tag applied to nodes so the VPC firewall rules match."
  type        = string
}

variable "authorized_networks" {
  description = <<-EOT
    CIDRs permitted to reach the public control plane endpoint.

    Set this to your own IP. Leaving it as 0.0.0.0/0 exposes the API server to the internet — it
    still requires authentication, but it is needless attack surface.
  EOT

  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR or STABLE."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE."
  }
}

variable "deletion_protection" {
  description = "Block `terraform destroy` on the cluster. Leave enabled unless you are actively tearing the platform down."
  type        = bool
  default     = true
}

# --- Base node pool (on-demand, always-on) --------------------------------------------------------

variable "base_node_machine_type" {
  description = <<-EOT
    Machine type for the always-on pool. This is the single largest cost lever on the platform.

    The stateful engines request roughly 20 GiB of memory in total and are CPU-idle most of the
    time, so a high-memory type is the efficient shape. e2-highmem-4 (4 vCPU, 32 GiB) fits the full
    ten-project build-out with headroom, at roughly $130/month.

    While fewer projects are deployed, e2-standard-2 or e2-highmem-2 is sufficient and much cheaper.
  EOT

  type    = string
  default = "e2-highmem-4"
}

variable "base_node_min_count" {
  description = "Minimum nodes in the always-on pool."
  type        = number
  default     = 1
}

variable "base_node_max_count" {
  description = "Maximum nodes in the always-on pool. Headroom for rolling upgrades and pod rescheduling."
  type        = number
  default     = 2
}

variable "base_node_disk_size_gb" {
  description = "Boot disk size for base nodes."
  type        = number
  default     = 100
}

# --- Batch node pool (Spot, scales from zero) -----------------------------------------------------

variable "batch_node_machine_type" {
  description = "Machine type for the Spot batch pool that runs Spark."
  type        = string
  default     = "e2-standard-4"
}

variable "batch_node_max_count" {
  description = "Maximum nodes in the batch pool. Scales back to zero when no jobs are running."
  type        = number
  default     = 2
}

variable "batch_node_disk_size_gb" {
  description = "Boot disk size for batch nodes. Spark shuffle spills here, so it needs headroom."
  type        = number
  default     = 200
}

# --- Maintenance ----------------------------------------------------------------------------------

variable "maintenance_start_time" {
  description = "RFC3339 start of the weekly maintenance window."
  type        = string
  default     = "2025-01-04T03:00:00Z"
}

variable "maintenance_end_time" {
  description = "RFC3339 end of the weekly maintenance window."
  type        = string
  default     = "2025-01-04T11:00:00Z"
}

variable "labels" {
  description = "Labels applied to the cluster and nodes."
  type        = map(string)
  default     = {}
}
