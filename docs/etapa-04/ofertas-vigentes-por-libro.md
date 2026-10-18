# Ofertas vigentes por libro - Etapa 4

Este documento explica la consulta [`catalogo/ofertas-vigentes-por-libro.sql`](../../sql/consultas/catalogo/ofertas-vigentes-por-libro.sql), que resuelve el caso de uso [Consultar ofertas vigentes por libro](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Muestra las ofertas que hoy se pueden comprar de un libro, de la más barata a la más cara. De cada una indica el vendedor, la condición del ejemplar, el precio y el stock.

Solo aparecen publicaciones activas, con stock y de vendedores que no fueron dados de baja (RN12, RN28). Si el libro no tiene ninguna oferta así, la consulta no devuelve filas.

## 2. Quién la usa

El **Cliente**, antes de armar su pedido. Un mismo libro puede tener ofertas de varios vendedores (RN11), y la consulta le permite elegir según el precio y el estado del ejemplar.

## 3. Cómo lo resuelve

- **Libro elegido:** se indica con la variable `@libro_id`.
- **Uniones:** parte del libro y lo une con sus publicaciones; cada publicación, con su vendedor y su condición.
- **Filtros:** el `WHERE` descarta las ofertas pausadas, dadas de baja, agotadas o de un vendedor dado de baja.
- **Orden:** por precio; a igual precio, por número de publicación, para que el resultado salga siempre en el mismo orden.

## 4. Resultado esperado

Con `@libro_id = 277` (_El hobbit_, tapa blanda) devuelve cinco ofertas:

| Vendedor              | Condición |  Precio | Stock |
| --------------------- | --------- | ------: | ----: |
| Daniel Federico Verón | Bueno     | $11.000 |     1 |
| Romina Torres         | Bueno     | $11.300 |     1 |
| Santiago Fretes       | Nuevo     | $18.900 |     6 |
| Sergio Quintana       | Nuevo     | $22.800 |     5 |
| Valeria Giménez       | Nuevo     | $25.200 |     4 |
