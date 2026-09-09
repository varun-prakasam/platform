output "network_id" {
  description = "Self link of the VPC network."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Name of the VPC network."
  value       = google_compute_network.this.name
}

output "subnet_id" {
  description = "Self link of the node subnet."
  value       = google_compute_subnetwork.this.id
}

output "subnet_name" {
  description = "Name of the node subnet."
  value       = google_compute_subnetwork.this.name
}

output "pods_range_name" {
  description = "Secondary range name for pods, consumed by the GKE module."
  value       = var.pods_range_name
}

output "services_range_name" {
  description = "Secondary range name for services, consumed by the GKE module."
  value       = var.services_range_name
}

output "node_tag" {
  description = "Network tag that GKE nodes must carry for the firewall rules to apply."
  value       = var.node_tag
}
