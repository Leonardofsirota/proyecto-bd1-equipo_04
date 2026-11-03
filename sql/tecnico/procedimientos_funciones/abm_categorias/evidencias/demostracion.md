# Demostración de `abm_categorias/demostracion.sql`

- **Fecha:** 2026-11-03 09:38
- **Repetición:** 2026-11-03, enseguida y sobre la misma base: los mismos resultados, con los ID 35 a 38 en lugar de 31 a 34.
- **Base temporal:** `tmp_validacion_pf`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más `abm_categorias/script.sql`
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. El nombre de 100 caracteres se abrevia como `Demo ABM x…x`: es `Demo ABM ` seguido de 91 `x`.

## Resumen

| Llamadas correctas | Errores provocados | Con el número esperado | filas_demo |
| ------------------ | ------------------ | ---------------------- | ---------- |
| 6                  | 9                  | 9                      | 0          |

CATEGORIA antes y después de la demostración:

| Momento | Filas | Checksum    | IDENT_CURRENT |
| ------- | ----- | ----------- | ------------- |
| Antes   | 30    | -1305360723 | 30            |
| Después | 30    | -1305360723 | 34            |

El ROLLBACK deshace todas las filas de la demostración. El contador IDENTITY no se revierte: queda en 34, el salto que anticipa el comentario del script.

## Caso 1: altas, modificación y baja correctas

**`usp_InsertarCategoria`** (cuatro llamadas)

| categoria_id | nombre                       | mensaje                           |
| ------------ | ---------------------------- | --------------------------------- |
| 31           | Demo ABM Narrativa Histórica | Categoria insertada correctamente |
| 32           | Demo ABM Teatro Clásico      | Categoria insertada correctamente |
| 33           | Demo ABM Poesía Española     | Categoria insertada correctamente |
| 34           | Demo ABM x…x                 | Categoria insertada correctamente |

**`usp_ModificarCategoria`** (categoría 31, nombre `'  Demo ABM Narrativa Épica  '`)

| mensaje                            |
| ---------------------------------- |
| Categoria modificada correctamente |

**`usp_EliminarCategoria`** (categoría 32)

| mensaje                           |
| --------------------------------- |
| Categoria eliminada correctamente |

**Estado antes del ROLLBACK**

| categoria_id | nombre                   | longitud |
| ------------ | ------------------------ | -------- |
| 31           | Demo ABM Narrativa Épica | 24       |
| 33           | Demo ABM Poesía Española | 24       |
| 34           | Demo ABM x…x             | 100      |

**Comprobaciones**

| Comprobación                              | Esperado                              | Obtenido                                  | Resultado |
| ----------------------------------------- | ------------------------------------- | ----------------------------------------- | --------- |
| Alta de dos categorías nuevas             | ID nuevo y confirmación               | 31 y 32, con confirmación                 | OK        |
| Alta con espacios en los extremos         | nombre recortado                      | `Demo ABM Poesía Española`, 24 caracteres | OK        |
| Alta de 100 caracteres sin los espacios   | aceptada y recortada                  | ID 34, 100 caracteres                     | OK        |
| Modificación con espacios en los extremos | `Demo ABM Narrativa Épica`, recortado | ID 31 con ese nombre, 24 caracteres       | OK        |
| Baja de una categoría sin libros          | ya no figura                          | ID 32 ausente                             | OK        |

## Caso 2: validaciones

Salida de `@Errores`. Para el error 50007, la demostración toma la categoría 1 (Novela), que tiene 138 libros (consulta aparte).

| esperado | obtenido | resultado | caso                                     | mensaje                                                        |
| -------- | -------- | --------- | ---------------------------------------- | -------------------------------------------------------------- |
| 50001    | 50001    | OK        | Insertar: nombre solo con espacios       | El nombre de la categoria es obligatorio.                      |
| 50002    | 50002    | OK        | Insertar: nombre repetido                | La categoria ya existe.                                        |
| 50003    | 50003    | OK        | Modificar: nombre NULL                   | El nombre de la categoria es obligatorio.                      |
| 50004    | 50004    | OK        | Modificar: categoría inexistente         | La categoria indicada no existe.                               |
| 50005    | 50005    | OK        | Modificar: nombre de otra categoría      | Ya existe otra categoria con ese nombre.                       |
| 50006    | 50006    | OK        | Eliminar: categoría inexistente          | La categoria indicada no existe.                               |
| 50007    | 50007    | OK        | Eliminar: categoría con libros asociados | No se puede eliminar: la categoria tiene libros asociados.     |
| 50008    | 50008    | OK        | Insertar: nombre de 150 caracteres       | El nombre de la categoria no puede superar los 100 caracteres. |
| 50009    | 50009    | OK        | Modificar: nombre de 101 caracteres      | El nombre de la categoria no puede superar los 100 caracteres. |

Ningún error modificó datos: el estado antes del ROLLBACK (caso 1) solo tiene las tres categorías de las llamadas correctas.
