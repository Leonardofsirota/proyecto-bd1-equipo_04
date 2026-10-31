# Búsqueda en el catálogo - Etapa 4

Este documento explica la consulta [`cliente/buscar-libros-catalogo.sql`](../../sql/consultas/cliente/buscar-libros-catalogo.sql), que resuelve el caso de uso [Buscar libros en el catálogo](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Busca libros por una parte de su título, de su ISBN o del nombre de alguno de sus autores. De cada libro muestra su ficha, sus autores, cuántas ofertas vigentes tiene y el precio más bajo entre ellas.

También lista los libros sin ofertas vigentes, al final. Si ningún libro coincide con el texto, la consulta no devuelve filas.

## 2. Quién la usa

- **Cliente:** para encontrar un libro y obtener el ID con que se consultan sus [ofertas vigentes](ofertas-vigentes-por-libro.md).
- **Vendedor:** para comprobar si un libro ya está en el catálogo antes de darlo de alta (RN06, RN09).

## 3. Cómo lo resuelve

- **Texto buscado:** se indica con la variable `@texto`. `LIKE` con comodines a ambos lados lo busca en cualquier parte del título, del ISBN o del nombre completo de un autor.
- **Mayúsculas y tildes:** el título y el autor se comparan con la intercalación `Latin1_General_CI_AI`, que no las distingue: «cortazar» encuentra «Cortázar».
- **Autores:** un `EXISTS` busca el texto entre los autores del libro. Otra subconsulta los reúne en una sola columna con `FOR XML PATH` y `STUFF`, porque SQL Server 2012 no tiene `STRING_AGG`.
- **Ofertas vigentes:** una subconsulta agrupa por libro las publicaciones que un cliente puede agregar a un pedido (RN12), con el mismo criterio que [Ofertas vigentes por libro](ofertas-vigentes-por-libro.md): una publicación con todas sus unidades reservadas no cuenta como oferta (RN13, RN33). Por eso usa `dbo.fn_StockLibre`, y [`registrar_venta/script.sql`](../../sql/tecnico/procedimientos_funciones/registrar_venta/script.sql), de la Etapa 5, debe ejecutarse antes que esta consulta. Se une con `LEFT JOIN` para conservar los libros sin ofertas, que muestran cero y ningún precio.
- **Orden:** primero, los libros que se pueden comprar; después, por título y, a igual título, por número de libro.

## 4. Resultado esperado

Con `@texto = 'borges'` devuelve 13 libros, 11 con ofertas vigentes y 2 sin ellas. Los primeros y los últimos son:

| Libro                                 | Autores                                                | Ofertas |   Desde |
| ------------------------------------- | ------------------------------------------------------ | ------: | ------: |
| Antología de la literatura fantástica | Jorge Luis Borges, Silvina Ocampo, Adolfo Bioy Casares |       1 | $22.600 |
| Crónicas de Bustos Domecq             | Jorge Luis Borges, Adolfo Bioy Casares                 |       1 | $12.300 |
| El Aleph                              | Jorge Luis Borges                                      |       3 | $18.100 |
| …                                     |                                                        |         |         |
| El hacedor                            | Jorge Luis Borges                                      |       0 |       — |
| Seis problemas para don Isidro Parodi | Jorge Luis Borges, Adolfo Bioy Casares                 |       0 |       — |
