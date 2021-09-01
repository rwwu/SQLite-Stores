/*
Customers: customer data
	-Primary: customerNumber
	-Foreign: salesRepEmployeeNumber -> employees.employeeNumber
Employees: all employee information
	-Primary: employeeNumber
	-Foreign: officeCode -> offices.officeCode
			  reportsTo -> employees.employeeNumber
Offices: sales office information
	-Primary: officeCode
Orders: customers' sales orders
	-Primary: orderNumber
	-Foreign: customerNumber -> customers.customerNumber
OrderDetails: sales order line for each sales order
	-Primary: orderNumber, productCode
	-Foreign: orderNumber -> orders.orderNumber
		      productCode -> products.productCode
Payments: customers' payment records
	-Primary: customerNumber, checkNumber
	-Foreign: customerNumber
Products: a list of scale model cars
	-Primary: productCode
	-Foreign: productLine -> productlines.productLine
ProductLines: a list of product line categories
	-Primary: productLine
*/

-- Which products do we need more of?
WITH product_ratio AS (
-- Identify products with highest ratio of quantity ordered to quantity in stock
	SELECT p.productName, p.productCode, p.productLine, (CAST(SUM(o.quantityOrdered) AS REAL) / p.quantityInStock) as quantity_ratio
	FROM products AS p
	JOIN orderdetails AS o
	ON p.productCode = o.productCode
	GROUP BY p.productName, p.productCode
	ORDER BY quantity_ratio DESC
),
performance AS (
-- Identity the products that have generated the most revenue
	SELECT o.productCode, SUM(o.quantityOrdered * o.priceEach) as product_performance
	FROM orderdetails AS o
	GROUP BY o.productCode
	ORDER BY product_performance DESC
)
-- Identity products that should be prioritize for restocking
SELECT pr.productName, pr.productCode, pr.productLine
FROM product_ratio AS pr
WHERE pr.productCode IN (
	SELECT p.productCode
	FROM performance AS p
	)
LIMIT 10;
	
-- Do we need to spend more money to acquire new customers?
-- We need to find the number of new costumers per month
WITH payment_with_year_month_table AS (
SELECT *, CAST(SUBSTR(paymentDate, 1,4) AS INTEGER)*100 + CAST(SUBSTR(paymentDate, 6,7) AS INTEGER) AS year_month
FROM payments p
),
customers_by_month_table AS (
SELECT p1.year_month, COUNT(*) AS number_of_customers, SUM(p1.amount) AS total
FROM payment_with_year_month_table p1
GROUP BY p1.year_month
),
new_customers_by_month_table AS (
-- Identify the number of new customers and their spending per month in addition to the total number of customers and their spending per month
SELECT p1.year_month, COUNT(*) AS number_of_new_customers, SUM(p1.amount) AS new_customer_total,
	(SELECT number_of_customers
	FROM customers_by_month_table c
	WHERE c.year_month = p1.year_month) AS number_of_customers,
	(SELECT total
	FROM customers_by_month_table c
	WHERE c.year_month = p1.year_month) AS total
FROM payment_with_year_month_table p1
WHERE p1.customerNumber NOT IN 
	(SELECT customerNumber
	FROM payment_with_year_month_table p2
	WHERE p2.year_month < p1.year_month)
GROUP BY p1.year_month
)
-- Compare percentage of new customers to total customer base and new customer amount to total customer amount
SELECT ROUND(SUM(number_of_new_customers)*100/SUM(number_of_customers),1) AS number_of_new_customers_percent, 
	   ROUND(SUM(new_customer_total)*100/SUM(total),1) AS new_customers_total_amount_percent
FROM new_customers_by_month_table;

/* We see that new customers make up 55% of our total customer base and make up a similar proportion of our total revenue.
Therefore, it is definitely worthwhile to spend more money to acquire new customers. */
	
-- How much money should we spend to acquire new customers?
WITH customer_profits AS(
 -- Create a table to identify customer and the profits from their orders
	SELECT o.customerNumber, SUM(od.quantityOrdered * (od.priceEach - p.buyprice)) AS profit
	FROM orders AS o
	JOIN orderdetails AS od
	ON o.orderNumber = od.orderNumber
	JOIN products AS p
	ON od.productCode = p.productCode
	WHERE o.status in ('Shipped', 'Resolved', 'In Process')
	GROUP BY o.customerNumber
),
most_profitable_customers AS (
-- Identify the 5 most profitable customers and their information
	SELECT c.customerName, c.customerNumber, c.contactLastName, c.contactFirstName, c.city, c.country, cp.profit
	FROM customer_profits AS cp
	JOIN customers AS c
	ON cp.customerNumber = c.customerNumber
	ORDER BY cp.profit DESC
	LIMIT 5
),
least_profitable_customers AS (
-- Identify the 5 least profitable customers and their information
	SELECT c.customerName, c.customerNumber, c.contactLastName, c.contactFirstName, c.city, c.country, cp.profit
	FROM customer_profits AS cp
	JOIN customers AS c
	ON cp.customerNumber = c.customerNumber
	ORDER BY cp.profit ASC
	LIMIT 5
)
-- Identify average profit per customer
SELECT AVG(profit)
FROM customer_profits;

/* The average profit per customer is $37,198. Therefore we should should not spend more than $37,198 per customer.