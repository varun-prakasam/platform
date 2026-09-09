variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the subnet, router and NAT."
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network."
  type        = string
  default     = "data-platform"
}

variable "subnet_cidr" {
  description = "Primary CIDR for the node subnet."
  type        = string
  default     = "10.0.0.0/20"
}

variable "pods_cidr" {
  description = "Secondary CIDR for GKE pods."
  type        = string
  default     = "10.4.0.0/14"
}

variable "services_cidr" {
  description = "Secondary CIDR for GKE services."
  type        = string
  default     = "10.8.0.0/20"
}

variable "master_cidr" {
  description = "CIDR of the GKE control plane, used to allow webhook traffic to nodes."
  type        = string
  default     = "172.16.0.0/28"
}

variable "pods_range_name" {
  description = "Name of the secondary range used for pods."
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the secondary range used for services."
  type        = string
  default     = "services"
}

variable "node_tag" {
  description = "Network tag applied to GKE nodes, used as a firewall target."
  type        = string
  default     = "data-platform-node"
}
