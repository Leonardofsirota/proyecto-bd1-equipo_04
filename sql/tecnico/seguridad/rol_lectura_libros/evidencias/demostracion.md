# Demostración de `rol_lectura_libros/demostracion.sql`

- **Fecha:** 2026-11-03 16:33
- **Repetición:** 2026-11-03, enseguida y sobre la misma base, después de repetir la demostración de `usuarios_admin_y_lectura`: los mismos resultados.
- **Base temporal:** `tmp_validacion_seg`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más `abm_categorias/script.sql` y los `script.sql` de las dos carpetas de `seguridad`: `usuarios_admin_y_lectura` y `rol_lectura_libros`. Antes se ejecutó la demostración de `usuarios_admin_y_lectura`.
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit), configurado solo con autenticación de Windows.
- **Método:** salida de `sqlcmd`, agrupada por paso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración. Los mensajes de error nombran la base temporal: en la instalación real dicen `sistema-venta-libros`. Con autenticación de Windows solamente, los logins de SQL Server no pueden conectarse, así que la demostración suplanta a cada usuario con `EXECUTE AS USER` (ver la evidencia de [`usuarios_admin_y_lectura`](../../usuarios_admin_y_lectura/evidencias/demostracion.md)).

## Resumen

| Pasos | Permitidos | Errores 229 | Con el resultado esperado | filas_demo |
| ----- | ---------- | ----------- | ------------------------- | ---------- |
| 6     | 2          | 4           | 6                         | 0          |

LIBRO antes y después de la demostración:

| Momento | Filas | Checksum   | IDENT_CURRENT |
| ------- | ----- | ---------- | ------------- |
| Antes   | 500   | 2096367084 | 500           |
| Después | 500   | 2096367084 | 500           |

Ningún paso modificó `LIBRO`: el `UPDATE` del paso 4 se rechazó antes de ejecutarse. Los miembros del rol tampoco cambiaron: antes y después, el único es `usuario_con_rol`.

## Usuarios, rol y permisos que crea `script.sql`

Cada usuario de la base está asociado a un login de SQL Server con su mismo nombre. Solo `usuario_con_rol` es miembro de `rol_lectura_libros`:

| usuario         | login           | tipo_login | rol                |
| --------------- | --------------- | ---------- | ------------------ |
| usuario_con_rol | usuario_con_rol | SQL_LOGIN  | rol_lectura_libros |
| usuario_sin_rol | usuario_sin_rol | SQL_LOGIN  | NULL               |

Permisos concedidos directamente al rol y a cada usuario. El único permiso sobre una tabla es `SELECT` sobre `LIBRO`, y lo tiene el rol, no un usuario. `CONNECT` lo concede `CREATE USER`:

| principal          | tipo          | estado | permiso | clase            | objeto    |
| ------------------ | ------------- | ------ | ------- | ---------------- | --------- |
| rol_lectura_libros | DATABASE_ROLE | GRANT  | SELECT  | OBJECT_OR_COLUMN | dbo.LIBRO |
| usuario_con_rol    | SQL_USER      | GRANT  | CONNECT | DATABASE         | NULL      |
| usuario_sin_rol    | SQL_USER      | GRANT  | CONNECT | DATABASE         | NULL      |

## Permisos efectivos

Salida de `@Permisos`, con `IS_ROLEMEMBER` y `HAS_PERMS_BY_NAME` evaluados bajo la suplantación de cada usuario (1: es miembro o tiene el permiso; 0: no). `login_suplantado` es `SUSER_SNAME()` en ese momento.

| usuario         | login_suplantado | miembro_rol | select_libro | insert_libro | update_libro | delete_libro | select_usuario |
| --------------- | ---------------- | ----------- | ------------ | ------------ | ------------ | ------------ | -------------- |
| usuario_con_rol | usuario_con_rol  | 1           | 1            | 0            | 0            | 0            | 0              |
| usuario_sin_rol | usuario_sin_rol  | 0           | 0            | 0            | 0            | 0            | 0              |

El usuario con el rol solo puede leer `LIBRO`. El usuario sin el rol no tiene ningún permiso sobre las tablas.

## Pasos 1 y 2: lectura de LIBRO con el rol y sin él

Salida de `@Resultados`. La columna `usuario` es `USER_NAME()` bajo la suplantación, no un texto fijo:

| paso | usuario         | operacion          | esperado  | obtenido  | resultado | detalle                                                                                              |
| ---- | --------------- | ------------------ | --------- | --------- | --------- | ---------------------------------------------------------------------------------------------------- |
| 1    | usuario_con_rol | SELECT sobre LIBRO | Permitido | Permitido | OK        | 500 filas leídas                                                                                     |
| 2    | usuario_sin_rol | SELECT sobre LIBRO | Error 229 | Error 229 | OK        | The SELECT permission was denied on the object 'LIBRO', database 'tmp_validacion_seg', schema 'dbo'. |

- **Paso 1:** el usuario con el rol cuenta las 500 filas de `LIBRO` y lee las primeras cinco:

  | libro_id | isbn          | titulo                                | anio_publicacion |
  | -------- | ------------- | ------------------------------------- | ---------------- |
  | 1        | 9789500421010 | Ficciones                             | 1944             |
  | 2        | 9789500421027 | Seis problemas para don Isidro Parodi | 1942             |
  | 3        | 9789500712033 | Rayuela                               | 1963             |
  | 4        | 9789500712040 | Cien años de soledad                  | 1967             |
  | 5        | 9788497593052 | La casa de los espíritus              | 1982             |

- **Paso 2:** el usuario sin el rol intenta la misma lectura, y SQL Server la rechaza con el error 229 antes de devolver ninguna fila. Ejecutada sin `TRY...CATCH`, en una consulta aparte, una lectura de `LIBRO` del mismo usuario muestra el error tal como aparece en SSMS:

  ```
  Msg 229, Level 14, State 5, Server admin\SQLEXPRESS, Line 2
  The SELECT permission was denied on the object 'LIBRO', database 'tmp_validacion_seg', schema 'dbo'.
  ```

## Pasos 3 a 6: comprobaciones complementarias

| paso | usuario         | operacion                              | esperado  | obtenido  | resultado | detalle                                                                                                |
| ---- | --------------- | -------------------------------------- | --------- | --------- | --------- | ------------------------------------------------------------------------------------------------------ |
| 3    | usuario_con_rol | SELECT sobre USUARIO                   | Error 229 | Error 229 | OK        | The SELECT permission was denied on the object 'USUARIO', database 'tmp_validacion_seg', schema 'dbo'. |
| 4    | usuario_con_rol | UPDATE sobre LIBRO                     | Error 229 | Error 229 | OK        | The UPDATE permission was denied on the object 'LIBRO', database 'tmp_validacion_seg', schema 'dbo'.   |
| 5    | usuario_sin_rol | SELECT sobre LIBRO, ya miembro del rol | Permitido | Permitido | OK        | 500 filas leídas                                                                                       |
| 6    | usuario_sin_rol | SELECT sobre LIBRO, quitado del rol    | Error 229 | Error 229 | OK        | The SELECT permission was denied on the object 'LIBRO', database 'tmp_validacion_seg', schema 'dbo'.   |

- **Paso 3:** el rol solo cubre `LIBRO`. El usuario con el rol no puede leer `USUARIO`, que guarda datos personales y el hash de las contraseñas.
- **Paso 4:** el rol solo permite leer. El usuario con el rol no puede cambiar el título del libro 1.
- **Paso 5:** `ALTER ROLE ... ADD MEMBER` agrega a `usuario_sin_rol` al rol, y desde ese momento puede leer `LIBRO`, sin recibir ningún permiso propio.
- **Paso 6:** `ALTER ROLE ... DROP MEMBER` lo quita del rol, y vuelve a recibir el error 229.

## Comprobación final

| usuario_actual | transacciones_abiertas | miembros_rol | con_rol_es_miembro | sin_rol_es_miembro | filas_demo |
| -------------- | ---------------------- | ------------ | ------------------ | ------------------ | ---------- |
| dbo            | 0                      | 1            | 1                  | 0                  | 0          |

Después de cada paso, `REVERT` devolvió el usuario original, `dbo`. No quedó ninguna transacción abierta, `usuario_con_rol` sigue siendo el único miembro del rol y ningún título quedó modificado.
