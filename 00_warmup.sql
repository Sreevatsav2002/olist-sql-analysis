--SET integer_division = true;
WITH order_cus AS(
	SELECT customers.customer_id,customer_unique_id,order_id,order_status FROM orders
	INNER JOIN customers
	ON orders.customer_id = customers.customer_id
	WHERE (order_status != 'canceled' AND order_status != 'unavailable') 
	OR order_status IS NULL
--	WHERE order_status = 'delivered'
),
unique_count AS(
SELECT customer_unique_id,COUNT(order_id) AS total_count
FROM order_cus
GROUP BY customer_unique_id
)

SELECT ROUND(AVG(
CASE
	WHEN total_count > 1 THEN 1
	ELSE 0
END 
)*100,2) AS repeat_percent,SUM(
CASE
	WHEN total_count > 1 THEN 1
	ELSE 0
END 
) AS repeat_count, COUNT(*) AS total FROM unique_count

--SELECT * FROM (VALUES ('delivered'), ('canceled'), (NULL)) AS t(status)
--WHERE status != 'canceled' OR status IS NULL;
SELECT MIN(order_purchase_timestamp), MAX(order_purchase_timestamp) FROM orders;       