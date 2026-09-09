-- Current-month spend by GCP service, net of credits.
--
-- Both the partition filter and the invoice.month filter are present deliberately. invoice.month
-- alone is correct but scans the whole table, and a cost dashboard that is itself expensive to
-- query is a poor advertisement. The _PARTITIONTIME predicate prunes to the current month's
-- partitions; the invoice filter then makes the result exact.

SELECT
  service.description AS service,
  SUM(cost) AS gross_cost,
  SUM(
    IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)
  ) AS credits,
  SUM(cost) + SUM(
    IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)
  ) AS net_cost,
  ANY_VALUE(currency) AS currency
FROM `${project_id}.${billing_dataset}.${export_table}`
WHERE
  _PARTITIONTIME >= TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
  AND invoice.month = FORMAT_DATE('%Y%m', CURRENT_DATE())
GROUP BY service
HAVING net_cost > 0
ORDER BY net_cost DESC
