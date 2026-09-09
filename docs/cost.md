# Cost

The platform is designed to a budget, and the budget is a stated design constraint rather than an
afterthought. This document records where the money goes, which levers exist, and what each lever
costs in capability.

## Steady state, all ten projects live

| Component | Est. monthly | Notes |
| --- | --- | --- |
| GKE control plane | $0 | Free tier covers one zonal cluster |
| Base node pool, `e2-highmem-4` on-demand | ~$130 | 4 vCPU / 32 GiB |
| Spot batch pool | ~$5 | Scales from zero; only bills during Spark runs |
| Persistent disks (~150 GiB balanced) | ~$15 | Kafka, Postgres, StarRocks, Airflow metadata |
| Cloud NAT | ~$3 | Required by private nodes |
| BigQuery | ~$10 | 1 TiB queries and 10 GiB storage are free monthly |
| GCS | ~$5 | Lifecycle rules keep raw zones from accumulating |
| Vertex AI embeddings | ~$4 | Project 7 only |
| Dataflow | ~$4 | Burst runs only; the always-on path uses the Flink runner |
| Dataplex, DLP | ~$5 | |
| Cloud Run, Firebase Hosting, Artifact Registry, logging | ~$8 | Mostly within free tiers |
| **Total** | **~$189** | |

Cost is not incurred all at once. With only the platform and the first two or three projects
deployed, a smaller node type is sufficient and the bill sits nearer $60–80.

## The one lever that matters

`base_node_machine_type` is roughly 70% of the bill. Everything else is rounding.

| Machine type | vCPU / RAM | ~Monthly | Supports |
| --- | --- | --- | --- |
| `e2-standard-2` | 2 / 8 GiB | $49 | Platform plus one lightweight project |
| `e2-highmem-2` | 2 / 16 GiB | $65 | First three or four projects |
| `e2-highmem-4` | 4 / 32 GiB | $130 | All ten |
| `e2-highmem-8` | 8 / 64 GiB | $260 | Headroom that is not needed |

Start at `e2-highmem-2`. Scaling up is a variable change and a rolling node pool replacement, not a
migration.

The workloads are memory-hungry and CPU-idle — five JVMs sitting mostly at rest — so high-memory
types are the efficient shape. A `e2-standard-8` costs more than `e2-highmem-4` and delivers less
of what this platform actually consumes.

## Reduction options

**Flip the base pool to Spot.** Saves roughly $95/month, around half the total bill. The
PodDisruptionBudgets, checkpoint-to-GCS configuration and graceful shutdown handling are already in
place, so the platform recovers from preemption without intervention. The cost is a few minutes of
degraded dashboards when a node is reclaimed. This is the single largest saving available and the
first thing to try if the bill becomes uncomfortable.

**Reduce BigQuery time travel.** Datasets are created with `max_time_travel_hours = 48` rather than
the 168-hour default. Already applied.

**Shorten raw-zone retention.** The `lake-raw` bucket expires objects after 30 days and
`p01_streaming_raw` tables after 14. Both are replayable from source. Shortening further is safe
but saves little at this volume.

**Turn off the Spot batch pool.** Saves ~$5. Not worth the loss of the Spark project.

## What is deliberately not optimised

**Cloud Composer** would cost ~$100/month against ~$0 for self-hosting Airflow on the existing
cluster. Self-hosting is also the better showcase.

**24/7 Dataflow streaming** would cost ~$60/month. Beam runs on the in-cluster Flink runner
continuously and on Dataflow only in scheduled bursts, which preserves the runner-portability
demonstration at a fraction of the price.

**Regional GKE** would triple the control plane and node cost. A zonal cluster accepts a control
plane outage during zone maintenance; workloads keep running, and for a portfolio that is the right
trade.

## Making cost visible

Cloud Billing exports to BigQuery, three views summarise it, and the portfolio hub renders the
current month. The export is enabled manually — there is no Terraform resource for it:

1. Console → Billing → Billing export → BigQuery export → Edit settings
2. Select the project and the `platform_billing` dataset
3. Wait up to 24 hours for the first partition
4. Read the generated table name off the dataset
5. Set `billing_export_table` and `create_cost_views = true`, then re-apply

Per-project attribution works because GKE cost allocation is enabled on the cluster and every
dataset and bucket carries a `project_ref` label. Anything not attributable falls to
`shared-platform` rather than being spread across projects — a smaller, honest number beats a
larger, invented one.

## Budget alerts

Alerts fire at 50%, 80% and 100% of actual spend, plus once when the forecast exceeds the budget.
Set `budget_amount` and `alert_email` before the first apply. The forecast alert is the useful one;
by the time actual spend crosses 100% the money is already committed.
