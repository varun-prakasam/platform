output "workload_identity_provider" {
  description = "Full provider resource name. Set as the WIF_PROVIDER repository variable in GitHub."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_service_account_email" {
  description = "Plan and build identity, assumable from any branch."
  value       = google_service_account.ci.email
}

output "apply_service_account_email" {
  description = "Terraform apply identity, assumable only from the platform repo's main branch."
  value       = google_service_account.apply.email
}

output "github_setup" {
  description = "Repository variables to configure in GitHub."
  value       = <<-EOT
    Set these as repository (or organisation) variables in GitHub. They are identifiers rather than
    secrets, so Variables is correct here, not Secrets:

      WIF_PROVIDER            = ${google_iam_workload_identity_pool_provider.github.name}
      WIF_SERVICE_ACCOUNT     = ${google_service_account.ci.email}
      GCP_PROJECT_ID          = ${var.project_id}

    Platform repository only — used by the apply job:

      WIF_APPLY_ACCOUNT       = ${google_service_account.apply.email}

    The apply account is only assumable from ${var.apply_branch_ref}. Requesting it from a pull
    request fails at token exchange, not at a workflow condition.
  EOT
}
