variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "project_number" {
  description = "GCP project number. Budget filters address projects by number, not ID."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account ID in the form XXXXXX-XXXXXX-XXXXXX."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "data-platform"
}

variable "budget_display_name" {
  description = "Name shown in the Cloud Console budget list."
  type        = string
  default     = "Data platform monthly budget"
}

variable "budget_amount" {
  description = <<-EOT
    Monthly budget in whole currency units.

    Set this before the first apply, not after. The full ten-project build-out runs at roughly $185
    per month, so a limit around $250 leaves headroom for a bad week without hiding a runaway.
  EOT

  type    = number
  default = 250
}

variable "currency_code" {
  description = "Budget currency. Must match the billing account currency."
  type        = string
  default     = "USD"
}

variable "actual_thresholds" {
  description = "Fractions of the budget at which to alert on actual spend."
  type        = list(number)
  default     = [0.5, 0.8, 1.0]
}

variable "alert_email" {
  description = "Email address for budget alerts. Null disables the email channel."
  type        = string
  default     = null
}

variable "billing_dataset_id" {
  description = "Dataset holding the billing export and the derived cost views."
  type        = string
  default     = "platform_billing"
}

variable "billing_export_table" {
  description = <<-EOT
    Name of the table the billing export writes to. Google generates this as
    `gcp_billing_export_resource_v1_<BILLING_ACCOUNT_ID_WITH_UNDERSCORES>`; read the exact name off
    the dataset after enabling the export.
  EOT

  type    = string
  default = null
}

variable "create_cost_views" {
  description = "Create the cost views. Leave false until the billing export has written its first partition, or the views will fail to validate."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to created resources."
  type        = map(string)
  default     = {}
}
