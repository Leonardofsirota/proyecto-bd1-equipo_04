# Demostración: alta de un libro con sus autores en una transacción

Prueba `usp_RegistrarLibroConAutores`, que registra en una sola transacción el libro, sus autores nuevos, la autoría y, si lo pide un vendedor, la primera publicación. Así se cumple que todo libro tenga al menos un autor (RN08), y el procedimiento valida el ISBN único (RN06), la clasificación (RN07), quién puede dar de alta un libro (RN09) y quién puede publicarlo (RN10). La demostración trabaja con libros, autores y publicaciones propios, y los borra al terminar.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **28 de 28** comprobaciones correctas

## Resumen

| Caso | Qué se prueba                             | Comprobaciones | Resultado |
| ---- | ----------------------------------------- | -------------- | --------- |
| 1    | Alta completa del vendedor                | 4              | OK        |
| 2    | Alta del administrador sin publicación    | 3              | OK        |
| 3    | Fallo al insertar un autor nuevo (paso 3) | 3              | OK        |
| 4    | Fallo al insertar la publicación (paso 5) | 3              | OK        |
| 5    | El alta del caso 3 sin transacción        | 3              | OK        |
| 6    | ISBN repetido                             | 1              | OK        |
| 7    | Validaciones                              | 10             | OK        |
| 8    | Transacciones abiertas tras cada llamada  | 1              | OK        |

Las tablas de filas nuevas muestran cuántas filas sumó cada tabla durante el caso.

## Caso 1: alta completa del vendedor

El vendedor registra un libro con dos autores, Borges, que ya existe, y una autora nueva, y lo publica en condición Nuevo, a 25000.00 y con stock 5. El procedimiento inserta el libro, la autora, las dos autorías y la publicación, y devuelve en sus variables de salida el libro y la publicación creados.

| Autores | Autores nuevos | Publicado | Mensaje                                    |
| ------- | -------------- | --------- | ------------------------------------------ |
| 2       | 1              | Sí        | Libro registrado y publicado correctamente |

| Filas nuevas | LIBRO | AUTOR | AUTOR_LIBRO | PUBLICACION | Resultado |
| ------------ | ----- | ----- | ----------- | ----------- | --------- |
| Tras el alta | +1    | +1    | +2          | +1          | OK        |

| Comprobación                                                               | Valor                                 | Resultado |
| -------------------------------------------------------------------------- | ------------------------------------- | --------- |
| `@LibroId` y `@PublicacionId`, iguales al libro y a la publicación creados | coinciden                             | OK        |
| Autores del libro                                                          | 1 existente y 1 nuevo                 | OK        |
| Publicación                                                                | disponible, stock 5 y precio 25000.00 | OK        |

## Caso 2: alta del administrador sin publicación

El administrador registra un libro con Borges y Cortázar, sin publicarlo. La variable de salida de la publicación llegaba con el valor del caso 1, y el procedimiento la dejó en NULL: no arrastra la publicación de una llamada anterior.

| Autores | Autores nuevos | Publicado | Mensaje                        |
| ------- | -------------- | --------- | ------------------------------ |
| 2       | 0              | No        | Libro registrado correctamente |

| Filas nuevas | LIBRO | AUTOR | AUTOR_LIBRO | PUBLICACION | Resultado |
| ------------ | ----- | ----- | ----------- | ----------- | --------- |
| Tras el alta | +1    | +0    | +2          | +0          | OK        |

| Comprobación                      | Valor    | Resultado |
| --------------------------------- | -------- | --------- |
| `@PublicacionId`                  | NULL     | OK        |
| `@LibroId`, igual al libro creado | coincide | OK        |

## Caso 3: fallo al insertar un autor nuevo (paso 3)

El alta trae dos autores nuevos, y el segundo repite el ISNI de Borges. El error 2601 de la restricción única `uq_autor_isni` llega en el tercer paso, con el libro y el primer autor ya insertados, y el ROLLBACK deshace los dos: no queda nada del alta.

| Filas nuevas     | LIBRO | AUTOR | AUTOR_LIBRO | PUBLICACION | Resultado |
| ---------------- | ----- | ----- | ----------- | ----------- | --------- |
| Tras el ROLLBACK | +0    | +0    | +0          | +0          | OK        |

| Comprobación                | Valor | Resultado |
| --------------------------- | ----- | --------- |
| Error de `uq_autor_isni`    | 2601  | OK        |
| Libros con el ISBN del alta | 0     | OK        |

## Caso 4: fallo al insertar la publicación (paso 5)

El alta trae a Borges y una autora nueva, y pide publicar a precio 0. El error 547 de `chk_publicacion_precio` llega en el último paso, con el libro, la autora y las dos autorías ya insertados, y el ROLLBACK deshace todo.

| Filas nuevas     | LIBRO | AUTOR | AUTOR_LIBRO | PUBLICACION | Resultado |
| ---------------- | ----- | ----- | ----------- | ----------- | --------- |
| Tras el ROLLBACK | +0    | +0    | +0          | +0          | OK        |

| Comprobación                      | Valor                | Resultado |
| --------------------------------- | -------------------- | --------- |
| Error de `chk_publicacion_precio` | 547                  | OK        |
| Libro y autora nueva que quedaron | 0 libros y 0 autores | OK        |

## Caso 5: el alta del caso 3 sin transacción

Las mismas sentencias del caso 3, ejecutadas sueltas: cada una se confirma por su cuenta. El segundo autor falla igual, con 2601, pero el libro y el primer autor quedan, y la autoría nunca llega a insertarse. El resultado es un libro sin autor, lo que RN08 prohíbe y la transacción del procedimiento evita.

| Filas nuevas | LIBRO | AUTOR | AUTOR_LIBRO | PUBLICACION | Resultado |
| ------------ | ----- | ----- | ----------- | ----------- | --------- |
| Que quedaron | +1    | +1    | +0          | +0          | OK        |

| Comprobación                               | Valor | Resultado |
| ------------------------------------------ | ----- | --------- |
| Error de `uq_autor_isni`                   | 2601  | OK        |
| Libros de la demostración sin autor (RN08) | 1     | OK        |

## Caso 6: ISBN repetido

El vendedor intenta registrar otra vez el ISBN `9990000000001` del caso 1, y el procedimiento lo rechaza con el error 50306 (RN06).

| Comprobación  | Valor | Resultado |
| ------------- | ----- | --------- |
| ISBN repetido | 50306 | OK        |

## Caso 7: validaciones

Cada llamada es un alta válida de un libro de Cortázar, salvo el dato indicado. El procedimiento rechaza cada una con su error antes de insertar nada.

| Llamada                                    | Error | Resultado |
| ------------------------------------------ | ----- | --------- |
| Un cliente registra el libro               | 50301 | OK        |
| Un vendedor dado de baja registra el libro | 50301 | OK        |
| Lista de autores vacía                     | 50302 | OK        |
| Fila con `autor_id` y nombre a la vez      | 50303 | OK        |
| `autor_id` inexistente                     | 50304 | OK        |
| El mismo autor dos veces                   | 50305 | OK        |
| Categoría inexistente                      | 50307 | OK        |
| Publicación sin condición                  | 50308 | OK        |
| El administrador pide publicar             | 50309 | OK        |

| Filas nuevas          | LIBRO | AUTOR | AUTOR_LIBRO | PUBLICACION | Resultado |
| --------------------- | ----- | ----- | ----------- | ----------- | --------- |
| Tras las validaciones | +0    | +0    | +0          | +0          | OK        |

## Caso 8: transacciones abiertas

Después de cada llamada al procedimiento, también de las que fallaron, no quedó ninguna transacción abierta (0).

## Conclusión

Con la transacción, el alta es todo o nada: un fallo en el tercer paso (caso 3, error 2601) o en el último (caso 4, error 547) no deja ninguna fila, mientras que las mismas sentencias sin transacción (caso 5) dejan un libro sin autor, contra RN08. El procedimiento rechaza el ISBN repetido y las nueve llamadas inválidas del caso 7 con los errores 50301 a 50309, sin escribir nada,, y nunca deja una transacción abierta. La limpieza borró todas las filas de la demostración: la base quedó igual.
