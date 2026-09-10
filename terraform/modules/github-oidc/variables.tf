variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "github_owner" {
  description = "GitHub account or organisation that owns the portfolio repositories."
  type        = string
}

variable "pool_id" {
  description = "Workload Identity pool ID."
  type        = string
  default     = "github-actions"
}

# --- CI identity ----------------------------------------------------------------------------------

variable "ci_service_account_id" {
  description = "Account ID for the CI (plan and build) service account."
  type        = string
  default     = "github-actions-ci"
}

variable "allowed_repositories" {
  description = "Repository names, without the owner prefix, permitted to impersonate the CI account."
  type        = list(string)
  default = [
    "platform",
    "website",
    "p01-streaming",
    "p02-lakehouse",
    "p03-elt",
    "p04-orchestration",
    "p05-cdc",
    "p06-quality",
    "p07-vector",
    "p08-olap",
    "p09-features",
    "p10-governance",
  ]
}

variable "ci_roles" {
  description = <<-EOT
    Roles granted to the CI account.

    Read-only on infrastructure, write-only on the artefacts CI produces: images, and the Cloud Run
    revisions that serve them. `roles/storage.objectAdmin` is what lets `terraform plan` write the
    state lock; it cannot change infrastructure.

    Deliberately excludes owner, editor, and every *Admin role. Anything needing more belongs on the
    apply account, which is branch-restricted.
  EOT

  type = list(string)
  default = [
    "roles/viewer",
    "roles/artifactregistry.writer",
    "roles/storage.objectAdmin",
    "roles/run.developer",
    "roles/iam.serviceAccountUser",
    // Submits the image builds. This is the one identity that should hold it: the platform's rule
    // is that a *pipeline* identity must never be able to run builds as a deploy identity, and CI
    // is the deploy identity rather than a workload — granting it here is what keeps wl-p03-elt
    // read-only.
    "roles/cloudbuild.builds.editor",
  ]
}

# --- Apply identity -------------------------------------------------------------------------------

variable "apply_service_account_id" {
  description = "Account ID for the Terraform apply service account."
  type        = string
  default     = "github-actions-apply"
}

variable "apply_repositories" {
  description = <<-EOT
    Repositories permitted to impersonate the apply account. Only the platform repository holds
    Terraform configuration, so widening this list grants project repos the ability to reshape the
    platform.
  EOT

  type    = list(string)
  default = ["platform"]
}

variable "apply_branch_ref" {
  description = "Git ref the apply account may be assumed from. Must be a full ref, not a branch name."
  type        = string
  default     = "refs/heads/main"

  validation {
    condition     = startswith(var.apply_branch_ref, "refs/")
    error_message = "apply_branch_ref must be a full ref such as refs/heads/main — a bare branch name never matches the OIDC claim."
  }
}

variable "apply_roles" {
  description = <<-EOT
    Roles granted to the apply account. Pass the iam module's `deployer_roles` output: CI applying
    the configuration needs exactly the authority a human applying it needs, and defining the list
    twice guarantees they drift.
  EOT

  type = list(string)
}
