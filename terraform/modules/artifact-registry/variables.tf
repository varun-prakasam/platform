variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the repository. Keep it colocated with GKE so image pulls stay free."
  type        = string
}

variable "repository_id" {
  description = "Repository name."
  type        = string
  default     = "data-platform"
}

variable "labels" {
  description = "Labels applied to the repository."
  type        = map(string)
  default     = {}
}

variable "cleanup_dry_run" {
  description = "Report what the cleanup policies would delete without deleting it. Set true on first apply to verify the policies, then flip to false."
  type        = bool
  default     = true
}

variable "untagged_retention_days" {
  description = "Days to keep untagged image versions."
  type        = number
  default     = 7
}

variable "prerelease_retention_days" {
  description = "Days to keep pr-/dev-/sha- prefixed tags."
  type        = number
  default     = 30
}

variable "keep_recent_versions" {
  description = "Number of most recent versions always retained, regardless of other policies."
  type        = number
  default     = 10
}
