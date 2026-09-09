-- Headline cost figures rendered on the portfolio hub.
--
-- The forecast is a straight-line extrapolation of month-to-date spend. That is crude, and it
-- overstates early in a month when fixed costs like the node pool dominate. It is good enough to
-- catch a runaway, which is the only thing a headline figure needs to do.

WITH current_month AS (
  SELECT
    SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)) AS net_cost,
    ANY_VALUE(currency) AS currency
  FROM `${project_id}.${billing_dataset}.${export_table}`
  WHERE
    _PARTITIONTIME >= TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
    AND invoice.month = FORMAT_DATE('%Y%m', CURRENT_DATE())
),

previous_month AS (
  SELECT
    SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)) AS net_cost
  FROM `${project_id}.${billing_dataset}.${export_table}`
  WHERE
    _PARTITIONTIME >= TIMESTAMP(DATE_SUB(DATE_TRUNC(CURRENT_DATE(), MONTH), INTERVAL 1 MONTH))
    AND _PARTITIONTIME < TIMESTAMP(DATE_TRUNC(CURRENT_DATE(), MONTH))
    AND invoice.month = FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
),

calendar AS (
  SELECT
    EXTRACT(DAY FROM CURRENT_DATE()) AS day_of_month,
    EXTRACT(DAY FROM LAST_DAY(CURRENT_DATE())) AS days_in_month
)

SELECT
  ROUND(c.net_cost, 2) AS month_to_date_cost,
  ROUND(c.net_cost / cal.day_of_month * cal.days_in_month, 2) AS forecast_month_end_cost,
  ROUND(p.net_cost, 2) AS previous_month_cost,
  ROUND(c.net_cost / cal.day_of_month, 2) AS average_daily_cost,
  cal.day_of_month,
  cal.days_in_month,
  c.currency,
  CURRENT_TIMESTAMP() AS refreshed_at
FROM current_month AS c
CROSS JOIN previous_month AS p
CROSS JOIN calendar AS cal
