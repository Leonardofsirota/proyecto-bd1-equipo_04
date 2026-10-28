# Libros más vendidos - Etapa 4

Este documento explica la consulta [`ventas/libros-mas-vendidos.sql`](../../sql/consultas/ventas/libros-mas-vendidos.sql), que resuelve el caso de uso [Consultar libros más vendidos](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Lista los libros con al menos 3 unidades vendidas, con el total de unidades y el monto recaudado, del más vendido al menos vendido. Suma las [ventas](casos-uso.md#3-qué-se-considera-una-venta) de todas las ofertas del libro, sin importar el vendedor ni la condición del ejemplar. No tiene rango de fechas: abarca todas las ventas registradas.

## 2. Quién la usa

- **Vendedor:** para saber qué títulos conviene publicar o reponer.
- **Administrador:** para conocer qué libros del catálogo tienen más salida.

## 3. Cómo lo resuelve

- **Uniones:** va del libro a sus publicaciones y de cada publicación a los renglones en que se vendió.
- **Ventas:** un `EXISTS` deja solo los renglones de pedidos con pago aprobado.
- **Agrupación:** `GROUP BY` por libro; `SUM` acumula las unidades y la cantidad × precio unitario de cada renglón.
- **Mínimo de unidades:** `HAVING SUM(cantidad) >= 3`. Va en el `HAVING` y no en el `WHERE` porque filtra por un valor que recién existe después de agrupar.
- **Orden:** por unidades vendidas; a igual cantidad, por monto recaudado.

## 4. Resultado esperado

Devuelve 113 libros. Los tres primeros son:

| Libro                                   | Unidades |  Recaudado |
| --------------------------------------- | -------: | ---------: |
| Harry Potter y el prisionero de Azkaban |       65 | $1.795.800 |
| La metamorfosis                         |       63 | $1.031.100 |
| El hobbit                               |       62 | $1.265.900 |
