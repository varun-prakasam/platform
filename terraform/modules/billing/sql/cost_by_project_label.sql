-- Current-month spend attributed to each of the ten portfolio projects.
--
-- Attribution comes from three sources, in priority order:
--
--   1. project_ref  a label this platform's Terraform puts on datasets and buckets
--   2. goog-k8s-namespace  emitted by GKE cost allocation, which is enabled on the cluster
--   3. everything else falls to shared-platform: the control plane, NAT, registry and other
--      genuinely shared infrastructure that should not be charged to any single project
--
-- The third bucket existing and being labelled honestly matters. Silently spreading shared cost
-- across projects would make the per-project figures look precise while being fiction.

WITH usage AS (
  SELECT
    cost,
    IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0) AS credit_amount,
    currency,
    service.description AS service,
    (SELECT value FROM UNNEST(labels) WHERE key = 'project_ref') AS label_project_ref,
    (SELECT value FROM UNNEST(labels) WHERE key = 'goog-k8s-namespace') AS k8s_namespace
  FROM `${project_id}.${billing_dataset}.${export_table}`
  WHERE
    _PARTITIONTIME >= TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
    AND invoice.month = FORMAT_DATE('%Y%m', CURRENT_DATE())
)

SELECT
  COALESCE(label_project_ref, k8s_namespace, 'shared-platform') AS portfolio_project,
  SUM(cost) + SUM(credit_amount) AS net_cost,
  SUM(cost) AS gross_cost,
  SUM(credit_amount) AS credits,
  COUNT(DISTINCT service) AS services_used,
  ANY_VALUE(currency) AS currency
FROM usage
GROUP BY portfolio_project
ORDER BY net_cost DESC
