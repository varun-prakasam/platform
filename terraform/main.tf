data "google_project" "this" {
  project_id = var.project_id
}

locals {
  labels = {
    managed_by = "terraform"
    platform   = "data-platform"
  }
}

// API enablement gates everything else. Without the explicit depends_on below, Terraform races
// ahead and fails the first apply with "API not enabled" on roughly half the resources.
module "project_services" {
  source = "./modules/project-services"

  project_id = var.project_id
}

module "network" {
  source = "./modules/network"

  project_id = var.project_id
  region     = var.region

  depends_on = [module.project_services]
}

module "storage" {
  source = "./modules/storage"

  project_id  = var.project_id
  name_prefix = var.project_id
  location    = var.region
  labels      = local.labels

  depends_on = [module.project_services]
}

module "bigquery" {
  source = "./modules/bigquery"

  project_id = var.project_id
  location   = var.region
  labels     = local.labels

  depends_on = [module.project_services]
}

module "artifact_registry" {
  source = "./modules/artifact-registry"

  project_id = var.project_id
  region     = var.region
  labels     = local.labels

  depends_on = [module.project_services]
}

// Every identity on the platform. Deliberately applied before the cluster so the runtime accounts
// exist by the time any workload is scheduled.
module "iam" {
  source = "./modules/iam"

  project_id                     = var.project_id
  deployer_service_account_email = var.deployer_service_account_email

  depends_on = [module.project_services]
}

module "gke" {
  source = "./modules/gke"

  project_id = var.project_id
  zone       = var.zone

  network_id          = module.network.network_id
  subnet_id           = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  node_tag            = module.network.node_tag

  authorized_networks    = var.authorized_networks
  base_node_machine_type = var.base_node_machine_type
  base_node_disk_size_gb = var.base_node_disk_size_gb
  deletion_protection    = var.cluster_deletion_protection
  labels                 = local.labels

  depends_on = [module.project_services]
}

// Skipped until the repositories exist on GitHub. Set github_owner to enable keyless CI auth.
module "github_oidc" {
  source = "./modules/github-oidc"
  count  = var.github_owner == null ? 0 : 1

  project_id   = var.project_id
  github_owner = var.github_owner

  // The apply account carries the deployer's authority. Sourcing the list from the iam module keeps
  // "what CI can do" and "what I can do" identical by construction.
  apply_roles = module.iam.deployer_roles

  depends_on = [module.project_services]
}

module "billing" {
  source = "./modules/billing"

  project_id         = var.project_id
  project_number     = data.google_project.this.number
  billing_account_id = var.billing_account_id

  budget_amount = var.budget_amount
  currency_code = var.currency_code
  alert_email   = var.alert_email

  billing_export_table = var.billing_export_table
  create_cost_views    = var.create_cost_views
  labels               = local.labels

  depends_on = [module.project_services, module.bigquery]
}

// Watches the scheduled pipelines rather than the infrastructure. A node going unhealthy is
// already visible in the console; a nightly job that quietly stops producing data is not, and it is
// the failure that actually costs something, because everything downstream keeps serving the last
// good numbers as though nothing happened.
module "monitoring" {
  source = "./modules/monitoring"

  project_id   = var.project_id
  cluster_name = module.gke.cluster_name
  alert_email  = var.alert_email

  heartbeats = var.pipeline_heartbeats

  depends_on = [module.project_services, module.gke]
}
