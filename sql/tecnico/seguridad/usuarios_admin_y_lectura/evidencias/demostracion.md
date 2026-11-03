# Demostración de `usuarios_admin_y_lectura/demostracion.sql`

- **Fecha:** 2026-11-03 16:33
- **Repetición:** 2026-11-03, enseguida y sobre la misma base, después de la demostración de `rol_lectura_libros`: los mismos resultados, con los ID 33 y 34 en lugar de 31 y 32.
- **Base temporal:** `tmp_validacion_seg`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más `abm_categorias/script.sql`, que crea `usp_InsertarCategoria`, y los `script.sql` de las dos carpetas de `seguridad`: `usuarios_admin_y_lectura` y `rol_lectura_libros`.
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit), configurado solo con autenticación de Windows.
- **Método:** salida de `sqlcmd`, agrupada por paso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración. Los mensajes de error nombran la base temporal: en la instalación real dicen `sistema-venta-libros`. Con autenticación de Windows solamente, los logins de SQL Server no pueden conectarse: un intento con `sqlcmd -U usuario_lectura` devolvió `Login failed for user 'usuario_lectura'`, y el log del servidor registró el motivo (`Server is configured for Integrated authentication only`). Por eso la demostración suplanta a cada usuario con `EXECUTE AS USER`.

## Resumen

| Pasos | Permitidos | Errores 229 | Con el resultado esperado | filas_demo |
| ----- | ---------- | ----------- | ------------------------- | ---------- |
| 5     | 3          | 2           | 5                         | 0          |

CATEGORIA antes y después de la demostración:

| Momento | Filas | Checksum    | IDENT_CURRENT |
| ------- | ----- | ----------- | ------------- |
| Antes   | 30    | -1305360723 | 30            |
| Después | 30    | -1305360723 | 32            |

El ROLLBACK deshace las dos altas. El contador IDENTITY no se revierte y avanzó dos valores, uno por cada alta aceptada: 31 del administrador y 32 del procedimiento. El `INSERT` rechazado del paso 2 no consumió ninguno, porque la comprobación de permisos lo detiene antes de ejecutarlo.

## Usuarios y permisos que crea `script.sql`

Cada usuario de la base está asociado a un login de SQL Server con su mismo nombre. El administrador es miembro de `db_owner` y el usuario de solo lectura, de `db_datareader`:

| usuario         | login           | tipo_login | rol           |
| --------------- | --------------- | ---------- | ------------- |
| usuario_admin   | usuario_admin   | SQL_LOGIN  | db_owner      |
| usuario_lectura | usuario_lectura | SQL_LOGIN  | db_datareader |

Permisos concedidos directamente a cada usuario. `CONNECT` lo concede `CREATE USER`; el único permiso propio de `usuario_lectura` es `EXECUTE` sobre el procedimiento:

| usuario         | estado | permiso | clase            | objeto                    |
| --------------- | ------ | ------- | ---------------- | ------------------------- |
| usuario_admin   | GRANT  | CONNECT | DATABASE         | NULL                      |
| usuario_lectura | GRANT  | CONNECT | DATABASE         | NULL                      |
| usuario_lectura | GRANT  | EXECUTE | OBJECT_OR_COLUMN | dbo.usp_InsertarCategoria |

## Permisos efectivos

Salida de `@Permisos`, con `IS_ROLEMEMBER` y `HAS_PERMS_BY_NAME` evaluados bajo la suplantación de cada usuario (1: es miembro o tiene el permiso; 0: no). `login_suplantado` es `SUSER_SNAME()` en ese momento. El administrador tiene todos los permisos sin ser miembro de `db_datareader`, porque `db_owner` los incluye.

| usuario         | login_suplantado | db_owner | db_datareader | select_categoria | insert_categoria | execute_insertar | execute_eliminar |
| --------------- | ---------------- | -------- | ------------- | ---------------- | ---------------- | ---------------- | ---------------- |
| usuario_admin   | usuario_admin    | 1        | 0             | 1                | 1                | 1                | 1                |
| usuario_lectura | usuario_lectura  | 0        | 1             | 1                | 0                | 1                | 0                |

`execute_insertar` y `execute_eliminar` se refieren a `usp_InsertarCategoria` y `usp_EliminarCategoria`.

## Pasos 1 a 3: INSERT directo y a través del procedimiento

Salida de `@Resultados`. La columna `usuario` es `USER_NAME()` bajo la suplantación, no un texto fijo:

| paso | usuario         | operacion                      | esperado  | obtenido  | resultado | detalle                                                                                                  |
| ---- | --------------- | ------------------------------ | --------- | --------- | --------- | -------------------------------------------------------------------------------------------------------- |
| 1    | usuario_admin   | INSERT directo en CATEGORIA    | Permitido | Permitido | OK        | categoria_id 31                                                                                          |
| 2    | usuario_lectura | INSERT directo en CATEGORIA    | Error 229 | Error 229 | OK        | The INSERT permission was denied on the object 'CATEGORIA', database 'tmp_validacion_seg', schema 'dbo'. |
| 3    | usuario_lectura | EXEC dbo.usp_InsertarCategoria | Permitido | Permitido | OK        | categoria_id 32                                                                                          |

- **Paso 1:** el administrador inserta `Demo Seguridad Admin Directo` con un `INSERT` directo, y SQL Server lo acepta.
- **Paso 2:** el usuario de solo lectura intenta un `INSERT` directo de `Demo Seguridad Lectura Directo`, y SQL Server lo rechaza con el error 229. Ejecutado sin `TRY...CATCH`, en una consulta aparte, un `INSERT` directo del mismo usuario muestra el error tal como aparece en SSMS:

  ```
  Msg 229, Level 14, State 5, Server admin\SQLEXPRESS, Line 4
  The INSERT permission was denied on the object 'CATEGORIA', database 'tmp_validacion_seg', schema 'dbo'.
  ```

- **Paso 3:** el mismo usuario inserta `Demo Seguridad Lectura Procedimiento` a través de `usp_InsertarCategoria`, y lo consigue. El procedimiento devuelve su confirmación:

  | categoria_id | nombre                               | mensaje                           |
  | ------------ | ------------------------------------ | --------------------------------- |
  | 32           | Demo Seguridad Lectura Procedimiento | Categoria insertada correctamente |

  El procedimiento y `CATEGORIA` pertenecen a `dbo`: por el encadenamiento de propiedad, SQL Server comprueba el permiso `EXECUTE` sobre el procedimiento y no el `INSERT` sobre la tabla.

**Estado antes del ROLLBACK:** las altas de los pasos 1 y 3, y ninguna del paso 2.

| categoria_id | nombre                               |
| ------------ | ------------------------------------ |
| 31           | Demo Seguridad Admin Directo         |
| 32           | Demo Seguridad Lectura Procedimiento |

## Pasos 4 y 5: comprobaciones complementarias

| paso | usuario         | operacion                      | esperado  | obtenido  | resultado | detalle                                                                                                               |
| ---- | --------------- | ------------------------------ | --------- | --------- | --------- | --------------------------------------------------------------------------------------------------------------------- |
| 4    | usuario_lectura | SELECT sobre CATEGORIA         | Permitido | Permitido | OK        | 32 filas leídas                                                                                                       |
| 5    | usuario_lectura | EXEC dbo.usp_EliminarCategoria | Error 229 | Error 229 | OK        | The EXECUTE permission was denied on the object 'usp_EliminarCategoria', database 'tmp_validacion_seg', schema 'dbo'. |

- **Paso 4:** el usuario de solo lectura lee `CATEGORIA`. Cuenta 32 filas: las 30 de la base y las dos altas de la demostración, todavía sin revertir.
- **Paso 5:** intenta borrar la categoría 32 con `usp_EliminarCategoria`, del mismo ABM, y SQL Server lo rechaza: el permiso `EXECUTE` es solo sobre `usp_InsertarCategoria`.

## Comprobación final

| usuario_actual | transacciones_abiertas | filas_demo |
| -------------- | ---------------------- | ---------- |
| dbo            | 0                      | 0          |

Después de cada paso, `REVERT` devolvió el usuario original, `dbo`. No quedó ninguna transacción abierta, y el ROLLBACK no dejó ninguna categoría `Demo Seguridad`.
