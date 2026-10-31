# Ventas por publicación - Etapa 4

Este documento explica la consulta [`vendedor/ventas-por-publicacion.sql`](../../sql/consultas/vendedor/ventas-por-publicacion.sql), que resuelve el caso de uso [Consultar ventas por publicación](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Resume las [ventas](casos-uso.md#3-qué-se-considera-una-venta) de un vendedor en un rango de fechas, publicación por publicación: cuántas veces se vendió cada una, cuántas unidades y cuánto recaudó. Las publicaciones sin ventas en el período no aparecen. El orden va de mayor a menor recaudación.

## 2. Quién la usa

El **Vendedor**, para saber qué publicaciones le rinden más. Muestra solo sus propios datos, a diferencia de [Total de ventas por vendedor](total-ventas-por-vendedor.md).

## 3. Cómo lo resuelve

- **Vendedor y período:** se indican con `@vendedor_id`, `@fecha_desde` y `@fecha_hasta`. Las fechas se comparan con la de aprobación del pago, que es la [fecha de la venta](casos-uso.md#3-qué-se-considera-una-venta). Como esa fecha incluye la hora, el filtro llega hasta antes del día siguiente a `@fecha_hasta`, para tomar el último día completo.
- **Uniones:** une la publicación con su libro, su condición y los renglones en que se vendió.
- **Ventas:** un `EXISTS` deja solo los renglones de pedidos con un pago aprobado dentro del período.
- **Publicaciones pausadas o dadas de baja:** no se filtran, porque sus ventas siguen contando (RN28).
- **Agrupación:** `GROUP BY` por publicación. `COUNT(*)` cuenta los renglones: como una publicación aparece una sola vez por pedido (RN16), cada renglón es una venta distinta. `SUM` acumula las unidades y la cantidad × precio unitario, con el precio del renglón y no el actual de la publicación (RN26).
- **Orden:** por monto recaudado y, a igual monto, por número de publicación.

## 4. Resultado esperado

Con `@vendedor_id = 25` y el año 2026 completo devuelve 15 publicaciones, entre ellas las dos dadas de baja del vendedor. Las de mayor y menor recaudación son:

| Publicación | Libro                   | Condición  | Ventas | Unidades | Recaudado |
| ----------: | ----------------------- | ---------- | -----: | -------: | --------: |
|          56 | El Señor de los Anillos | Nuevo      |      7 |        8 |  $403.400 |
|         140 | El conde de Montecristo | Nuevo      |      5 |        7 |  $261.800 |
|          33 | Residencia en la tierra | Nuevo      |      6 |        9 |  $198.900 |
|           … |                         |            |        |          |           |
|          68 | Beloved                 | Como nuevo |      1 |        1 |   $14.800 |
|          32 | País de nieve           | Como nuevo |      1 |        1 |   $12.600 |

Las unidades y el monto de las 15 filas suman 65 y $1.714.600, lo mismo que [Total de ventas por vendedor](total-ventas-por-vendedor.md) para este vendedor. Las ventas, en cambio, no se suman: dan 56 frente a 41, porque un pedido con varias de sus publicaciones cuenta una vez en cada publicación, pero una sola en el total del vendedor.
