variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for bucket names; GCS names are globally unique so this is usually the project ID."
  type        = string
}

variable "location" {
  description = "Bucket location. Keep this in the same region as the cluster to avoid egress charges."
  type        = string
}

variable "labels" {
  description = "Labels applied to every bucket, used for cost attribution."
  type        = map(string)
  default     = {}
}

variable "buckets" {
  description = <<-EOT
    Buckets to create, keyed by suffix. The key becomes both the name suffix and the `component`
    label used in cost reporting.

    Set `delete_after_days` on anything ingested continuously — raw landing zones in particular.
    Set `delete_prefixes` when part of a bucket must outlive that rule.
  EOT

  type = map(object({
    storage_class       = optional(string, "STANDARD")
    versioning          = optional(bool, false)
    force_destroy       = optional(bool, false)
    nearline_after_days = optional(number)
    delete_after_days   = optional(number)
    # Scope the delete rule to these prefixes. Unset, it applies to the whole bucket.
    delete_prefixes = optional(list(string))
  }))

  default = {
    # Raw landing zone. High churn, replayable from source, so retention is short.
    "lake-raw" = {
      delete_after_days = 30
      force_destroy     = true
    }

    # Iceberg warehouse (project 2). The durable copy — kept, but aged into Nearline.
    "lakehouse" = {
      nearline_after_days = 90
    }

    # Flink checkpoints and savepoints (projects 1 and 5). Only the recent ones matter.
    #
    # Scoped, not bucket-wide. Flink's HA metadata lives here too, under <project>/ha/, and part of
    # it is written once at job submission and never rewritten. A seven-day rule over the whole
    # bucket deletes it on day seven, and the job keeps running green until its first JobManager
    # restart — which then cannot recover. Checkpoints are safe under the rule because a running job
    # rewrites them every minute; HA metadata is not. Project 5 adds its own two prefixes here.
    "flink-state" = {
      delete_after_days = 7
      delete_prefixes   = ["p01/checkpoints/", "p01/savepoints/"]
      force_destroy     = true
    }

    # Spark event logs and job artifacts (project 2).
    "spark" = {
      delete_after_days = 30
      force_destroy     = true
    }

    # StarRocks shared-data backing store (project 8). This is primary storage — never expire it.
    "starrocks" = {
      versioning = false
    }

    # Build artifacts, dbt docs, Evidence static output.
    "artifacts" = {
      versioning        = true
      delete_after_days = 90
      force_destroy     = true
    }

    # Pre-materialised JSON that the project UIs fetch directly, avoiding an API round trip.
    "site-data" = {
      versioning    = true
      force_destroy = true
    }
  }
}
