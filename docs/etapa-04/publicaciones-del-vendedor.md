# Publicaciones del vendedor - Etapa 4

Este documento explica la consulta [`vendedor/publicaciones-del-vendedor.sql`](../../sql/consultas/vendedor/publicaciones-del-vendedor.sql), que resuelve el caso de uso [Consultar publicaciones del vendedor](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Lista todas las publicaciones de un vendedor, con el libro, la condición, el precio, el stock y el estado. Van de menor a mayor stock, y las dadas de baja, al final. Si el vendedor no tiene publicaciones, la consulta no devuelve filas.

## 2. Quién la usa

El **Vendedor**, para saber qué reponer y qué publicaciones no ven los clientes. Solo las activas pueden agregarse a un pedido (RN12).

## 3. Cómo lo resuelve

- **Vendedor elegido:** se indica con la variable `@vendedor_id`.
- **Uniones:** une la publicación con su libro y su condición.
- **Sin filtros de estado:** muestra todas las publicaciones, también las pausadas y las dadas de baja, que se conservan (RN28).
- **Estado:** un `CASE` lo deduce de la fecha de baja, el stock y la disponibilidad, en ese orden. Una publicación sin stock figura como agotada aunque además esté pausada, porque para volver a venderla primero hay que reponer stock.
- **Stock:** es el stock real de la publicación. No resta las unidades reservadas por pedidos pendientes (RN33).
- **Orden:** otro `CASE` deja las dadas de baja al final. El resto va de menor a mayor stock, y a igual stock, por número de publicación.

## 4. Resultado esperado

Con `@vendedor_id = 25` devuelve 21 publicaciones: 13 activas, 4 agotadas, 2 pausadas y 2 dadas de baja. Las primeras y las últimas son:

| Publicación | Libro                     | Condición  |  Precio | Stock | Estado       |
| ----------: | ------------------------- | ---------- | ------: | ----: | ------------ |
|          32 | País de nieve             | Como nuevo | $14.500 |     0 | Agotada      |
|          33 | Residencia en la tierra   | Nuevo      | $23.500 |     0 | Agotada      |
|          68 | Beloved                   | Como nuevo | $16.300 |     0 | Agotada      |
|         140 | El conde de Montecristo   | Nuevo      | $45.700 |     0 | Agotada      |
|         436 | Crónicas de Bustos Domecq | Muy bueno  | $12.300 |     2 | Activa       |
|           … |                           |            |         |       |              |
|           9 | Sobre héroes y tumbas     | Nuevo      | $26.600 |     8 | Dada de baja |
|         434 | La pregunta de sus ojos   | Nuevo      | $22.100 |    11 | Dada de baja |
