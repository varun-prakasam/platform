# GitOps

Cluster state is delivered by ArgoCD. Terraform provisions the cluster; nothing else is applied by
hand except the two bootstrap commands below.

## Layout

```
gitops/
├── bootstrap/              Applied manually, once
│   ├── namespace.yaml
│   ├── priorityclasses.yaml
│   ├── kustomization.yaml  Pinned ArgoCD install + resource trims
│   └── patches/
└── apps/
    ├── root.yaml           App-of-apps; the only Application applied by hand
    └── projects/
        ├── _appproject.yaml    Permission boundary for all ten projects
        └── pNN-*.yaml          One Application per project
```

Each `pNN-*.yaml` points at that project's own repository. The project repos own their manifests;
this repo owns only the declaration of where they live and how they sync.

## Install

```bash
make argocd            # installs ArgoCD, waits for rollout, applies root.yaml
make argocd-password   # initial admin password
make argocd-ui         # https://localhost:8080
```

`root.yaml` is deliberately not applied until the `platform` repo is pushed to GitHub — it points at
that repo, and ArgoCD cannot sync a source that does not exist. Install ArgoCD itself first, then
apply `root.yaml` once the push has landed. After that the child applications show as `Unknown`
until their own project repos exist, which is expected rather than a failure.

## Adding a project

1. Copy `apps/projects/p03-elt.yaml`, change the name, repo URL and namespace.
2. Set a sync wave that reflects dependencies. Projects that produce tables others consume sync
   first.
3. Commit. ArgoCD picks it up on the next reconciliation; nothing is applied manually.

## Conventions

**Namespaces** match the project key (`p01-streaming` … `p10-governance`). The Workload Identity
bindings in Terraform assume this, so a namespace rename requires a matching Terraform change.

**Priority classes** must be set explicitly on every workload. `pipeline-default` is the global
default, so an unlabelled pod gets middling priority — fine for scheduled jobs, wrong for a Kafka
broker. Stateful engines must declare `stateful-engine`; Spark executors must declare
`batch-preemptible` and tolerate the `workload-class=batch` taint, or they will schedule onto the
expensive on-demand pool.

**Server-side apply** is enabled on project applications. Several operator CRDs exceed the
annotation size limit that client-side apply relies on.

## Why ArgoCD rather than Terraform for workloads

Terraform's Kubernetes provider requires the cluster to exist at plan time, which makes a
create-from-scratch run a two-phase apply. More importantly, a controller that continuously
reconciles drift is a different guarantee from a CLI that reconciles when someone runs it. On a
platform whose selling point is that it stays live, continuous reconciliation is the correct
property.
