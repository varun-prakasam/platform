// GCS buckets backing the lake, the Iceberg warehouse, engine state and the static site data.
//
// Every bucket carries a lifecycle rule. Storage is the cost line that grows silently on a
// platform that ingests continuously, so retention is set explicitly at creation rather than
// discovered later on a bill.

resource "google_storage_bucket" "this" {
  for_each = var.buckets

  project  = var.project_id
  name     = "${var.name_prefix}-${each.key}"
  location = var.location

  storage_class               = each.value.storage_class
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = each.value.force_destroy

  versioning {
    enabled = each.value.versioning
  }

  // Age out to cheaper classes before deleting, where the data is worth keeping cold.
  dynamic "lifecycle_rule" {
    for_each = each.value.nearline_after_days == null ? [] : [1]
    content {
      condition {
        age = each.value.nearline_after_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }

  dynamic "lifecycle_rule" {
    for_each = each.value.delete_after_days == null ? [] : [1]
    content {
      condition {
        age = each.value.delete_after_days
        # null leaves the attribute unset, which GCS reads as the whole bucket — so every bucket
        # without delete_prefixes keeps exactly the rule it had.
        matches_prefix = each.value.delete_prefixes
      }
      action {
        type = "Delete"
      }
    }
  }

  // Old object versions are pure cost once superseded.
  dynamic "lifecycle_rule" {
    for_each = each.value.versioning ? [1] : []
    content {
      condition {
        num_newer_versions = 3
        with_state         = "ARCHIVED"
      }
      action {
        type = "Delete"
      }
    }
  }

  // Incomplete resumable uploads are invisible in the console but still billed.
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  labels = merge(var.labels, { component = each.key })
}
