// Declared per module, matching the root. A child module inherits the provider *configuration* from
// its caller either way — this only states the constraint, so the module says what it needs rather
// than relying on whoever happens to call it. tflint's recommended ruleset asks for both, and
// satisfying a linter is a better answer than switching it off.
terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
