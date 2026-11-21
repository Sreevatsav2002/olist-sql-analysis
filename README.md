# olist-sql-analysis
SQL analysis of Brazilian e-commerce orders, answering business questions on repeat purchases, fulfilment, category revenue and monthly trends (in progress).

## Dataset

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) on Kaggle: 9 related tables covering about 99,000 orders from September 2016 to October 2018. Queries are written in DuckDB SQL, kept portable to PostgreSQL.

## Warm-up: repeat customers

**Question:** What share of customers placed more than one order?

Of 93,358 customers with a delivered order, 2,801 (3.00%) placed more than one order. Excluding only canceled and unavailable orders instead of keeping delivered orders only gives 2,888 of 94,990 customers (3.04%), 87 more repeat customers, so the filter choice barely changes the result. Few customers place a second order, though the data covers a little over two years, so late first-time buyers had little time to return.

**Note:** `customer_id` is created fresh for every order, so a person is identified by `customer_unique_id`. Grouping by `customer_id` would show a 0% repeat rate.

Query: [`00_warmup.sql`](00_warmup.sql)

## Q1: Fulfilment funnel

**Question:** How many orders reach each stage, where do they drop off, and how long does each stage take?

Of 99,441 orders, 95,815 (96.35%) went through every stage to a review. The biggest drop is approval to carrier (1,637 orders, 1.6% of approved orders): 62% were canceled or unavailable, and 615 sat in invoiced or processing across the whole period. Median times: 0.34 hours to approve, 1.85 days to reach the carrier, 7.10 days to deliver and 2.02 days from delivery to review.

Query: [`01_fulfilment_funnel.sql`](01_fulfilment_funnel.sql)