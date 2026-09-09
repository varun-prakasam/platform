// Budget alerting and the cost data the portfolio hub renders.
//
// One thing Terraform cannot do: enabling the Cloud Billing export to BigQuery. That switch lives
// in the Cloud Console under Billing -> Billing export, and there is no API or provider resource
// for it. The dataset is created here and the console step is documented in docs/cost.md; the
// views below stay disabled until the export table exists.

resource "google_monitoring_notification_channel" "budget_email" {
  count = var.alert_email == null ? 0 : 1

  project      = var.project_id
  display_name = "Platform budget alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

resource "google_pubsub_topic" "budget" {
  project = var.project_id
  name    = "${var.name_prefix}-budget-alerts"
  labels  = var.labels
}

resource "google_billing_budget" "platform" {
  billing_account = var.billing_account_id
  display_name    = var.budget_display_name

  budget_filter {
    projects               = ["projects/${var.project_number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.currency_code
      units         = tostring(var.budget_amount)
    }
  }

  // Alert well before the limit. By the time actual spend hits 100% the money is already gone;
  // the useful signals are the early ones and the forecast.
  dynamic "threshold_rules" {
    for_each = var.actual_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.budget.id
    schema_version                   = "1.0"
    monitoring_notification_channels = var.alert_email == null ? [] : [google_monitoring_notification_channel.budget_email[0].id]
    disable_default_iam_recipients   = false
  }
}

// --- Cost views ---------------------------------------------------------------------------------
// Enabled only once the billing export has been switched on in the console and has written its
// first partition, which takes up to 24 hours.

resource "google_bigquery_table" "cost_by_service" {
  count = var.create_cost_views ? 1 : 0

  project             = var.project_id
  dataset_id          = var.billing_dataset_id
  table_id            = "v_cost_by_service"
  deletion_protection = false
  description         = "Current-month spend by GCP service, net of credits."

  view {
    query          = templatefile("${path.module}/sql/cost_by_service.sql", local.sql_vars)
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "cost_by_project_label" {
  count = var.create_cost_views ? 1 : 0

  project             = var.project_id
  dataset_id          = var.billing_dataset_id
  table_id            = "v_cost_by_project_label"
  deletion_protection = false
  description         = "Current-month spend attributed to each of the ten portfolio projects."

  view {
    query          = templatefile("${path.module}/sql/cost_by_project_label.sql", local.sql_vars)
    use_legacy_sql = false
  }
}

resource "google_bigquery_table" "cost_summary" {
  count = var.create_cost_views ? 1 : 0

  project             = var.project_id
  dataset_id          = var.billing_dataset_id
  table_id            = "v_cost_summary"
  deletion_protection = false
  description         = "Single-row headline figures consumed by the portfolio hub."

  view {
    query          = templatefile("${path.module}/sql/cost_summary.sql", local.sql_vars)
    use_legacy_sql = false
  }
}

locals {
  sql_vars = {
    project_id      = var.project_id
    billing_dataset = var.billing_dataset_id
    export_table    = var.billing_export_table
  }
}
