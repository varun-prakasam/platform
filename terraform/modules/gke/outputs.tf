output "cluster_name" {
  description = "Cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "Control plane endpoint."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate, base64 encoded."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_pool" {
  description = "Workload Identity pool for the cluster."
  value       = google_container_cluster.this.workload_identity_config[0].workload_pool
}

output "node_service_account" {
  description = "Email of the node service account."
  value       = google_service_account.nodes.email
}

output "get_credentials_command" {
  description = "Command to configure kubectl against this cluster."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --zone ${var.zone} --project ${var.project_id}"
}
