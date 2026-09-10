// Every identity on the platform, in one place.
//
// This file is the answer to "what can touch what". Service accounts were previously spread across
// the gke and github-oidc modules, which meant that question had several answers. It has one now.
//
// Three planes, deliberately separate:
//
//   provisioning  the deployer, which creates infrastructure
//   ci            two GitHub Actions identities, split by branch (see github-oidc)
//   runtime       one account per workload, per surface (GKE and Cloud Run)
//
// Runtime accounts are split by surface rather than shared per project. Project 3's dbt job writes
// to BigQuery; project 3's API only reads. Giving the API the writer's account would grant a
// public-facing service write access to the warehouse for no reason.

locals {
  // Roles the deployer needs at project scope. Editor is insufficient: it cannot grant IAM roles
  // or administer Workload Identity pools, both of which this configuration does.
  //
  // roles/billing.costsManager is also required, but at billing-account scope rather than project
  // scope, so it is granted separately by `make grant-deployer`.
  deployer_roles = [
    "roles/serviceusage.serviceUsageAdmin",
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/container.admin",
    "roles/storage.admin",
    "roles/bigquery.admin",
    "roles/artifactregistry.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/pubsub.admin",
    "roles/monitoring.notificationChannelEditor",
    // Alerting needs all three: a channel to send to, a policy to evaluate, and a log-based metric
    // for the policy to evaluate against. The channel role alone lets Terraform create somewhere to
    // send alerts and nothing that would ever send one.
    "roles/monitoring.alertPolicyEditor",
    "roles/logging.configWriter",
    "roles/dataplex.admin",
    "roles/aiplatform.admin",
    "roles/run.admin",
    "roles/dataflow.admin",
    "roles/iam.serviceAccountUser",
  ]

  // Flattened role bindings for the GKE runtime accounts.
  gke_role_bindings = merge([
    for name, wl in var.gke_workloads : {
      for role in wl.roles : "${name}::${role}" => { name = name, role = role }
    }
  ]...)

  // Flattened role bindings for the Cloud Run runtime accounts.
  run_role_bindings = merge([
    for name, svc in var.cloud_run_services : {
      for role in svc.roles : "${name}::${role}" => { name = name, role = role }
    }
  ]...)
}

# =================================================================================================
# Provisioning plane
# =================================================================================================

// The deployer is an account you already own, not one created here — Terraform cannot create the
// identity it authenticates as. `make grant-deployer` performs the initial grant via gcloud; these
// resources then manage the same bindings declaratively so they cannot drift or be revoked by
// accident.
resource "google_project_iam_member" "deployer" {
  for_each = var.deployer_service_account_email == null ? [] : toset(local.deployer_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${var.deployer_service_account_email}"
}

# =================================================================================================
# Runtime plane — GKE workloads
# =================================================================================================

resource "google_service_account" "gke" {
  for_each = var.gke_workloads

  project      = var.project_id
  account_id   = "wl-${each.key}"
  display_name = "Runtime (GKE): ${each.key}"
  description  = "Bound to ${each.value.namespace}/${each.value.ksa_name} via Workload Identity"
}

resource "google_project_iam_member" "gke" {
  for_each = local.gke_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.gke[each.value.name].email}"
}

// Completes the Workload Identity binding. The Kubernetes service account must carry the matching
// annotation, which is emitted as a Terraform output so project repos do not hardcode it.
resource "google_service_account_iam_member" "gke_workload_identity" {
  for_each = var.gke_workloads

  service_account_id = google_service_account.gke[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.namespace}/${each.value.ksa_name}]"
}

# =================================================================================================
# Runtime plane — Cloud Run services
# =================================================================================================

resource "google_service_account" "cloud_run" {
  for_each = var.cloud_run_services

  project      = var.project_id
  account_id   = "api-${each.key}"
  display_name = "Runtime (Cloud Run): ${each.key}"
  description  = "Attached to the ${each.key} API service"
}

resource "google_project_iam_member" "cloud_run" {
  for_each = local.run_role_bindings

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.cloud_run[each.value.name].email}"
}

# =================================================================================================
# Runtime plane — Dataflow
# =================================================================================================

// Project 5 runs the same Beam pipeline on two runners. The Flink runner uses the p05 GKE account;
// Dataflow workers need their own, because Dataflow attaches it to worker VMs rather than pods.
resource "google_service_account" "dataflow_worker" {
  project      = var.project_id
  account_id   = "dataflow-worker"
  display_name = "Runtime: Dataflow workers"
  description  = "Attached to Dataflow worker VMs for the project 5 runner comparison"
}

resource "google_project_iam_member" "dataflow_worker" {
  for_each = toset([
    "roles/dataflow.worker",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/storage.objectAdmin",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dataflow_worker.email}"
}

// Whoever launches a Dataflow job must be able to act as the worker account.
resource "google_service_account_iam_member" "dataflow_worker_user" {
  for_each = toset(compact([
    var.deployer_service_account_email,
    google_service_account.gke["p05-cdc"].email,
  ]))

  service_account_id = google_service_account.dataflow_worker.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${each.value}"
}
