# Demostración: alta, modificación y baja de categorías

Prueba los procedimientos `usp_InsertarCategoria`, `usp_ModificarCategoria` y `usp_EliminarCategoria`, con los que el administrador mantiene la lista de categorías del catálogo (RN09). El nombre es obligatorio, único y de hasta 100 caracteres, y no se borra una categoría que use algún libro, porque cada libro tiene una categoría (RN07). La demostración corre dentro de una transacción que termina en `ROLLBACK`, así que no deja datos en la base.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **6 llamadas correctas y 9 errores provocados**, todos con el número esperado

## Resumen

| Caso | Qué se prueba                        | Llamadas y errores | Resultado |
| ---- | ------------------------------------ | ------------------ | --------- |
| 1    | Altas, modificación y baja correctas | 6 llamadas         | OK        |
| 2    | Validaciones                         | 9 errores          | OK        |

## Caso 1: altas, modificación y baja correctas

Se dieron de alta cuatro categorías, se modificó una y se dio de baja otra, sin libros. Cada llamada devolvió su confirmación. Los procedimientos recortan los espacios de los extremos del nombre, tanto en el alta como en la modificación, y aceptan un nombre que, ya recortado, tiene exactamente 100 caracteres. Antes del `ROLLBACK` quedaban las tres categorías esperadas:

| Categoría | Nombre                   | Longitud |
| --------- | ------------------------ | -------- |
| 31        | Demo ABM Narrativa Épica | 24       |
| 33        | Demo ABM Poesía Española | 24       |
| 34        | nombre de 100 caracteres | 100      |

| Comprobación                                                  | Valor                                               | Resultado |
| ------------------------------------------------------------- | --------------------------------------------------- | --------- |
| Alta de dos categorías nuevas, con ID nuevo y confirmación    | 31 y 32, con confirmación                           | OK        |
| Alta con espacios en los extremos: nombre recortado           | `Demo ABM Poesía Española`, 24 caracteres           | OK        |
| Alta de 100 caracteres sin los espacios: aceptada y recortada | ID 34, 100 caracteres                               | OK        |
| Modificación con espacios en los extremos: nombre recortado   | ID 31 con `Demo ABM Narrativa Épica`, 24 caracteres | OK        |
| Baja de una categoría sin libros: ya no figura                | ID 32 ausente                                       | OK        |

## Caso 2: validaciones

Nueve llamadas con datos inválidos cubren el nombre vacío o nulo, el repetido, el que supera los 100 caracteres, la categoría inexistente y la que tiene libros asociados. Cada una se rechazó con su número de error y un mensaje que explica el motivo. Ningún error modificó datos: antes del `ROLLBACK` solo estaban las categorías de las llamadas correctas del caso 1.

| Validación                               | Error | Mensaje                                                        | Resultado |
| ---------------------------------------- | ----- | -------------------------------------------------------------- | --------- |
| Insertar: nombre solo con espacios       | 50001 | El nombre de la categoria es obligatorio.                      | OK        |
| Insertar: nombre repetido                | 50002 | La categoria ya existe.                                        | OK        |
| Modificar: nombre NULL                   | 50003 | El nombre de la categoria es obligatorio.                      | OK        |
| Modificar: categoría inexistente         | 50004 | La categoria indicada no existe.                               | OK        |
| Modificar: nombre de otra categoría      | 50005 | Ya existe otra categoria con ese nombre.                       | OK        |
| Eliminar: categoría inexistente          | 50006 | La categoria indicada no existe.                               | OK        |
| Eliminar: categoría con libros asociados | 50007 | No se puede eliminar: la categoria tiene libros asociados.     | OK        |
| Insertar: nombre de 150 caracteres       | 50008 | El nombre de la categoria no puede superar los 100 caracteres. | OK        |
| Modificar: nombre de 101 caracteres      | 50009 | El nombre de la categoria no puede superar los 100 caracteres. | OK        |

## Conclusión

Los tres procedimientos aplican las reglas del nombre de una categoría: lo recortan, exigen que no quede vacío, que no se repita y que no pase de 100 caracteres. Además, impiden borrar una categoría en uso. Las seis llamadas correctas se confirmaron y los nueve errores tuvieron el número esperado, sin modificar datos. El `ROLLBACK` deshizo todas las altas: la base quedó igual, sin ninguna fila de la demostración.
