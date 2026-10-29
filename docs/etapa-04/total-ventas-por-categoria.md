# Total de ventas por categoría - Etapa 4

Este documento explica la consulta [`vendedor-administrador/total-ventas-por-categoria.sql`](../../sql/consultas/vendedor-administrador/total-ventas-por-categoria.sql), que resuelve el caso de uso [Consultar total de ventas por categoría](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Resume las [ventas](casos-uso.md#3-qué-se-considera-una-venta) de cada categoría de libro en un rango de fechas: en cuántos pedidos aparece, cuántas unidades se vendieron y cuánto se recaudó. Las categorías sin ventas en el período no aparecen. El orden va de mayor a menor recaudación.

Un pedido con libros de varias categorías cuenta una vez en cada una, y a cada categoría se le suman solo sus renglones.

## 2. Quién la usa

- **Vendedor:** para saber qué categorías tienen más demanda y decidir qué publicar.
- **Administrador:** para conocer qué áreas del catálogo mueven más ventas.

## 3. Cómo lo resuelve

- **Período:** se indica con `@fecha_desde` y `@fecha_hasta`, y se compara con la fecha de aprobación del pago, que es la [fecha de la venta](casos-uso.md#3-qué-se-considera-una-venta), no con la del pedido. Como esa fecha incluye la hora, el filtro llega hasta antes del día siguiente a `@fecha_hasta`, para tomar el último día completo.
- **Uniones:** va de la categoría a sus libros, de cada libro a sus publicaciones, de cada publicación a los renglones en que se vendió y de cada renglón a su pedido.
- **Ventas:** un `EXISTS` deja solo los pedidos con un pago aprobado dentro del período. La fecha se compara dentro del `EXISTS` porque pertenece al pago: así, el mismo pago aprobado decide si el pedido es una venta y en qué período se cuenta.
- **Agrupación:** `GROUP BY` por categoría. `COUNT(DISTINCT ...)` cuenta cada pedido una sola vez aunque incluya varios libros de la misma categoría; `SUM` acumula las unidades y la cantidad × precio unitario de cada renglón.

## 4. Resultado esperado

Con el año 2026 completo devuelve 28 de las 30 categorías. Las de mayor y menor recaudación son:

| Categoría        | Pedidos | Unidades |  Recaudado |
| ---------------- | ------: | -------: | ---------: |
| Novela           |     271 |      396 | $9.426.400 |
| Fantasía         |     169 |      232 | $6.097.700 |
| Informática      |      56 |       73 | $4.910.200 |
| …                |         |          |            |
| Biología         |       1 |        1 |    $95.400 |
| Ciencia política |       4 |        4 |    $70.300 |
