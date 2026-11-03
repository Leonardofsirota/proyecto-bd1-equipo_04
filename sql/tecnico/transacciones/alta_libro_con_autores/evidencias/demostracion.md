# Demostración de `alta_libro_con_autores/demostracion.sql`

- **Fecha:** 2026-11-03 11:00
- **Repetición:** 2026-11-03, enseguida y sobre la misma base: los mismos resultados, con los libros 506 y 507 y la publicación 794 en lugar de 501, 502 y 792.
- **Base temporal:** `tmp_validacion_tx`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más `transacciones/alta_libro_con_autores/script.sql`
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración.

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 28             | 28        | 0        | 0          |

Tablas que escribe la demostración, antes y después de ejecutarla:

| Tabla       | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| ----------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| LIBRO       | 500         | 500           | 2096367084     | 2096367084       | 500                 | 505                   |
| AUTOR       | 362         | 362           | 669763279      | 669763279        | 362                 | 368                   |
| AUTOR_LIBRO | 581         | 581           | 6147           | 6147             | 581                 | 587                   |
| PUBLICACION | 791         | 791           | 1804080490     | 1804080490       | 791                 | 793                   |
| USUARIO     | 500         | 500           | -1321992964    | -1321992964      | 500                 | 504                   |

La limpieza borra todas las filas de la demostración, y `trg_AUTOR_LIBRO_UltimoAutor` queda habilitado (`is_disabled = 0`) antes y después. El ROLLBACK no revierte los valores de IDENTITY consumidos: `LIBRO` avanza 5, uno por cada `INSERT` de los casos 1 a 5, incluidos los revertidos de los casos 3 y 4. `AUTOR` avanza 6: uno en los casos 1 y 4, y dos en los casos 3 y 5, porque el `INSERT` que falla en `uq_autor_isni` también consume un valor. `PUBLICACION` avanza 2: la del caso 1 y la que rechaza `chk_publicacion_precio` en el caso 4.

## Caso 1: alta completa del vendedor

El vendedor registra el ISBN `9990000000001` con dos autores, Borges (existente) y `Autora Demo Uno` (nuevo), y lo publica en condición Nuevo, a 25000.00 y con stock 5.

| libro_id | isbn          | autores | autores_nuevos | publicacion_id | mensaje                                    |
| -------- | ------------- | ------- | -------------- | -------------- | ------------------------------------------ |
| 501      | 9990000000001 | 2       | 1              | 792            | Libro registrado y publicado correctamente |

| Comprobación                  | Esperado                                              | Obtenido                                              | Resultado |
| ----------------------------- | ----------------------------------------------------- | ----------------------------------------------------- | --------- |
| Filas nuevas                  | LIBRO +1 / AUTOR +1 / AUTOR_LIBRO +2 / PUBLICACION +1 | LIBRO +1 / AUTOR +1 / AUTOR_LIBRO +2 / PUBLICACION +1 | OK        |
| `@LibroId` y `@PublicacionId` | coinciden                                             | coinciden                                             | OK        |
| Autores del libro             | existente 1 / nuevo 1                                 | existente 1 / nuevo 1                                 | OK        |
| Publicación                   | disponible 1 / stock 5 / precio 25000.00              | disponible 1 / stock 5 / precio 25000.00              | OK        |

## Caso 2: alta del administrador sin publicación

El administrador registra el ISBN `9990000000002` con Borges y Cortázar, sin publicarlo. La variable `@PublicacionId` llega con el ID 792 del caso 1.

| libro_id | isbn          | autores | autores_nuevos | publicacion_id | mensaje                        |
| -------- | ------------- | ------- | -------------- | -------------- | ------------------------------ |
| 502      | 9990000000002 | 2       | 0              | NULL           | Libro registrado correctamente |

| Comprobación     | Esperado                                              | Obtenido                                              | Resultado |
| ---------------- | ----------------------------------------------------- | ----------------------------------------------------- | --------- |
| Filas nuevas     | LIBRO +1 / AUTOR +0 / AUTOR_LIBRO +2 / PUBLICACION +0 | LIBRO +1 / AUTOR +0 / AUTOR_LIBRO +2 / PUBLICACION +0 | OK        |
| `@PublicacionId` | NULL                                                  | NULL                                                  | OK        |
| `@LibroId`       | coincide                                              | coincide                                              | OK        |

## Caso 3: fallo al insertar un autor nuevo (paso 3)

ISBN `9990000000003`, con dos autores nuevos: `Autor Demo Tres A` y `Autor Demo Tres B`, que trae el ISNI de Borges. El error llega después de insertar el libro y el primer autor, y el ROLLBACK deshace los dos.

| Comprobación                     | Esperado                                              | Obtenido                                              | Resultado |
| -------------------------------- | ----------------------------------------------------- | ----------------------------------------------------- | --------- |
| Error de `uq_autor_isni`         | 2601                                                  | 2601                                                  | OK        |
| Filas nuevas tras el ROLLBACK    | LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0 | LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0 | OK        |
| Libros con el ISBN 9990000000003 | 0                                                     | 0                                                     | OK        |

## Caso 4: fallo al insertar la publicación (paso 5)

ISBN `9990000000004`, con Borges y `Autora Demo Cuatro` (nueva), publicado a precio 0. El error llega en el último paso, con el libro, el autor nuevo y las dos filas de `AUTOR_LIBRO` ya insertados.

| Comprobación                      | Esperado                                              | Obtenido                                              | Resultado |
| --------------------------------- | ----------------------------------------------------- | ----------------------------------------------------- | --------- |
| Error de `chk_publicacion_precio` | 547                                                   | 547                                                   | OK        |
| Filas nuevas tras el ROLLBACK     | LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0 | LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0 | OK        |
| Libro y autor nuevo que quedaron  | libro 0 / autor 0                                     | libro 0 / autor 0                                     | OK        |

## Caso 5: el alta del caso 3 sin transacción

Los mismos `INSERT` del caso 3, ejecutados sueltos: cada uno se confirma por su cuenta. El segundo autor falla igual, pero el libro y el primer autor quedan, y la autoría nunca llega a insertarse.

| Comprobación                               | Esperado                                              | Obtenido                                              | Resultado |
| ------------------------------------------ | ----------------------------------------------------- | ----------------------------------------------------- | --------- |
| Error de `uq_autor_isni`                   | 2601                                                  | 2601                                                  | OK        |
| Filas que quedaron                         | LIBRO +1 / AUTOR +1 / AUTOR_LIBRO +0 / PUBLICACION +0 | LIBRO +1 / AUTOR +1 / AUTOR_LIBRO +0 / PUBLICACION +0 | OK        |
| Libros de la demostración sin autor (RN08) | 1                                                     | 1                                                     | OK        |

## Caso 6: ISBN repetido

El vendedor intenta registrar otra vez el ISBN `9990000000001` del caso 1 (RN06).

| Comprobación  | Esperado | Obtenido | Resultado |
| ------------- | -------- | -------- | --------- |
| ISBN repetido | 50306    | 50306    | OK        |

## Caso 7: validaciones

Salvo el dato indicado, cada llamada es un alta válida de Cortázar con el ISBN `9990000000007`.

| Llamada                                    | Esperado                                              | Obtenido                                              | Resultado |
| ------------------------------------------ | ----------------------------------------------------- | ----------------------------------------------------- | --------- |
| Un cliente registra el libro               | 50301                                                 | 50301                                                 | OK        |
| Un vendedor dado de baja registra el libro | 50301                                                 | 50301                                                 | OK        |
| Lista de autores vacía                     | 50302                                                 | 50302                                                 | OK        |
| Fila con `autor_id` y nombre a la vez      | 50303                                                 | 50303                                                 | OK        |
| `autor_id` inexistente                     | 50304                                                 | 50304                                                 | OK        |
| El mismo autor dos veces                   | 50305                                                 | 50305                                                 | OK        |
| Categoría inexistente                      | 50307                                                 | 50307                                                 | OK        |
| Publicación sin condición                  | 50308                                                 | 50308                                                 | OK        |
| El administrador pide publicar             | 50309                                                 | 50309                                                 | OK        |
| Filas nuevas tras las validaciones         | LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0 | LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0 | OK        |

## Caso 8: transacciones abiertas

`@Abiertas` suma `@@TRANCOUNT` después de cada llamada al procedimiento, también de las que fallaron.

| Comprobación                          | Esperado | Obtenido | Resultado |
| ------------------------------------- | -------- | -------- | --------- |
| Transacciones abiertas tras cada EXEC | 0        | 0        | OK        |
