output "cluster_name" {
  description = "GKE cluster name."
  value       = module.gke.cluster_name
}

output "kubectl_setup" {
  description = "Command to point kubectl at the cluster."
  value       = module.gke.get_credentials_command
}

output "gke_ksa_annotations" {
  description = "Annotations each project must apply to its Kubernetes service account to complete Workload Identity binding."
  value       = module.iam.gke_ksa_annotations
}

output "cloud_run_service_accounts" {
  description = "Service account each project must attach to its Cloud Run API service."
  value       = module.iam.cloud_run_service_accounts
}

output "deployer_roles" {
  description = "Project-scoped roles the deployer holds. Read by `make grant-deployer`."
  value       = module.iam.deployer_roles
}

output "dataflow_worker_service_account" {
  description = "Service account to pass as --serviceAccount when launching Dataflow jobs."
  value       = module.iam.dataflow_worker_service_account
}

output "buckets" {
  description = "GCS buckets available to the projects."
  value       = module.storage.bucket_urls
}

output "datasets_by_project" {
  description = "BigQuery datasets grouped by owning project."
  value       = module.bigquery.datasets_by_project
}

output "image_registry" {
  description = "Base URL for container images."
  value       = module.artifact_registry.repository_url
}

output "budget_topic" {
  description = "Pub/Sub topic receiving budget notifications."
  value       = module.billing.budget_topic
}

output "github_actions_setup" {
  description = "Repository variables to configure in GitHub for keyless CI auth. Null until github_owner is set."
  value       = var.github_owner == null ? null : module.github_oidc[0].github_setup
}

output "next_steps" {
  description = "What to do after the first successful apply."
  value       = <<-EOT

    1. Point kubectl at the cluster:
         ${module.gke.get_credentials_command}

    2. Install ArgoCD and the root application:
         make argocd

    3. Enable the Cloud Billing export to BigQuery. This cannot be done from Terraform:
         Console -> Billing -> Billing export -> BigQuery export -> Edit settings
         Project: ${var.project_id}
         Dataset: platform_billing

       Wait up to 24 hours for the first partition, read the generated table name off the dataset,
       then set billing_export_table and create_cost_views = true and re-apply.

    4. Deploy the first project. Build order is platform -> p03-elt -> p01-streaming -> the rest.

  EOT
}
