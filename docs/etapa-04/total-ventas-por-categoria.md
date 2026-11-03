# Total de ventas por categoría - Etapa 4

Este documento explica la consulta [`vendedor-administrador/total-ventas-por-categoria.sql`](../../sql/consultas/vendedor-administrador/total-ventas-por-categoria.sql), que resuelve el caso de uso [Consultar total de ventas por categoría](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Resume las [ventas](casos-uso.md#3-qué-se-considera-una-venta) de cada categoría de libro en un rango de fechas: en cuántos pedidos aparece, cuántas unidades se vendieron y cuánto se recaudó. Las categorías sin ventas en el período no aparecen. El orden va de mayor a menor recaudación.

Un pedido con libros de varias categorías cuenta una vez en cada una, y a cada categoría se le suman solo sus renglones.

El monto recaudado es lo cobrado: el descuento no modifica el total del pedido, pero reduce el importe cobrado (RN32). Por eso, a cada renglón se le resta su parte del descuento del pedido.

## 2. Quién la usa

- **Vendedor:** para saber qué categorías tienen más demanda y decidir qué publicar.
- **Administrador:** para conocer qué áreas del catálogo mueven más ventas.

## 3. Cómo lo resuelve

- **Período:** se indica con `@fecha_desde` y `@fecha_hasta`, y se compara con la fecha de aprobación del pago, que es la [fecha de la venta](casos-uso.md#3-qué-se-considera-una-venta), no con la del pedido. Como esa fecha incluye la hora, el filtro llega hasta antes del día siguiente a `@fecha_hasta`, para tomar el último día completo.
- **Uniones:** va de la categoría a sus libros, de cada libro a sus publicaciones, de cada publicación a los renglones en que se vendió y de cada renglón a su pedido.
- **Ventas:** un `EXISTS` deja solo los pedidos con un pago aprobado dentro del período. La fecha se compara dentro del `EXISTS` porque pertenece al pago: así, el mismo pago aprobado decide si el pedido es una venta y en qué período se cuenta.
- **Agrupación:** `GROUP BY` por categoría. `COUNT(DISTINCT ...)` cuenta cada pedido una sola vez aunque incluya varios libros de la misma categoría; `SUM` acumula las unidades y lo cobrado por cada renglón: la cantidad × precio unitario menos su parte del descuento.
- **Descuento:** un pedido tiene un solo descuento, aunque incluya libros de varias categorías (RN30). `dbo.fn_DescuentoRenglon` lo reparte entre sus renglones en proporción a su subtotal, y redondea de forma acumulada para que las partes sumen exactamente el descuento del pedido. Así, el total del reporte coincide con el importe de los pagos aprobados. La función se crea en [`calcular_descuento_pedido/script.sql`](../../sql/tecnico/procedimientos_funciones/calcular_descuento_pedido/script.sql), de la Etapa 5, que debe ejecutarse antes que esta consulta.

## 4. Resultado esperado

Con el año 2026 completo devuelve 28 de las 30 categorías. Las de mayor y menor recaudación son:

| Categoría        | Pedidos | Unidades |  Recaudado |
| ---------------- | ------: | -------: | ---------: |
| Novela           |     271 |      396 | $9.237.095 |
| Fantasía         |     169 |      232 | $5.950.680 |
| Informática      |      56 |       73 | $4.678.725 |
| …                |         |          |            |
| Biología         |       1 |        1 |    $85.860 |
| Ciencia política |       4 |        4 |    $69.245 |

Las 28 categorías suman $37.816.150, lo mismo que [Total de ventas por vendedor](total-ventas-por-vendedor.md) y que el importe aprobado de [Pagos por método](pagos-por-metodo.md) para 2026.
