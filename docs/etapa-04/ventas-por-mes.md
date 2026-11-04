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
- **Agrupación:** `GROUP BY` por año y mes de la fecha de aprobación, así cada venta se cuenta en el mes en que se aprobó su pago. `COUNT(DISTINCT ...)` cuenta cada pedido una sola vez aunque tenga varios renglones; `SUM` acumula las unidades y lo cobrado por cada renglón: la cantidad × precio unitario menos su parte del descuento del pedido.
- **Descuento:** el descuento no modifica el total del pedido, pero reduce el importe cobrado (RN32). `dbo.fn_DescuentoRenglon` calcula la parte de cada renglón, igual que en [Total de ventas por vendedor](total-ventas-por-vendedor.md), y las partes de un pedido suman exactamente su descuento. Así, lo recaudado en un mes coincide con el importe de los pagos aprobados en ese mes. La función se crea en [`calcular_descuento_pedido/script.sql`](../../sql/tecnico/procedimientos_funciones/calcular_descuento_pedido/script.sql), de la Etapa 5, que debe ejecutarse antes que esta consulta.
- **Promedio:** divide el monto recaudado del mes por su cantidad de ventas.

## 4. Resultado esperado

Con el año 2026 completo devuelve los 12 meses:

| Mes        | Ventas | Unidades |  Recaudado | Promedio por venta |
| ---------- | -----: | -------: | ---------: | -----------------: |
| Enero      |     33 |       79 | $1.518.305 |         $46.009,24 |
| Febrero    |     45 |       97 | $2.296.920 |         $51.042,67 |
| Marzo      |     66 |      188 | $5.523.440 |         $83.688,48 |
| Abril      |     45 |      124 | $2.948.630 |         $65.525,11 |
| Mayo       |     47 |      119 | $2.833.735 |         $60.292,23 |
| Junio      |     40 |       92 | $2.435.710 |         $60.892,75 |
| Julio      |     54 |      136 | $3.537.430 |         $65.507,96 |
| Agosto     |     46 |      112 | $3.082.525 |         $67.011,41 |
| Septiembre |     45 |      115 | $3.691.300 |         $82.028,89 |
| Octubre    |     46 |      123 | $3.063.175 |         $66.590,76 |
| Noviembre  |     46 |      119 | $3.605.830 |         $78.387,61 |
| Diciembre  |     54 |      127 | $3.279.150 |         $60.725,00 |

Las 567 ventas del año son los pedidos que lista [Pedidos con pago aprobado](pedidos-con-pago-aprobado.md), y suman $37.816.150, lo mismo que los importes de sus pagos.
