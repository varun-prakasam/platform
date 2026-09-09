// State lives in GCS with versioning enabled, created by `make bootstrap-state` before the first
// init. The bucket name is not templatable in a backend block, so set it via:
//
//   terraform init -backend-config="bucket=YOUR_PROJECT_ID-tfstate"
//
// or uncomment and hardcode it below once the project ID is settled.

terraform {
  backend "gcs" {
    # bucket = "YOUR_PROJECT_ID-tfstate"
    prefix = "platform"
  }
}
