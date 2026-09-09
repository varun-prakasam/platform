output "dataset_ids" {
  description = "IDs of all created datasets."
  value       = [for d in google_bigquery_dataset.this : d.dataset_id]
}

output "datasets_by_project" {
  description = "Dataset IDs grouped by the project that owns them."
  value = {
    for ref in distinct([for d in var.datasets : d.project_ref]) :
    ref => [for k, d in var.datasets : k if d.project_ref == ref]
  }
}
