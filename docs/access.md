# Access and identity

Who can touch what, and how each identity proves it is who it claims to be.

Every identity on the platform is defined in one place — [`terraform/modules/iam`](../terraform/modules/iam).
If you want the authoritative answer rather than this prose version, read `identities.tf`.

## Three planes

| Plane | Identity | Authenticates by | Created by |
| --- | --- | --- | --- |
| Provisioning | `terraform-deployer` | Key file, or your own user credentials | You, before the first apply |
| CI | `github-actions-ci`, `github-actions-apply` | Workload Identity Federation (OIDC) | Terraform |
| Runtime | `wl-*` (GKE), `api-*` (Cloud Run), `dataflow-worker` | Workload Identity, or attachment | Terraform |

The planes are separate on purpose. The deployer can create a GKE cluster but has no reason to read
warehouse rows; the Cloud Run API for project 3 can read warehouse rows but cannot create anything.
A single "does everything" account would collapse all three and make the blast radius of any one
leak the whole platform.

## Provisioning: the deployer

Terraform cannot create the identity it authenticates as, so this one is bootstrapped by hand.

```bash
gcloud iam service-accounts create terraform-deployer \
  --project=$PROJECT_ID --display-name="Terraform deployer"

make grant-deployer-bootstrap \
  PROJECT_ID=$PROJECT_ID \
  DEPLOYER_SA=terraform-deployer@$PROJECT_ID.iam.gserviceaccount.com \
  BILLING_ACCOUNT_ID=$BILLING_ACCOUNT_ID
```

Then set `deployer_service_account_email` in `terraform.tfvars`. From that point the same bindings
are managed declaratively, so they cannot be revoked by accident or drift out of sync with what the
configuration actually needs.

### Why Editor is not enough

An `Editor` service account cannot complete this apply. Two roles it lacks are load-bearing:

- **`roles/resourcemanager.projectIamAdmin`** — this configuration grants IAM roles to twenty-two
  runtime accounts. Editor can create service accounts but cannot grant them anything.
- **`roles/iam.workloadIdentityPoolAdmin`** — required for the GitHub OIDC pool.

### The grant that gets missed

`roles/billing.costsManager` is granted at **billing-account** scope, not project scope. It is the
one grant `make grant-deployer` cannot infer from the project, and its absence surfaces late — the
budget resource is near the end of the graph, so the first apply gets most of the way through
before failing.

### Key file handling

If you authenticate with a key file rather than user credentials:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.gcp/terraform-deployer.json"
make whoami   # confirms which identity Terraform will use
```

Rules, in order of how much they matter:

1. **The key file never lives inside a repository.** Keep it under `~/.gcp/`. `make whoami` warns if
   the path is inside the working tree, `.gitignore` blocks the common filename shapes, and CI fails
   the build if key material is ever committed — three layers, because this is the failure that is
   both easiest to make and hardest to undo.
2. **The path comes from an environment variable**, never a Terraform variable. A variable would end
   up in state, and state is a file you back up.
3. `chmod 600` it. It is a bearer credential with no expiry.

A key file is the one place this platform holds a long-lived credential. Everything else — pods, CI,
Cloud Run — uses short-lived tokens. If you would rather have zero keys anywhere, use
`gcloud auth application-default login` and leave `deployer_service_account_email` unset; you then
apply as yourself, which is fine for a single-operator platform and removes the only key.

## CI: two identities, split by branch

GitHub Actions authenticates by exchanging its OIDC token for short-lived Google credentials. No key
is stored in a repository secret.

| Identity | Assumable from | Can do |
| --- | --- | --- |
| `github-actions-ci` | Any branch of any listed repo | Build and push images, deploy Cloud Run, `terraform plan` |
| `github-actions-apply` | `refs/heads/main` of `platform` only | `terraform apply` |

The split exists because the apply account holds enough authority to destroy the platform, and a
pull request can edit workflow YAML. That means an `if: github.ref == 'refs/heads/main'` condition in
a workflow is not a security control — an attacker opening a pull request controls that line.

So the restriction is enforced where the pull request cannot reach it. The Workload Identity pool
maps a composite attribute:

```hcl
"attribute.repository_ref" = "assertion.repository + '@' + assertion.ref"
```

and the apply account's impersonation binding names exactly one value of it:

```
principalSet://.../attribute.repository_ref/<owner>/platform@refs/heads/main
```

A token minted on a pull request carries `refs/pull/<n>/merge`, so the exchange is refused by IAM
before any workflow logic runs. The workflow condition is still there, but as documentation rather
than as the control.

Two further guards, neither of which is the primary one:

- The apply job targets a GitHub Environment named `production`. Add a required reviewer there if you
  want a human gate on every apply.
- The apply job's concurrency group never cancels in progress. A cancelled apply leaves a held state
  lock and a partially built graph.

### Repository variables

These are identifiers, not secrets, so GitHub *Variables* is the correct place for them:

| Variable | Scope | Value |
| --- | --- | --- |
| `WIF_PROVIDER` | All repos | From `terraform output github_actions_setup` |
| `WIF_SERVICE_ACCOUNT` | All repos | `github-actions-ci@…` |
| `WIF_APPLY_ACCOUNT` | `platform` only | `github-actions-apply@…` |
| `GCP_PROJECT_ID` | All repos | Your project ID |

Terraform's own inputs are **not** here. Everything that is not sensitive lives in
`terraform/prod.tfvars`, which is committed, so a laptop and a workflow read the same file rather
than two sets of values that happen to agree. Only three inputs are supplied out of band, and as
*Secrets* rather than Variables:

| Secret | Scope | Value |
| --- | --- | --- |
| `GCP_BILLING_ACCOUNT` | `platform` only | Billing account ID |
| `TF_AUTHORIZED_NETWORKS` | `platform` only | JSON, e.g. `[{"cidr_block":"203.0.113.42/32","display_name":"home"}]` |
| `TF_ALERT_EMAIL` | `platform` only | Where budget and pipeline alerts are delivered |

Secrets, not Variables, because these repositories are public and a workflow log prints an
environment dump on every run. Variable values appear in it verbatim; secret values are masked. A
home IP address and a personal email in a world-readable build log is not a hypothetical.

**Why the split exists at all.** Passing every input through the workflow environment meant CI could
only see the values someone had remembered to add there, while `terraform.tfvars` — the file a
laptop reads — is gitignored and invisible to it. The first version of this workflow passed six
inputs and the tfvars file set fourteen. An apply from CI would have read `alert_email` as null and
`pipeline_heartbeats` as empty, deleting the alerting, and `base_node_disk_size_gb` as 100 rather
than 50, recreating the node pool. It never ran only because an unrelated lint job failed first.

A committed var file removes the class of bug rather than the instance: a new input is visible to
both, or to neither.

## Runtime: one account per workload, per surface

Runtime accounts are split by **surface**, not shared per project:

- `wl-<project>` — the GKE workload. Bound to `<namespace>/<ksa>` via Workload Identity.
- `api-<project>` — the Cloud Run API. Attached to the service.

Project 3's dbt job writes to BigQuery. Project 3's API only reads it. Sharing one account between
them would give a public-facing internet service write access to the warehouse for no reason, so
every `api-*` account is read-only. The single exception is project 5's chaos control, whose write
path targets an isolated synthetic Postgres containing no real data — see
[`security.md`](security.md).

`dataflow-worker` is separate again, because Dataflow attaches a service account to worker VMs
rather than running under a Kubernetes service account. Whoever launches a job must hold
`roles/iam.serviceAccountUser` on it; that binding covers the deployer and the p05 GKE account.

### Wiring a workload

Each project's manifests create a Kubernetes service account carrying an annotation that names its
Google counterpart. Rather than hardcoding the project ID in ten repositories, read it:

```bash
terraform -chdir=terraform output -json gke_ksa_annotations
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dbt
  namespace: p03-elt
  annotations:
    iam.gke.io/gcp-service-account: wl-p03-elt@<project>.iam.gserviceaccount.com
```

The namespace and KSA name must match the `gke_workloads` entry exactly. A mismatch does not error —
the pod simply gets no credentials and fails at its first API call, which is a confusing way to spend
an afternoon.

## Known gap

Runtime roles are granted at **project** scope rather than per bucket and per dataset. Project 1's
Flink account needs write access to two datasets and one bucket, not `roles/bigquery.dataEditor`
across the whole project.

This is the most significant deviation from least privilege on the platform, and it is deliberate
rather than overlooked: the per-resource matrix is only knowable once all ten projects have settled
their resource lists, and tightening it early means churn on every project addition. The reasoning
and the closing condition are in [`security.md`](security.md).
