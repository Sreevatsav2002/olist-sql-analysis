# olist-sql-analysis
SQL analysis of Brazilian e-commerce orders, answering business questions on repeat purchases, fulfilment, category revenue and monthly trends (in progress).

## Dataset

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) on Kaggle: 9 related tables covering about 99,000 orders from September 2016 to October 2018. Queries are written in DuckDB SQL, kept portable to PostgreSQL.

## Warm-up: repeat customers

**Question:** What share of customers placed more than one order?

Of 93,358 customers with a delivered order, 2,801 (3.00%) placed more than one order. Excluding only canceled and unavailable orders instead of keeping delivered orders only gives 2,888 of 94,990 customers (3.04%), 87 more repeat customers, so the filter choice barely changes the result. Few customers place a second order, though the data covers a little over two years, so late first-time buyers had little time to return; the next question therefore tests whether a first order delivered later than its estimated date, or given a low review score, is linked to not returning.

**Note:** `customer_id` is created fresh for every order, so a person is identified by `customer_unique_id`. Grouping by `customer_id` would show a 0% repeat rate.

Query: [`00_warmup.sql`](00_warmup.sql)
