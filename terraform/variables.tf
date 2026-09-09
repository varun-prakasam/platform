variable "project_id" {
  description = "GCP project ID hosting the entire platform."
  type        = string
}

variable "region" {
  description = <<-EOT
    Region for all regional resources.

    Keep BigQuery, GCS and GKE in the same region. BigLake external tables over Iceberg require the
    dataset and bucket to be colocated, and cross-region reads add egress charges to every query.
  EOT

  type    = string
  default = "us-central1"
}

variable "zone" {
  description = "Zone for the GKE cluster. Must be inside var.region."
  type        = string
  default     = "us-central1-a"
}

variable "billing_account_id" {
  description = "Billing account ID in the form XXXXXX-XXXXXX-XXXXXX, used to create the budget."
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget ceiling in whole units of var.currency_code."
  type        = number
  default     = 250
}

variable "currency_code" {
  description = <<-EOT
    Budget currency. Must equal the billing account's own currency, which is fixed when the account
    is created and cannot be changed. A mismatch fails the apply with a bare INVALID_ARGUMENT and no
    field detail, so read it off the account rather than assuming:

      gcloud billing accounts describe <billing_account_id> --format='value(currencyCode)'
  EOT

  type    = string
  default = "USD"
}

variable "alert_email" {
  description = "Email address that receives budget alerts."
  type        = string
  default     = null
}

variable "deployer_service_account_email" {
  description = <<-EOT
    Service account Terraform authenticates as, in the form
    <name>@<project_id>.iam.gserviceaccount.com.

    Terraform cannot create the identity it runs as, so this account must already exist and already
    hold the roles before the first apply. `make grant-deployer` performs that initial grant; setting
    this variable then brings the same bindings under Terraform management so they cannot silently
    drift.

    Leave null if you apply as an owner user rather than a service account.
  EOT

  type    = string
  default = null
}

variable "authorized_networks" {
  description = <<-EOT
    CIDRs allowed to reach the GKE control plane. Set this to your own public IP:

      authorized_networks = [{ cidr_block = "203.0.113.42/32", display_name = "home" }]

    Add your CI runner's egress range too if CI needs cluster access.
  EOT

  type = list(object({
    cidr_block   = string
    display_name = string
  }))
}

variable "base_node_machine_type" {
  description = "Machine type for the always-on node pool. The largest single cost lever; see docs/cost.md."
  type        = string
  default     = "e2-highmem-4"
}

variable "base_node_disk_size_gb" {
  description = <<-EOT
    Boot disk for base nodes, in GB, on pd-balanced at roughly $0.10/GB/month.

    100 is right once the stateful engines are pulling large images. While only ArgoCD is running,
    50 is ample and halves the line item.
  EOT

  type    = number
  default = 100
}

variable "cluster_deletion_protection" {
  description = "Block terraform destroy on the cluster."
  type        = bool
  default     = true
}

variable "billing_export_table" {
  description = "Name of the billing export table, read off the dataset after enabling the export in the console."
  type        = string
  default     = null
}

variable "create_cost_views" {
  description = "Create cost views. Leave false until the billing export has written its first partition."
  type        = bool
  default     = false
}

variable "github_owner" {
  description = <<-EOT
    GitHub account owning the portfolio repositories. Enables keyless CI authentication via
    Workload Identity Federation.

    Leave null until the repositories exist on GitHub; the module is skipped entirely.
  EOT

  type    = string
  default = null
}
