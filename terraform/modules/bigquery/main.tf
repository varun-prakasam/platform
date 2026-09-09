// Warehouse datasets, one set per project, laid out in medallion layers where the project uses
// them.
//
// Two settings here are cost controls rather than modelling decisions:
//
//   default_table_expiration — raw and bronze layers ingest continuously and are replayable from
//   source, so tables created there expire automatically. Without this, storage grows unbounded.
//
//   max_time_travel_hours — BigQuery bills time travel storage. The 168-hour default is generous
//   for tables rewritten hourly; 48 hours is ample for recovery here and meaningfully cheaper.

resource "google_bigquery_dataset" "this" {
  for_each = var.datasets

  project     = var.project_id
  dataset_id  = each.key
  location    = var.location
  description = each.value.description

  default_table_expiration_ms = (
    each.value.default_table_expiration_days == null
    ? null
    : each.value.default_table_expiration_days * 24 * 60 * 60 * 1000
  )

  max_time_travel_hours = each.value.max_time_travel_hours

  delete_contents_on_destroy = each.value.delete_contents_on_destroy

  labels = merge(var.labels, {
    project_ref = each.value.project_ref
    layer       = each.value.layer
  })
}
