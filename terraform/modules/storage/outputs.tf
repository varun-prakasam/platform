output "bucket_names" {
  description = "Map of bucket key to full bucket name."
  value       = { for k, b in google_storage_bucket.this : k => b.name }
}

output "bucket_urls" {
  description = "Map of bucket key to gs:// URL."
  value       = { for k, b in google_storage_bucket.this : k => "gs://${b.name}" }
}
