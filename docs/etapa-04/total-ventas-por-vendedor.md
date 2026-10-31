# Total de ventas por vendedor - Etapa 4

Este documento explica la consulta [`administrador/total-ventas-por-vendedor.sql`](../../sql/consultas/administrador/total-ventas-por-vendedor.sql), que resuelve el caso de uso [Consultar total de ventas por vendedor](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Resume las [ventas](casos-uso.md#3-qué-se-considera-una-venta) de cada vendedor en un rango de fechas: cuántas ventas tuvo, cuántos libros vendió y cuánto recaudó. Los vendedores sin ventas en el período no aparecen. El orden va de menor a mayor recaudación.

Un pedido con libros de varios vendedores (RN16) cuenta como una venta para cada uno, y a cada vendedor se le suman solo sus renglones.

## 2. Quién la usa

El **Administrador**, para comparar el desempeño de los vendedores del marketplace. Como muestra las ventas de todos, no está pensada para un vendedor: cada uno consulta las suyas en [Ventas por publicación](ventas-por-publicacion.md).

## 3. Cómo lo resuelve

- **Período:** se indica con `@fecha_desde` y `@fecha_hasta`, y se compara con la fecha de aprobación del pago, que es la [fecha de la venta](casos-uso.md#3-qué-se-considera-una-venta), no con la del pedido. Como esa fecha incluye la hora, el filtro llega hasta antes del día siguiente a `@fecha_hasta`, para tomar el último día completo.
- **Uniones:** va del vendedor a sus publicaciones, de cada publicación a los renglones en que se vendió y de cada renglón a su pedido.
- **Ventas:** un `EXISTS` deja solo los pedidos con un pago aprobado dentro del período. La fecha se compara dentro del `EXISTS` porque pertenece al pago: así, el mismo pago aprobado decide si el pedido es una venta y en qué período se cuenta.
- **Agrupación:** `GROUP BY` por vendedor. `COUNT(DISTINCT ...)` cuenta cada pedido una sola vez aunque incluya varios libros del mismo vendedor; `SUM` acumula las unidades y la cantidad × precio unitario de cada renglón.

## 4. Resultado esperado

Con el año 2026 completo devuelve los 40 vendedores. Los extremos son:

| Vendedor        | Ventas | Libros vendidos | Recaudado  |
| --------------- | -----: | --------------: | ---------: |
| Germán Villordo |      1 |               2 |    $29.800 |
| Verónica Ramos  |      2 |               2 |    $45.000 |
| …               |        |                 |            |
| Paola Recalde   |     33 |              56 | $3.630.900 |
| Lucía Romero    |     96 |             170 | $4.464.800 |
