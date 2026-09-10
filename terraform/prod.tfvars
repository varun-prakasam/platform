# Non-sensitive configuration for the production platform. Committed on purpose.
#
# CI cannot read terraform.tfvars — it is gitignored, and rightly so. Passing values through
# workflow environment variables instead created two sources of truth, and the drift was not
# theoretical: an apply from CI would have read alert_email as null and pipeline_heartbeats as {},
# destroying the alerting, and base_node_disk_size_gb as 100, recreating the node pool. Everything
# that is not a secret therefore lives here, where both a laptop and a workflow read the same file.
#
# Secrets stay out. billing_account_id, authorized_networks and alert_email are supplied locally by
# terraform.tfvars and in CI by repository secrets. Note that workflow logs on a public repository
# print variable values but mask secrets, which is why the home IP is not a variable.
#
# Usage is identical in both places:
#   terraform plan -var-file=prod.tfvars

# --- Identity -------------------------------------------------------------------------------------

project_id = "varun-data-engineering"

# --- Location -------------------------------------------------------------------------------------

region = "us-central1"
zone   = "us-central1-a"

# --- Cost -----------------------------------------------------------------------------------------

# This billing account is denominated in SGD, so budget_amount is SGD, not USD. The currency must
# match the account exactly or the budget fails to create — and the module default is USD, which is
# precisely the kind of silent mismatch this file exists to prevent.
budget_amount = 200
currency_code = "SGD"

# Sized for the platform, ArgoCD, p03's CronJob and p01's Kafka + Flink.
#
#   e2-standard-2  2 vCPU /  8 GiB  ~$49/mo  platform + ArgoCD + one lightweight project
#   e2-standard-4  4 vCPU / 16 GiB  ~$98/mo  <- here: adds p01's broker and stream processor
#   e2-highmem-2   2 vCPU / 16 GiB  ~$66/mo  more memory, same 2 vCPU — does not help p01
#   e2-highmem-4   4 vCPU / 32 GiB ~$132/mo  full ten-project steady state
#
# CPU binds first, not memory, which is why the highmem shapes cost.md recommends are the wrong
# answer today: measured on e2-standard-2 the node sat at 66% of CPU requests against 37% of memory.
# p01 needs ~2100m (Kafka 700m, Strimzi 200m, Flink JM+TM 900m, Flink operator 150m, bridge 150m)
# against 639m free, so this is a 3x gap rather than a tuning problem.
#
# Two e2-standard-2 nodes cost the same $98 and fit less: GKE's system daemons take ~1000m on *every*
# node, so a second one contributes ~930m usable where a doubled node contributes ~1980m. It would
# also put Kafka and Flink on separate nodes, adding a network hop to every record.
#
# After p01 this node runs at ~87% of CPU requests, and ~94% for the two minutes a day p03's CronJob
# is running. That is deliberate but it is the ceiling: project 4 forces either the Spot flip
# (cost.md:47) or e2-highmem-4. Watch for Pending pods — the pool autoscales to 2 and will quietly
# add another $98/mo node rather than fail.
#
# e2-medium is not viable at any point: ~940m allocatable against the ~1000m the system daemons want.
base_node_machine_type = "e2-standard-4"
base_node_disk_size_gb = 50

# --- Identity -------------------------------------------------------------------------------------

deployer_service_account_email = "terraform-deployer@varun-data-engineering.iam.gserviceaccount.com"

# Enables keyless CI auth via Workload Identity Federation: GitHub Actions exchanges its own OIDC
# token for a short-lived GCP one, so nothing long-lived is ever stored as a repository secret.
github_owner = "varun-prakasam"

# --- Safety ---------------------------------------------------------------------------------------

# Blocks `terraform destroy` on the cluster. To tear down, set false, apply, then destroy.
cluster_deletion_protection = true

# --- Pipeline alerting ----------------------------------------------------------------------------

# Add a project here once its pipeline has had one green run — the staleness alert works by noticing
# an existing signal stop, so it cannot fire for a pipeline that has never succeeded.
#
# The marker is the last line the project's entrypoint prints. Change it there and it must change
# here, which is the one fragile joint in this design; the alternative is alerting on pod exit
# status, which says the container stopped cleanly rather than that the work finished.
pipeline_heartbeats = {
  "p03-elt" = {
    namespace = "p03-elt"
    marker    = "=== done ==="
    # Daily at 09:00 UTC, so a 24h window always contains one success. The CronJob already tolerates
    # six hours of lateness via startingDeadlineSeconds, so a six-hour grace alerts about thirty
    # hours after a missed run and never for one that merely started late.
    window = "86400s"
    grace  = "21600s"
  }
}

# --- Billing export -------------------------------------------------------------------------------
# Enable the export in the console first, wait for the first partition, then set these and re-apply.

# The table name embeds the billing account ID, so it belongs with the other secrets in
# terraform.tfvars rather than here. Read the generated name off the dataset once the export
# has written its first partition.
# billing_export_table = "gcp_billing_export_resource_v1_<billing account id>"
# create_cost_views    = true
