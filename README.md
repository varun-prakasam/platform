# Data Platform

Shared infrastructure for a portfolio of ten production data engineering projects running on
Google Cloud. This repo provisions everything the projects depend on — the GKE cluster, network,
storage, warehouse datasets, image registry, GitOps delivery and cost controls — so that each
project repo contains only its own pipeline code and Kubernetes manifests.

Deliberately, this is not just glue. The platform layer is the thing that makes ten independent
data products behave like one system: shared identity, shared observability, shared cost
accounting, one delivery mechanism.

## Architecture

```
                     ┌────────────────────────────────────────────┐
   Public data       │              GKE (zonal, Standard)         │
   sources           │                                            │
        │            │  Flink Operator      StarRocks Operator    │
        │            │  Strimzi (Kafka)     Spark Operator        │
        └───────────▶│  CloudNativePG       Airflow (K8s exec)    │
                     │  Debezium            Marquez               │
                     └────────────┬───────────────────────────────┘
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
         ┌─────────┐        ┌──────────┐        ┌──────────┐
         │   GCS   │        │ BigQuery │        │ Dataplex │
         │ (lake + │        │ (ware-   │        │ (catalog │
         │ Iceberg)│        │  house)  │        │  + DLP)  │
         └─────────┘        └──────────┘        └──────────┘
              │                   │                   │
              └───────────────────┼───────────────────┘
                                  ▼
                    ┌─────────────────────────────┐
                    │  Cloud Run APIs (per project)│  ← scale to zero
                    └──────────────┬──────────────┘
                                   ▼
                    ┌─────────────────────────────┐
                    │  Firebase Hosting (10 UIs +  │
                    │  portfolio hub)              │
                    └─────────────────────────────┘
```

The full interactive diagram, including cross-project data flows, is generated from
[`diagrams/architecture.d2`](diagrams/architecture.d2) and published to the portfolio hub.

## What runs where, and why

Not everything belongs on Kubernetes. The split is deliberate:

| Workload | Runtime | Rationale |
| --- | --- | --- |
| Stateful engines (Kafka, Flink, StarRocks, Postgres, Airflow, Spark, Marquez) | GKE | Need operators, persistent volumes, always-on scheduling |
| Project APIs and frontends | Cloud Run + Firebase Hosting | Traffic is near-zero; scale-to-zero costs nothing where a pod would bill 24/7 |
| Warehouse, lake, catalog, embeddings, batch streaming | BigQuery / GCS / Dataplex / Vertex AI / Dataflow | Managed services with no operational upside to self-hosting |

Cloud Run reaches cluster-internal services over **Direct VPC egress**, which avoids the
~$10/month Serverless VPC Access connector.

## Cluster design

- **One zonal Standard cluster.** The GKE free tier covers the control plane management fee for a
  single zonal cluster. A regional cluster would triple both control plane and node cost for
  availability a portfolio does not need.
- **Private nodes** with Cloud NAT for egress, and a public control plane endpoint restricted to
  authorised networks. Nodes have no external IPs.
- **Two node pools.** A base pool of on-demand nodes hosts the always-on stateful services so that
  live demos never go dark. A Spot pool autoscaling from zero handles Spark batch bursts, which
  are retry-safe and have no uptime requirement.
- **Workload Identity** everywhere. No service account keys are created, downloaded or stored
  anywhere in this platform.
- PodDisruptionBudgets, priority classes and checkpoint-to-GCS are configured on all stateful
  workloads. This is correct practice regardless, and it means the base pool can be flipped to
  Spot by changing one variable if cost needs to come down.

## Repository layout

```
platform/
├── terraform/
│   ├── modules/
│   │   ├── project-services/   API enablement
│   │   ├── iam/                Every identity: deployer, runtime, Workload Identity bindings
│   │   ├── network/            VPC, subnets, Cloud NAT, firewall
│   │   ├── github-oidc/        Keyless CI auth, split plan/apply identities
│   │   ├── gke/                Cluster and node pools
│   │   ├── storage/            GCS buckets (raw, Iceberg, artifacts, state)
│   │   ├── bigquery/           Warehouse datasets per medallion layer
│   │   ├── artifact-registry/  Container images
│   │   └── billing/            Budget alerts + billing export to BigQuery
│   └── *.tf                    Root configuration
├── gitops/
│   ├── bootstrap/              ArgoCD installation
│   └── apps/                   App-of-apps; one Application per project
├── diagrams/                   Architecture as code (D2)
├── docs/                       Runbooks and decision records
└── .github/workflows/          CI: fmt, validate, plan, tflint, checkov
```

## Bootstrapping

Prerequisites: `gcloud`, `terraform` >= 1.9, `kubectl`, `helm`, and a GCP project with billing
enabled.

```bash
# 1. Authenticate
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID

# 2. Create the Terraform state bucket (chicken-and-egg; this one is manual)
make bootstrap-state PROJECT_ID=YOUR_PROJECT_ID

# 3. Grant the deployer its roles. Terraform cannot create the identity it runs as, and an
#    Editor service account is not sufficient — see docs/access.md.
make grant-deployer-bootstrap \
  PROJECT_ID=YOUR_PROJECT_ID \
  DEPLOYER_SA=terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com \
  BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX

# 4. Configure
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars

# 5. Provision
make whoami        # confirm which identity Terraform will authenticate as
make plan
make apply

# 6. Connect kubectl and install ArgoCD
make kubeconfig
make argocd
```

Identity is the part worth reading before the first apply:
[`docs/access.md`](docs/access.md).

## Cost

The platform is designed to run the full ten-project portfolio for a predictable monthly figure,
and to make that figure visible rather than assumed. Cloud Billing exports to BigQuery, a
scheduled query summarises spend by service and by project label, and the portfolio hub renders
the current month's actual cost.

A budget alert fires at a configurable threshold. Set `budget_amount` in `terraform.tfvars`
before the first apply — not after.

Cost scales with how many of the ten projects are deployed. Early on the cluster runs a single
small node; the figures below are the steady state with all ten live.

| Component | Est. monthly |
| --- | --- |
| GKE control plane (zonal) | $0 — free tier |
| Base node pool (on-demand) | ~$130 |
| Spot burst pool (Spark, scales from zero) | ~$5 |
| Persistent disks | ~$15 |
| Cloud NAT | ~$3 |
| BigQuery, GCS, Vertex AI, Dataflow, Dataplex | ~$28 |
| Cloud Run, Firebase Hosting, Artifact Registry, logging | ~$8 |
| **Total** | **~$189** |

The single largest lever is `base_node_machine_type`. See [`docs/cost.md`](docs/cost.md) for the
reduction options and what each one trades away.

## Projects on this platform

| # | Project | Discipline | Primary tools |
| --- | --- | --- | --- |
| 1 | Streaming pipeline | Stream processing | Kafka, Flink |
| 2 | Lakehouse | Distributed batch, table formats | Spark, Iceberg, BigLake |
| 3 | ELT and dimensional modelling | Analytics engineering | dbt, dlt, Evidence |
| 4 | Orchestration | Workflow orchestration | Airflow 3 |
| 5 | CDC and replication | Change data capture | Debezium, Beam, Dataflow |
| 6 | Data quality | Data reliability engineering | Soda, OpenLineage, Marquez |
| 7 | Vector pipeline | AI data engineering | Vertex AI, BigQuery vector search |
| 8 | Real-time OLAP | Sub-second serving | StarRocks |
| 9 | Feature store | ML data engineering | Feast, Vertex AI Pipelines |
| 10 | Governance | Metadata and security | Dataplex, Cloud DLP |
