/*nivel 1 ejercicio 1*/
SELECT TA.id_transaction, CO.country,DATE((TA.timestamp)) 
FROM `string3-laurajuan.string3_silver.transactions_clean ` AS TA
INNER JOIN `string3-laurajuan.string3_silver.companies_clean` AS CO ON CO.company_id = TA.business_id
WHERE DATE((TA.timestamp)) = '2022-03-12' AND  CO.country ='Germany';



/*nivel 1 ejercicio 2.1*/
CREATE OR REPLACE TABLE `string3-laurajuan.string3_silver.transactions_recent` AS  
(
  
  SELECT
  id_transaction, 
  amount, 
  lat, 
  longitude, 
  id_products, 
  card_id, 
  business_id, 
  user_id, 
  declined,
  TIMESTAMP_SUB(
          CURRENT_TIMESTAMP(),INTERVAL CAST((RAND()*50)AS INT64) DAY) AS fecha_aleatoria
  
  FROM `string3-laurajuan.string3_silver.transactions_clean ` 

);



/*nivel 1 ejercicio 2.2*/
CREATE OR REPLACE TABLE `string3-laurajuan.string3_gold.fact_transactions_optimized`
PARTITION BY DATE(fecha_aleatoria)
CLUSTER BY business_id
AS (
  SELECT * 
  FROM `string3-laurajuan.string3_silver.transactions_recent`
);



/*nivel 1 ejercicio 3*/
SELECT * 
FROM `string3-laurajuan.string3_silver.transactions_recent` 
WHERE fecha_aleatoria > TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 30 DAY);  /* CONSUMO DE 5,77MB*/

SELECT *
FROM `string3-laurajuan.string3_gold.fact_transactions_optimized` 
WHERE fecha_aleatoria >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 30 DAY);  /* CONSUMO DE 11,85MB*/





/*nivel 1 ejercicio 4*/
CREATE OR REPLACE MATERIALIZED VIEW `string3-laurajuan.string3_gold.mv_daily_sales`
AS (
SELECT DATE(timestamp) AS DIAS,
SUM(ROUND(amount)) AS VENTAS_TOTAL,
FROM `string3-laurajuan.string3_silver.transactions_clean `
GROUP BY DIAS);

SELECT * FROM `string3-laurajuan.string3_gold.mv_daily_sales` ORDER BY DIAS DESC




/*nivel 2 ejercicio 1*/
WITH VIP_STATS AS 
(SELECT
user_id AS USUARIOS, 
ROUND(SUM(amount),2) as GASTO_TOTAL,
COUNT(id_transaction) as CANTIDAD_TRASACCIONES,
ROUND(AVG(amount),2) as GASTO_PROMEDIO,
ROUND(MAX(amount),2) as GASTO_MAXIMO
FROM `string3-laurajuan.string3_silver.transactions_clean `
GROUP BY USUARIOS
)


SELECT 
US.user_id, 
US.name, 
US.surname,
US.email,
US.phone,
US.country,
V.CANTIDAD_TRASACCIONES,
V.GASTO_PROMEDIO,
V.GASTO_MAXIMO,
V.GASTO_TOTAL,
FROM VIP_STATS AS V
INNER JOIN `string3-laurajuan.string3_silver.users_clean` AS US
ON US.user_id = V.USUARIOS
WHERE GASTO_TOTAL > 500
ORDER BY GASTO_TOTAL DESC;




/*nivel 2 ejercicio 2*/
WITH ventas AS 
(SELECT 
  DIAS,
  VENTAS_TOTAL AS VENTA_DIA,
  LAG(VENTAS_TOTAL) OVER (ORDER BY DIAS) AS VENTA_DIA_ANTERIOR,
FROM `string3-laurajuan.string3_gold.mv_daily_sales`
ORDER BY DIAS ASC)

SELECT 
  DIAS,
  VENTA_DIA,
  VENTA_DIA_ANTERIOR,
  ROUND(((VENTA_DIA - VENTA_DIA_ANTERIOR)/VENTA_DIA_ANTERIOR)*100,2) AS PORCENTAJE_VARIACION
FROM ventas;




/*nivel 2 ejercicio 3*/
SELECT 
  DIAS, 
  ROUND(VENTAS_TOTAL,2) AS VENTAS_TOTAL,
  SUM(VENTAS_TOTAL) OVER (
    PARTITION BY EXTRACT(YEAR FROM DIAS)
    ORDER BY DIAS
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS VENTA_ACUMULADA

 FROM `string3-laurajuan.string3_gold.mv_daily_sales` 
 ORDER BY DIAS




/*nivel 2 ejercicio 4*/
WITH TABLA AS (
  
  SELECT 
  US.user_id AS USUARI, 
  US.name AS NOM, 
  US.surname AS COGNOM, 
  US.email AS EMAIL,
  DATE(TA.timestamp) AS FECHA, 
  TA.amount AS IMPORT,
  ROUND (AVG(TA.amount) OVER(PARTITION BY US.user_id),2) AS MEDIA_TRANS_USUARI,
  ROW_NUMBER () OVER( 
    PARTITION BY US.user_id 
    ORDER BY DATE(timestamp)) AS RANKING_TRASACCIONES
  FROM `string3-laurajuan.string3_silver.users_clean` AS US
  INNER JOIN `string3-laurajuan.string3_silver.transactions_clean ` AS TA
  ON US.user_id = TA.user_id
  QUALIFY RANKING_TRASACCIONES IN (1,2,3)
  ORDER BY US.user_id)

SELECT 
  USUARI,
  NOM,
  COGNOM,
  EMAIL,
  FECHA,
  IMPORT,
  MEDIA_TRANS_USUARI,
FROM TABLA
WHERE RANKING_TRASACCIONES = 3;




/*nivel 3 ejercicio 1*/
CREATE OR REPLACE TABLE `string3-laurajuan.string3_gold.dim_transactions_flat` 
AS (
SELECT 
  TA.id_transaction,
  TA.timestamp,
  TA.amount AS TOTAL_TICKET , 
  SAFE_CAST(lista AS INT64) AS ID_PRODUCTO, /* DEJO LA COLUMNA PARA COMPROVACIONES MIAS*/
  PR.product_name, 
  PR.price,
FROM `string3-laurajuan.string3_silver.transactions_clean ` AS TA,
  UNNEST(id_products) AS LISTA
INNER JOIN `string3-laurajuan.string3_silver.products_clean` AS PR
ON LISTA = PR.id_product
)





/*nivel 3 ejercicio 2*/
SELECT ID_PRODUCTO, product_name, COUNT(id_transaction) AS UNIDADES_VENDIDAS
FROM `string3-laurajuan.string3_gold.dim_transactions_flat` 
GROUP BY ID_PRODUCTO, product_name
ORDER BY UNIDADES_VENDIDAS DESC
LIMIT 5




/*nivel 3 ejercicio 3*/
CREATE OR REPLACE FUNCTION `string3-laurajuan.string3_gold.calculate_tax` 
(amount FLOAT64)
RETURNS FLOAT64
AS (amount*1.21);


CREATE OR REPLACE TABLE `string3-laurajuan.string3_gold.dim_transactions_flat` 
AS (
SELECT 
  TA.id_transaction,
  TA.timestamp,
  TA.amount AS TOTAL_TICKET , 
  SAFE_CAST(lista AS INT64) AS ID_PRODUCTO, /* DEJO LA COLUMNA PARA COMPROVACIONES MIAS*/
  PR.product_name, 
  PR.price,
  ROUND (SAFE_CAST( `string3-laurajuan.string3_gold.calculate_tax` (PR.price) AS FLOAT64),2) AS product_price_tax_inc
FROM `string3-laurajuan.string3_silver.transactions_clean ` AS TA,
  UNNEST(id_products) AS LISTA
INNER JOIN `string3-laurajuan.string3_silver.products_clean` AS PR
ON LISTA = PR.id_product

);