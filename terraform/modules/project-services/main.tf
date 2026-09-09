// Enables every Google Cloud API the platform and its ten projects depend on.
//
// disable_on_destroy is false throughout: disabling an API on teardown can orphan resources in
// other configurations that share the project, and is almost never what you want.

locals {
  services = [
    // Core
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",

    // Kubernetes and images
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "containersecurity.googleapis.com",

    // Storage and warehouse
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "bigquerystorage.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "biglake.googleapis.com",

    // Processing
    "dataflow.googleapis.com",
    "dataproc.googleapis.com",
    "datastream.googleapis.com",
    "pubsub.googleapis.com",

    // Serving
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "secretmanager.googleapis.com",
    "iap.googleapis.com",
    "certificatemanager.googleapis.com",

    // AI / ML
    "aiplatform.googleapis.com",

    // Governance
    "dataplex.googleapis.com",
    "dlp.googleapis.com",
    "datacatalog.googleapis.com",

    // Observability and cost
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudtrace.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudbilling.googleapis.com",
  ]
}

resource "google_project_service" "this" {
  for_each = toset(local.services)

  project = var.project_id
  service = each.value

  disable_on_destroy         = false
  disable_dependent_services = false
}
