# Demostración: usuario administrador y usuario de solo lectura

Prueba los dos usuarios que crea [`script.sql`](../script.sql): `usuario_admin`, miembro de `db_owner`, que administra la base, y `usuario_lectura`, miembro de `db_datareader`, que solo lee, salvo por el permiso `EXECUTE` sobre `usp_InsertarCategoria`. El servidor solo acepta autenticación de Windows, así que los logins de SQL Server de estos usuarios no pueden conectarse: la demostración suplanta a cada usuario con `EXECUTE AS USER`. Todo ocurre dentro de una transacción que se revierte al final.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **5 de 5** pasos con el resultado esperado: 3 permitidos y 2 errores 229

## Usuarios y permisos

Cada usuario está asociado a un login de SQL Server con su mismo nombre. `CONNECT` lo concede `CREATE USER`.

| Usuario         | Rol           | Permisos propios                                    |
| --------------- | ------------- | --------------------------------------------------- |
| usuario_admin   | db_owner      | `CONNECT`                                           |
| usuario_lectura | db_datareader | `CONNECT` y `EXECUTE` sobre `usp_InsertarCategoria` |

Los permisos efectivos de cada usuario, comprobados bajo su suplantación. El administrador tiene todos los permisos sin ser miembro de `db_datareader`, porque `db_owner` los incluye.

| Usuario         | db_owner | db_datareader | SELECT en CATEGORIA | INSERT en CATEGORIA | EXECUTE `usp_InsertarCategoria` | EXECUTE `usp_EliminarCategoria` |
| --------------- | -------- | ------------- | ------------------- | ------------------- | ------------------------------- | ------------------------------- |
| usuario_admin   | Sí       | No            | Sí                  | Sí                  | Sí                              | Sí                              |
| usuario_lectura | No       | Sí            | Sí                  | No                  | Sí                              | No                              |

## Pasos

| Paso | Usuario         | Operación                        | Resultado obtenido | Resultado |
| ---- | --------------- | -------------------------------- | ------------------ | --------- |
| 1    | usuario_admin   | `INSERT` directo en CATEGORIA    | Permitido          | OK        |
| 2    | usuario_lectura | `INSERT` directo en CATEGORIA    | Error 229          | OK        |
| 3    | usuario_lectura | `EXEC dbo.usp_InsertarCategoria` | Permitido          | OK        |
| 4    | usuario_lectura | `SELECT` sobre CATEGORIA         | Permitido          | OK        |
| 5    | usuario_lectura | `EXEC dbo.usp_EliminarCategoria` | Error 229          | OK        |

En el paso 1, el administrador da de alta una categoría con un `INSERT` directo, y SQL Server lo acepta. En el paso 2, el usuario de solo lectura intenta lo mismo y SQL Server lo rechaza con el error 229, tal como aparece en SSMS (el mensaje nombra la base de prueba):

```
Msg 229, Level 14, State 5, Server admin\SQLEXPRESS, Line 4
The INSERT permission was denied on the object 'CATEGORIA', database 'tmp_validacion_seg', schema 'dbo'.
```

En el paso 3, el mismo usuario da de alta la categoría a través de `usp_InsertarCategoria`, y el procedimiento responde «Categoria insertada correctamente». El procedimiento y `CATEGORIA` pertenecen a `dbo`: por el encadenamiento de propiedad, SQL Server comprueba el permiso `EXECUTE` sobre el procedimiento y no el `INSERT` sobre la tabla. Antes del ROLLBACK, `CATEGORIA` tenía las altas de los pasos 1 y 3, y ninguna del paso 2.

En el paso 4, el usuario de solo lectura lee `CATEGORIA` y cuenta 32 filas: las 30 de la base y las dos altas de la demostración, todavía sin revertir. En el paso 5 intenta borrar una categoría con `usp_EliminarCategoria`, del mismo ABM, y SQL Server lo rechaza con el error 229: su permiso `EXECUTE` es solo sobre `usp_InsertarCategoria`.

## Conclusión

El administrador puede escribir directamente en las tablas, y el usuario de solo lectura no: solo da de alta categorías a través del procedimiento que tiene permitido, y ningún otro. Después de cada paso, `REVERT` volvió al usuario original, `dbo`. No quedó ninguna transacción abierta, y el ROLLBACK no dejó ninguna categoría de la demostración: la base quedó igual.
