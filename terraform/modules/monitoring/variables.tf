variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster whose workloads these alerts watch."
  type        = string
}

variable "alert_email" {
  description = "Where pipeline alerts are sent. Null disables alerting entirely."
  type        = string
  default     = null
}

variable "heartbeats" {
  description = <<-EOT
    Pipelines that must report success on a schedule, keyed by project name.

    `namespace` is the Kubernetes namespace the workload runs in and `marker` is the line its
    entrypoint prints on success — successes are counted by watching for that line.

    `window` is the trailing period the count is summed over and must comfortably exceed the
    schedule interval, or an on-time run will not always be inside it. `grace` is how long the
    window may stay empty before the alert fires, and should match the lateness the CronJob's
    startingDeadlineSeconds already tolerates.

    Time to alert is therefore `window + grace` after the last success: 24h + 6h for a daily
    pipeline that permits six hours of lateness.
  EOT

  type = map(object({
    namespace = string
    marker    = string
    window    = optional(string, "86400s")
    grace     = optional(string, "21600s")
  }))

  default = {}
}
