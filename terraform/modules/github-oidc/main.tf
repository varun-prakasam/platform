// Lets GitHub Actions authenticate to GCP by exchanging its OIDC token for short-lived Google
// credentials. No service account key is ever created, stored in a repository secret, or rotated.
//
// Two identities, not one:
//
//   ci     builds images, deploys Cloud Run, runs `terraform plan`. Assumable from any branch of
//          any listed repository, because plans run on pull requests.
//   apply  runs `terraform apply`. Assumable only from refs/heads/main of the platform repository.
//
// The split matters because apply needs roles broad enough to delete the platform, and a pull
// request can modify workflow YAML. A workflow `if:` condition is therefore not a security control
// — the attacker writes the condition. The branch restriction is enforced in the IAM binding
// instead, via a composite repository@ref attribute the token issuer controls and the pull request
// cannot forge.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = "GitHub Actions"
  description               = "OIDC federation for the portfolio repositories"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub"

  attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.repository"     = "assertion.repository"
    "attribute.owner"          = "assertion.repository_owner"
    "attribute.ref"            = "assertion.ref"
    "attribute.repository_ref" = "assertion.repository + '@' + assertion.ref"
  }

  // Restricts the pool to a single GitHub account. Anything else is rejected at token exchange.
  // Without this, any GitHub repository on the internet could exchange a token against this pool.
  attribute_condition = "assertion.repository_owner == '${var.github_owner}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# =================================================================================================
# CI identity — build, push, deploy, plan
# =================================================================================================

resource "google_service_account" "ci" {
  project      = var.project_id
  account_id   = var.ci_service_account_id
  display_name = "GitHub Actions CI (plan and build)"
  description  = "Impersonated by GitHub Actions on any branch. Cannot apply Terraform."
}

// Only the listed repositories may impersonate the CI account. Any branch, because plans and image
// builds run on pull requests.
resource "google_service_account_iam_member" "ci_impersonation" {
  for_each = toset(var.allowed_repositories)

  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${each.value}"
}

resource "google_project_iam_member" "ci" {
  for_each = toset(var.ci_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci.email}"
}

# =================================================================================================
# Apply identity — main branch of the platform repository only
# =================================================================================================

resource "google_service_account" "apply" {
  project      = var.project_id
  account_id   = var.apply_service_account_id
  display_name = "GitHub Actions apply"
  description  = "Runs terraform apply. Assumable only from refs/heads/main of the platform repo."
}

// The composite attribute is the whole point: `repo@refs/heads/main` cannot be produced by a token
// minted on a pull request, whose ref is refs/pull/<n>/merge.
resource "google_service_account_iam_member" "apply_impersonation" {
  for_each = toset(var.apply_repositories)

  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_ref/${var.github_owner}/${each.value}@${var.apply_branch_ref}"
}

// Mirrors the deployer's roles — applying the configuration requires the same authority as running
// it locally. Passed in from the iam module rather than duplicated, so the two cannot diverge.
resource "google_project_iam_member" "apply" {
  for_each = toset(var.apply_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.apply.email}"
}
