variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "deployer_service_account_email" {
  description = <<-EOT
    Service account Terraform authenticates as.

    This account is not created here — Terraform cannot create the identity it runs as. Grant the
    initial roles with `make grant-deployer`, then these bindings keep them managed declaratively.

    Null skips the deployer grants entirely, which is correct when applying as an owner user.
  EOT

  type    = string
  default = null
}

variable "gke_workloads" {
  description = <<-EOT
    Runtime identities for in-cluster workloads, bound to Kubernetes service accounts via Workload
    Identity.

    `namespace` and `ksa_name` must match what the project's manifests create. The KSA needs:

      annotations:
        iam.gke.io/gcp-service-account: wl-<key>@<project_id>.iam.gserviceaccount.com
  EOT

  type = map(object({
    namespace = string
    ksa_name  = string
    roles     = list(string)
  }))

  default = {
    "p01-streaming" = {
      namespace = "p01-streaming"
      ksa_name  = "flink"
      roles     = ["roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/storage.objectAdmin"]
    }
    "p02-lakehouse" = {
      namespace = "p02-lakehouse"
      ksa_name  = "spark"
      roles     = ["roles/storage.objectAdmin", "roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/biglake.admin"]
    }
    "p03-elt" = {
      namespace = "p03-elt"
      ksa_name  = "dbt"
      roles     = ["roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/storage.objectAdmin"]
    }
    "p04-orchestration" = {
      namespace = "p04-orchestration"
      ksa_name  = "airflow"
      roles     = ["roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/storage.objectAdmin", "roles/dataflow.developer"]
    }
    "p05-cdc" = {
      namespace = "p05-cdc"
      ksa_name  = "beam"
      roles     = ["roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/storage.objectAdmin", "roles/dataflow.developer"]
    }
    "p06-quality" = {
      namespace = "p06-quality"
      ksa_name  = "quality"
      roles     = ["roles/bigquery.dataViewer", "roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/storage.objectAdmin"]
    }
    "p07-vector" = {
      namespace = "p07-vector"
      ksa_name  = "vector"
      roles     = ["roles/aiplatform.user", "roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/storage.objectAdmin"]
    }
    "p08-olap" = {
      namespace = "p08-olap"
      ksa_name  = "starrocks"
      roles     = ["roles/storage.objectAdmin", "roles/bigquery.dataViewer", "roles/bigquery.jobUser"]
    }
    "p09-features" = {
      namespace = "p09-features"
      ksa_name  = "feast"
      roles     = ["roles/bigquery.dataEditor", "roles/bigquery.jobUser", "roles/datastore.user", "roles/aiplatform.user"]
    }
    "p10-governance" = {
      namespace = "p10-governance"
      ksa_name  = "governance"
      roles     = ["roles/dataplex.editor", "roles/dlp.user", "roles/bigquery.metadataViewer", "roles/bigquery.jobUser"]
    }
  }
}

variable "cloud_run_services" {
  description = <<-EOT
    Runtime identities for the public-facing APIs.

    Read-only by design. These services are exposed to the internet, so none of them holds write
    access to the warehouse — the pipelines write, the APIs read. Project 5 is the single
    deliberate exception, and its write path targets an isolated synthetic database rather than
    anything in BigQuery.
  EOT

  type = map(object({
    roles = list(string)
  }))

  default = {
    "p01-streaming"     = { roles = ["roles/bigquery.dataViewer", "roles/bigquery.jobUser"] }
    "p02-lakehouse"     = { roles = ["roles/bigquery.dataViewer", "roles/bigquery.jobUser", "roles/storage.objectViewer"] }
    "p03-elt"           = { roles = ["roles/bigquery.dataViewer", "roles/bigquery.jobUser"] }
    "p04-orchestration" = { roles = ["roles/bigquery.dataViewer", "roles/bigquery.jobUser"] }
    "p05-cdc"           = { roles = ["roles/bigquery.dataViewer", "roles/bigquery.jobUser"] }
    "p06-quality"       = { roles = ["roles/bigquery.dataViewer", "roles/bigquery.jobUser", "roles/storage.objectViewer"] }
    // Embeds the user's query at search time, so it needs Vertex AI at request scope.
    "p07-vector"   = { roles = ["roles/aiplatform.user", "roles/bigquery.dataViewer", "roles/bigquery.jobUser"] }
    "p08-olap"     = { roles = ["roles/bigquery.dataViewer", "roles/bigquery.jobUser"] }
    "p09-features" = { roles = ["roles/datastore.viewer", "roles/bigquery.dataViewer", "roles/bigquery.jobUser"] }
    "p10-governance" = {
      roles = ["roles/dataplex.viewer", "roles/bigquery.metadataViewer", "roles/bigquery.dataViewer", "roles/bigquery.jobUser"]
    }
    // The portfolio hub itself: reads the cost views and the per-project health feed.
    "hub" = { roles = ["roles/bigquery.dataViewer", "roles/bigquery.jobUser"] }
  }
}
