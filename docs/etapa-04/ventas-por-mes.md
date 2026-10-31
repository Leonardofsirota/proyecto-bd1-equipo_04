# Ventas por mes - Etapa 4

Este documento explica la consulta [`vendedor-administrador/ventas-por-mes.sql`](../../sql/consultas/vendedor-administrador/ventas-por-mes.sql), que resuelve el caso de uso [Consultar ventas por mes](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Muestra la evolución de las [ventas](casos-uso.md#3-qué-se-considera-una-venta) del marketplace en un rango de fechas: por cada mes, la cantidad de ventas, las unidades vendidas, el monto recaudado y el promedio por venta. Va del mes más antiguo al más reciente, y los meses sin ventas no aparecen.

## 2. Quién la usa

- **Vendedor:** para conocer qué meses tienen más demanda. No identifica a ningún vendedor ni cliente.
- **Administrador:** para seguir la evolución de la recaudación del marketplace.

## 3. Cómo lo resuelve

- **Período:** se indica con `@fecha_desde` y `@fecha_hasta`, y se compara con la fecha de aprobación del pago, que es la [fecha de la venta](casos-uso.md#3-qué-se-considera-una-venta). Como esa fecha incluye la hora, el filtro llega hasta antes del día siguiente a `@fecha_hasta`, para tomar el último día completo.
- **Uniones:** une los renglones con su pago y el estado de ese pago, y el `WHERE` deja solo el aprobado. A diferencia de los otros reportes, no usa `EXISTS`, porque necesita agrupar por la fecha del pago. Como un pedido tiene a lo sumo un pago aprobado (RN24), los renglones no se duplican.
- **Agrupación:** `GROUP BY` por año y mes de la fecha de aprobación, así cada venta se cuenta en el mes en que se aprobó su pago. `COUNT(DISTINCT ...)` cuenta cada pedido una sola vez aunque tenga varios renglones; `SUM` acumula las unidades y la cantidad × precio unitario.
- **Promedio:** divide el monto recaudado del mes por su cantidad de ventas.

## 4. Resultado esperado

Con el año 2026 completo devuelve los 12 meses:

| Mes        | Ventas | Unidades |  Recaudado | Promedio por venta |
| ---------- | -----: | -------: | ---------: | -----------------: |
| Enero      |     33 |       79 | $1.543.700 |         $46.778,79 |
| Febrero    |     45 |       97 | $2.330.000 |         $51.777,78 |
| Marzo      |     66 |      188 | $5.757.900 |         $87.240,91 |
| Abril      |     45 |      124 | $3.011.700 |         $66.926,67 |
| Mayo       |     47 |      119 | $2.887.300 |         $61.431,91 |
| Junio      |     40 |       92 | $2.483.200 |         $62.080,00 |
| Julio      |     54 |      136 | $3.607.400 |         $66.803,70 |
| Agosto     |     46 |      112 | $3.157.800 |         $68.647,83 |
| Septiembre |     45 |      115 | $3.812.600 |         $84.724,44 |
| Octubre    |     46 |      123 | $3.145.900 |         $68.389,13 |
| Noviembre  |     46 |      119 | $3.759.700 |         $81.732,61 |
| Diciembre  |     54 |      127 | $3.341.800 |         $61.885,19 |

Las 567 ventas del año son los pedidos que lista [Pedidos con pago aprobado](pedidos-con-pago-aprobado.md), y suman $38.839.000.
