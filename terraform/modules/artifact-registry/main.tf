// Single Docker repository shared by all ten projects, namespaced by image name.
//
// The cleanup policies matter more than they look: CI pushes an image on every commit, and
// untagged layers from overwritten tags accumulate indefinitely. Without these, registry storage
// becomes one of the larger line items within a few months.

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = "Container images for the data platform and its projects"
  format        = "DOCKER"

  labels = var.labels

  docker_config {
    immutable_tags = false
  }

  cleanup_policy_dry_run = var.cleanup_dry_run

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "${var.untagged_retention_days}d"
    }
  }

  cleanup_policies {
    id     = "keep-recent-releases"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_recent_versions
    }
  }

  cleanup_policies {
    id     = "delete-stale-prerelease"
    action = "DELETE"
    condition {
      tag_state    = "TAGGED"
      tag_prefixes = ["pr-", "dev-", "sha-"]
      older_than   = "${var.prerelease_retention_days}d"
    }
  }
}
