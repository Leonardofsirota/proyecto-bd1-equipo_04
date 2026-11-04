# Ofertas vigentes por libro - Etapa 4

Este documento explica la consulta [`cliente/ofertas-vigentes-por-libro.sql`](../../sql/consultas/cliente/ofertas-vigentes-por-libro.sql), que resuelve el caso de uso [Consultar ofertas vigentes por libro](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Muestra las ofertas que hoy se pueden comprar de un libro, de la más barata a la más cara. De cada una indica el vendedor, la condición del ejemplar, el precio y el stock libre.

Solo aparecen publicaciones activas, con stock libre y de vendedores que no fueron dados de baja (RN12, RN13, RN28). Si el libro no tiene ninguna oferta así, la consulta no devuelve filas.

## 2. Quién la usa

El **Cliente**, antes de armar su pedido. Un mismo libro puede tener ofertas de varios vendedores (RN11), y la consulta le permite elegir según el precio y el estado del ejemplar. El ID del libro se obtiene en [Buscar libros en el catálogo](buscar-libros-catalogo.md).

## 3. Cómo lo resuelve

- **Libro elegido:** se indica con la variable `@libro_id`.
- **Uniones:** parte del libro y lo une con su encuadernación y sus publicaciones; cada publicación, con su vendedor y su condición.
- **Filtros:** el `WHERE` descarta las ofertas pausadas, dadas de baja, sin stock libre o de un vendedor dado de baja.
- **Stock libre:** lo calcula `dbo.fn_StockLibre`: el stock real de la publicación menos las unidades de las reservas vigentes (RN33). Es el mismo cálculo con que se valida un pedido al crearlo (RN13), así que una oferta con todas sus unidades reservadas no aparece, y vuelve a aparecer si la reserva vence (RN35). La función se crea en [`registrar_venta/script.sql`](../../sql/tecnico/procedimientos_funciones/registrar_venta/script.sql), de la Etapa 5, que debe ejecutarse antes que esta consulta.
- **Orden:** por precio; a igual precio, por número de publicación, para que el resultado salga siempre en el mismo orden.

## 4. Resultado esperado

Con `@libro_id = 277` (_El hobbit_, tapa blanda) devuelve cinco ofertas. Los datos de prueba no tienen reservas vigentes, así que el stock libre coincide con el real:

| Vendedor              | Condición |  Precio | Stock libre |
| --------------------- | --------- | ------: | ----------: |
| Daniel Federico Verón | Bueno     | $11.000 |           1 |
| Romina Torres         | Bueno     | $11.300 |           1 |
| Santiago Fretes       | Nuevo     | $18.900 |           6 |
| Sergio Quintana       | Nuevo     | $22.800 |           5 |
| Valeria Giménez       | Nuevo     | $25.200 |           4 |
