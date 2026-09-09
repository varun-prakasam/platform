output "enabled_services" {
  description = "Fully qualified names of the APIs enabled by this module."
  value       = [for s in google_project_service.this : s.service]
}
