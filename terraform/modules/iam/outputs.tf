output "gke_service_accounts" {
  description = "Map of workload name to the Google service account email bound to its Kubernetes service account."
  value       = { for k, sa in google_service_account.gke : k => sa.email }
}

output "gke_ksa_annotations" {
  description = <<-EOT
    Annotation each project must place on its Kubernetes service account to complete the Workload
    Identity binding, keyed by namespace/name. Emitted so project repos never hardcode the project
    ID.
  EOT
  value = {
    for k, wl in var.gke_workloads :
    "${wl.namespace}/${wl.ksa_name}" => {
      "iam.gke.io/gcp-service-account" = google_service_account.gke[k].email
    }
  }
}

output "cloud_run_service_accounts" {
  description = "Map of service name to the service account to attach to that Cloud Run service."
  value       = { for k, sa in google_service_account.cloud_run : k => sa.email }
}

output "dataflow_worker_service_account" {
  description = "Service account attached to Dataflow worker VMs."
  value       = google_service_account.dataflow_worker.email
}

output "deployer_roles" {
  description = "Project-scoped roles the deployer holds. Mirrors what `make grant-deployer` applies."
  value       = local.deployer_roles
}
