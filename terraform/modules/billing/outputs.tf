output "budget_id" {
  description = "Resource ID of the budget."
  value       = google_billing_budget.platform.id
}

output "budget_topic" {
  description = "Pub/Sub topic receiving budget notifications."
  value       = google_pubsub_topic.budget.id
}

output "cost_summary_view" {
  description = "Fully qualified view the portfolio hub queries for headline cost figures."
  value       = var.create_cost_views ? "${var.project_id}.${var.billing_dataset_id}.v_cost_summary" : null
}
