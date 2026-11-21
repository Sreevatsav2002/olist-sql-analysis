-- ============================================================
-- Q1: ORDER FULFILMENT FUNNEL (Olist: orders + reviews)
-- Question: how many orders reach each stage (purchased -> approved -> handed to
-- carrier -> delivered -> reviewed), where do they drop off, and how long does
-- each stage take?
--
-- GRAIN: orders has one row per order (99,441). reviews can have several rows per
-- order, so reviews are collapsed to one row per order before joining
-- (collapse_review) to avoid fan-out.
--
-- STAGES: counted from timestamps, not order_status (status is only the current
-- state: 99,281 orders have an approval time but only 2 have status 'approved').
-- Strict funnel: an order counts at a stage only if it has every earlier
-- timestamp. Canceled and unavailable orders stay in. The review stage uses the
-- first review ANSWER (review_answer_timestamp), not the survey creation date.
--
-- DURATIONS: median gap between consecutive stages (medians, because a few very
-- late orders skew averages). A negative gap (a stage timestamp earlier than the
-- previous one) is set to NULL for durations, but the order stays in the counts:
-- counts ask "did it reach the stage", durations ask "how long did it take".
--
-- QUERIES IN THIS FILE (top to bottom)
--   Main query (lines below, WITH ... FROM comb_table): strict stage counts,
--     negative-gap counts and median durations.
--   Checks A-F: surveys vs the estimated delivery date, what happened to the
--     orders lost between approval and carrier, and sanity checks.
--   Stage table (last query): orders, % of purchased and orders lost per stage.
-- NOTE: comb_table and funnel are CTEs defined inside the main query. A query
-- further down can only use them when it is run together with those CTEs.
--
-- FINDINGS
-- Funnel (strict): 99,441 purchased -> 99,281 approved (99.84%) -> 97,644 handed
-- to carrier (98.19%) -> 96,461 delivered (97.00%) -> 95,815 reviewed (96.35%).
-- Biggest drop: approved -> carrier (1,637 orders, 1.6% of approved), then
-- carrier -> customer (1,183), then delivered -> review (646). Purchase -> approval
-- loses only 160.
-- Of the 1,637: 62% (1,018) are canceled (409) or unavailable (609), stopped before
-- shipping. 615 are invoiced (314) or processing (301), spread from Oct 2016 to
-- Aug 2018, so not just "still in progress". Status cannot tell stuck from never updated.
-- Median times: 0.34 hours to approve, 1.85 days approved -> carrier, 7.10 days
-- carrier -> customer, 2.02 days delivered -> review.
-- Negative gaps (NULL for durations, kept in counts): 0 at approval, 1,359 at
-- carrier, 23 at delivery. 4,769 reviews were answered before the delivery date
-- (not investigated).
-- 2,843 orders have a review but no delivery date. Only 191 of their surveys went
-- out before the estimated delivery date (93% after). Most likely the survey goes
-- out on delivery or once the estimated date passes, so these are mostly customers
-- whose order never arrived: real, not a data error.
-- ============================================================
WITH collapse_review AS (
-- collapse_review: one row per order. MIN keeps the first review answer when an order has several reviews.
    SELECT order_id,
           MIN(review_answer_timestamp) AS first_review
    FROM reviews
    GROUP BY order_id
),
-- comb_table: one row per order (orders LEFT JOIN collapse_review, stays 99,441 rows)
-- with the four stage gaps.
comb_table AS (
    SELECT o.order_id,
    	   o.order_status,
           o.order_purchase_timestamp,
           o.order_approved_at,
           o.order_delivered_carrier_date,
           o.order_delivered_customer_date,
           r.first_review,
-- Stage gaps: hours for approval, days for the rest, each measured from the previous
-- stage (carrier gap from approval, review gap from delivery).
-- The CASE leaves the gap NULL when the later timestamp is earlier than the previous one.
           CASE WHEN o.order_approved_at >= o.order_purchase_timestamp
                THEN EXTRACT(EPOCH FROM (o.order_approved_at - o.order_purchase_timestamp)) / 3600.0
           END AS hours_to_approve,
           CASE WHEN o.order_delivered_carrier_date >= o.order_approved_at
                THEN EXTRACT(EPOCH FROM (o.order_delivered_carrier_date - o.order_approved_at)) / 86400.0
           END AS days_to_carrier,
           CASE WHEN o.order_delivered_customer_date >= o.order_delivered_carrier_date
                THEN EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date)) / 86400.0
           END AS days_to_deliver,
           CASE WHEN r.first_review >= o.order_delivered_customer_date
                THEN EXTRACT(EPOCH FROM (r.first_review - o.order_delivered_customer_date)) / 86400.0
           END AS days_to_review
    FROM orders o
    LEFT JOIN collapse_review r ON r.order_id = o.order_id
),
-- funnel: one row per stage with the strict count (the order needs every earlier
-- timestamp). UNION ALL stacks the five stage counts as rows.
funnel AS (
    SELECT 1 AS stage_no, 'Purchased' AS stage_name, COUNT(order_id) AS orders
    FROM comb_table
    UNION ALL
    SELECT 2, 'Approved', COUNT(order_id)
    FROM comb_table
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_approved_at IS NOT NULL
    UNION ALL
    SELECT 3, 'Delivered_to_carrier', COUNT(order_id)
    FROM comb_table
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_approved_at IS NOT NULL
      AND order_delivered_carrier_date IS NOT NULL
    UNION ALL
    SELECT 4, 'Delivered_to_customer', COUNT(order_id)
    FROM comb_table
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_approved_at IS NOT NULL
      AND order_delivered_carrier_date IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
    UNION ALL
    SELECT 5, 'Reviewed', COUNT(order_id)
    FROM comb_table
    WHERE order_purchase_timestamp IS NOT NULL
      AND order_approved_at IS NOT NULL
      AND order_delivered_carrier_date IS NOT NULL
      AND order_delivered_customer_date IS NOT NULL
      AND first_review IS NOT NULL
)
-- Main output (one row).
-- First five columns: each timestamp counted on its own, so they can differ from the strict
-- counts (carrier 97,658 vs strict 97,644: 14 orders have a carrier date but no approval time).
-- step_1 to step_5: strict funnel counts (same as the funnel CTE).
-- n_ / neg_ / median_ per stage: valid durations, negative gaps, median gap.
SELECT
    COUNT(order_purchase_timestamp)      AS purchase_count,
    COUNT(order_approved_at)             AS approved_count,
    COUNT(order_delivered_carrier_date)  AS carrier_delivery_count,
    COUNT(order_delivered_customer_date) AS customer_delivery_count,
    COUNT(first_review)                  AS reviewed_count,
    COUNT(order_purchase_timestamp)      AS step_1_purchase_count,
    SUM(CASE WHEN order_purchase_timestamp IS NOT NULL
              AND order_approved_at IS NOT NULL
             THEN 1 ELSE 0 END) AS step_2_approved_count,
    SUM(CASE WHEN order_purchase_timestamp IS NOT NULL
              AND order_approved_at IS NOT NULL
              AND order_delivered_carrier_date IS NOT NULL
             THEN 1 ELSE 0 END) AS step_3_carrier_delivery_count,
    SUM(CASE WHEN order_purchase_timestamp IS NOT NULL
              AND order_approved_at IS NOT NULL
              AND order_delivered_carrier_date IS NOT NULL
              AND order_delivered_customer_date IS NOT NULL
             THEN 1 ELSE 0 END) AS step_4_customer_delivery_count,
    SUM(CASE WHEN order_purchase_timestamp IS NOT NULL
              AND order_approved_at IS NOT NULL
              AND order_delivered_carrier_date IS NOT NULL
              AND order_delivered_customer_date IS NOT NULL
              AND first_review IS NOT NULL
             THEN 1 ELSE 0 END) AS step_5_reviewed_count,
    COUNT(hours_to_approve) AS n_approve,
    SUM(CASE WHEN order_approved_at < order_purchase_timestamp THEN 1 ELSE 0 END) AS neg_approve,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hours_to_approve) AS median_hours_to_approve,
    COUNT(days_to_carrier) AS n_carrier,
    SUM(CASE WHEN order_delivered_carrier_date < order_approved_at THEN 1 ELSE 0 END) AS neg_carrier,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_carrier) AS median_days_to_carrier,
    COUNT(days_to_deliver) AS n_deliver,
    SUM(CASE WHEN order_delivered_customer_date < order_delivered_carrier_date THEN 1 ELSE 0 END) AS neg_deliver,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_deliver) AS median_days_to_deliver,
    COUNT(days_to_review) AS n_review,
    SUM(CASE WHEN first_review < order_delivered_customer_date THEN 1 ELSE 0 END) AS review_before_delivery,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_review) AS median_days_to_review
FROM comb_table

-- Peek at the combined table (rows by eye).
SELECT * FROM comb_table

-- CHECK A: orders with a review but no delivery date. How many had the survey sent
-- (review_creation_date) before the estimated delivery date, by order status?
-- Uses the survey creation date; the funnel's review stage uses the answer time.
-- Result: 2,843 orders, only 191 surveys before the estimated date (93% after).
-- Most likely the survey goes out on delivery or once the estimated date passes, so these
-- are mostly customers whose order never arrived. The early 191 are mostly canceled (96)
-- and shipped (71), probably cancellations and unrecorded deliveries. Approved (2) and
-- created (3) are too small to read.
SELECT o.order_status,
       COUNT(*) AS n_orders,
       SUM(CASE WHEN s.first_survey_sent < o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS survey_before_estimated_date
FROM orders o
JOIN (
    SELECT order_id,
           MIN(review_creation_date) AS first_survey_sent
    FROM reviews
    GROUP BY order_id
) s ON s.order_id = o.order_id
WHERE o.order_delivered_customer_date IS NULL
GROUP BY o.order_status
ORDER BY n_orders DESC

-- CHECK B: same orders, other side: surveys sent AFTER the estimated delivery date, by status.
-- Expected: check A's n_orders minus survey_before_estimated_date per status (2,652 in total),
-- unless a survey was created at exactly the estimated date.
SELECT o.order_status,
	   COUNT(o.order_status)
FROM orders o
JOIN (
    SELECT order_id,
           MIN(review_creation_date) AS first_survey_sent
    FROM reviews
    GROUP BY order_id
) s ON s.order_id = o.order_id
WHERE 
	o.order_delivered_customer_date IS NULL AND 
	first_survey_sent > order_estimated_delivery_date
GROUP BY order_status
	

-- CHECK C: status of the 1,637 orders lost between approval and carrier
-- (approved, no carrier date). 62% (1,018) are canceled (409) or unavailable (609): stopped
-- before shipping (status does not say who cancelled). 615 are invoiced or processing (check D).
-- About 4 are delivered or approved: no real data mismatch.
SELECT order_status,COUNT(order_status) FROM comb_table
	WHERE order_approved_at IS NOT NULL AND order_delivered_carrier_date IS NULL
	GROUP BY order_status

-- CHECK D: purchase dates of the invoiced and processing orders from check C.
-- 314 invoiced (Oct 2016 to Aug 2018) and 301 processing (Oct 2016 to Jul 2018), spread across the
-- whole period, not bunched at the end of the data (ends 17 Oct 2018), so not just "still in
-- progress". Status cannot tell stuck from never updated.
SELECT order_status,order_purchase_timestamp FROM comb_table
	WHERE 
		order_approved_at IS NOT NULL AND 
		order_delivered_carrier_date IS NULL AND
		(order_status = 'processing' OR 
		order_status = 'invoiced')
	ORDER BY order_status,order_purchase_timestamp

-- CHECK E: orders with a review but no delivery date, by status (the 2,843 orders from
-- check A, counted without the survey-date condition).
SELECT
order_status, COUNT(order_status)
FROM comb_table
WHERE first_review IS NOT NULL AND
order_delivered_customer_date IS NULL
GROUP BY order_status

-- CHECK F: reviewed orders with no purchase, approval or carrier timestamp.
-- Returns no rows: every order has a purchase timestamp (purchase_count = 99,441).
SELECT * FROM comb_table 
WHERE 
	order_delivered_carrier_date IS NULL AND 
	first_review IS NOT NULL AND 
	order_approved_at IS NULL AND
	order_purchase_timestamp IS NULL

-- Quick look at the stage counts from the funnel CTE.
SELECT * FROM funnel;

-- STAGE TABLE: one row per funnel stage (strict rule: all earlier timestamps present).
-- % of purchased = 100.0 * stage orders / purchased orders (multiplying first keeps integer
-- division from truncating in PostgreSQL). orders_lost = previous stage minus this stage (LAG);
-- NULL for stage 1.
-- Biggest drops: approved -> carrier 1,637; carrier -> customer 1,183; delivered -> review 646.
-- 96.35% of purchased orders end up reviewed.
SELECT
	stage_no,
	stage_name,
	orders,	
	(ROUND((100.0 * orders) /
	(SELECT orders FROM funnel 
		WHERE stage_no = 1)
	,2)) AS "% of purchased",
	(LAG(orders) OVER(
		ORDER BY stage_no
	)) - orders AS orders_lost
FROM funnel