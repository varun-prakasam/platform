output "repository_url" {
  description = "Base URL for pushing and pulling images."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "repository_id" {
  description = "Repository name."
  value       = google_artifact_registry_repository.docker.repository_id
}
