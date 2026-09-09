# Security

What is enforced, and what is knowingly deferred. The deferred list exists because a portfolio that
claims a clean security posture it does not have is worse than one that documents its gaps.

## Enforced

**No service account keys.** Nothing in this platform creates, downloads or stores a key. Pods
authenticate through Workload Identity; GitHub Actions authenticates through Workload Identity
Federation with an OIDC token exchange. There is no key to leak or rotate.

**Least-privilege node identity.** The node service account holds only logging, monitoring and
registry-read roles. Workload permissions come through Workload Identity, so a compromised pod
cannot inherit node permissions.

**Private nodes.** Nodes have no external IP addresses. Egress flows through Cloud NAT.

**Restricted control plane.** The API server endpoint is reachable only from CIDRs listed in
`authorized_networks`. The default in `terraform.tfvars.example` is a single host, not `0.0.0.0/0`.

**Federation scoped by attribute condition.** The GitHub OIDC provider carries
`assertion.repository_owner == '<owner>'`, and impersonation bindings name individual repositories.
Without the attribute condition any GitHub repository on the internet could exchange a token
against the pool. This is the most commonly missed step in WIF setups.

**Uniform bucket-level access and public access prevention** on every GCS bucket.

**Shielded nodes** with secure boot and integrity monitoring; legacy metadata endpoints disabled.

**Dataplane V2**, which is what makes network policy enforceable between project namespaces.

**Scoped ArgoCD permissions.** The `portfolio` AppProject restricts deployments to the ten project
namespaces and whitelists only the cluster-scoped resource kinds the operators genuinely need. The
default AppProject would allow any repository to deploy anything anywhere.

**CI apply is restricted at the IAM binding, not in workflow YAML.** CI has two identities: a plan
and build account assumable from any branch, holding `roles/viewer` plus narrow write roles for
registry and Cloud Run; and an apply account holding the deployer's full authority, assumable only
from `refs/heads/main` of the platform repository.

The branch restriction is enforced by a composite `repository@ref` attribute in the Workload
Identity pool, not by an `if:` condition in the workflow. This distinction is the whole point — a
pull request can edit workflow YAML, so a condition written there is a control the attacker owns. A
token minted on a pull request carries `refs/pull/<n>/merge` and is refused at token exchange. See
[`access.md`](access.md).

**No key material can be committed.** Three layers: `.gitignore` blocks the common key filename
shapes, `make whoami` warns if the deployer key path is inside the working tree, and CI fails the
build on any file containing `"type": "service_account"`, a PEM private key block, or a key-shaped
filename. The platform holds exactly one long-lived credential — the optional deployer key on your
laptop — and it is the one thing that must never reach a repository.

## Deferred, with reasons

**Project-scoped IAM roles for workloads.** Workload Identity service accounts hold roles at
project level rather than on individual buckets and datasets. Correct would be per-resource
bindings — project 1's Flink account needs write access to two datasets and one bucket, not
`roles/bigquery.dataEditor` across the project.

This is the most significant gap. It is deferred because the per-resource binding matrix is only
knowable once all ten projects have settled their resource lists, and tightening it prematurely
means churn on every project addition. It should be closed once project 10 lands, and closing it is
a natural talking point about how least privilege is arrived at iteratively in practice.

**No Binary Authorization.** Image signing and admission attestation is meaningful with a release
process and multiple contributors. With a single author and no promotion pipeline it would be
ceremony. The corresponding checkov check is skipped explicitly, not silently.

**Public control plane endpoint.** A fully private endpoint would require a bastion or Cloud
Identity-Aware Proxy tunnel for `kubectl`. Given the endpoint is IP-restricted and authenticated,
the added operational friction is not justified here. Also an explicit checkov skip.

**Secrets.** Currently Kubernetes Secrets, which are base64-encoded rather than encrypted at rest
beyond GKE's envelope encryption. Moving to Secret Manager with the CSI driver is planned; the
driver is available but not yet wired to workloads.

**No network policies yet.** Dataplane V2 makes them enforceable, but none are written. Project
namespaces can currently reach each other. Worth adding once the cross-project traffic pattern
(projects 5 and 8 reading project 1's Kafka) is stable enough to encode.

## Public exposure

Nine of the ten project UIs are read-only and safe to expose. Two need care:

**Airflow (project 4)** is fronted by Identity-Aware Proxy. The public artefact is a separate
read-only "control tower" served from Cloud Run, which reads the Airflow REST API through a proxy
holding narrowly scoped credentials. The Airflow UI itself is never public — it can trigger DAGs
and read connection metadata.

**The CDC chaos control (project 5)** lets anonymous visitors trigger schema changes and write
bursts against a Postgres instance. That instance is synthetic and isolated, contains no real data,
and holds no credentials for anything else. The endpoint is rate-limited. It is deliberately the
only write path exposed anywhere in the portfolio, and it is worth being able to explain why it is
safe.
