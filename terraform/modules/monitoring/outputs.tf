output "notification_channel" {
  description = "Notification channel receiving pipeline alerts. Null when alerting is disabled."
  value       = var.alert_email == null ? null : google_monitoring_notification_channel.pipeline_email[0].id
}

output "alert_policies" {
  description = "Display names of the alert policies created, for confirming what is armed."
  value = var.alert_email == null ? [] : concat(
    [google_monitoring_alert_policy.job_gave_up[0].display_name],
    [for k, p in google_monitoring_alert_policy.pipeline_stale : p.display_name],
  )
}
