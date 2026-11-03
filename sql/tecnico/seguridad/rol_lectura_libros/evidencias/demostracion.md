# Demostración: rol de solo lectura del catálogo de libros

Prueba el rol `rol_lectura_libros`, que crea [`script.sql`](../script.sql) con un único permiso, `SELECT` sobre `LIBRO`, y sus dos usuarios: `usuario_con_rol`, miembro del rol, y `usuario_sin_rol`, sin el rol ni permisos propios. La demostración suplanta a cada usuario con `EXECUTE AS USER`, por el motivo que explica la evidencia de [`usuarios_admin_y_lectura`](../../usuarios_admin_y_lectura/evidencias/demostracion.md).

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **6 de 6** pasos con el resultado esperado: 2 permitidos y 4 errores 229

## Usuarios, rol y permisos

Cada usuario está asociado a un login de SQL Server con su mismo nombre. `CONNECT` lo concede `CREATE USER`. El único permiso sobre una tabla es `SELECT` sobre `LIBRO`, y lo tiene el rol, no un usuario.

| Usuario         | Rol                | Permisos propios |
| --------------- | ------------------ | ---------------- |
| usuario_con_rol | rol_lectura_libros | `CONNECT`        |
| usuario_sin_rol | ninguno            | `CONNECT`        |

Los permisos efectivos de cada usuario, comprobados bajo su suplantación. El usuario con el rol solo puede leer `LIBRO`, y el usuario sin el rol no tiene ningún permiso sobre las tablas.

| Usuario         | Miembro del rol | SELECT en LIBRO | INSERT en LIBRO | UPDATE en LIBRO | DELETE en LIBRO | SELECT en USUARIO |
| --------------- | --------------- | --------------- | --------------- | --------------- | --------------- | ----------------- |
| usuario_con_rol | Sí              | Sí              | No              | No              | No              | No                |
| usuario_sin_rol | No              | No              | No              | No              | No              | No                |

## Resumen

| Paso | Usuario         | Operación                                | Resultado obtenido | Resultado |
| ---- | --------------- | ---------------------------------------- | ------------------ | --------- |
| 1    | usuario_con_rol | `SELECT` sobre LIBRO                     | Permitido          | OK        |
| 2    | usuario_sin_rol | `SELECT` sobre LIBRO                     | Error 229          | OK        |
| 3    | usuario_con_rol | `SELECT` sobre USUARIO                   | Error 229          | OK        |
| 4    | usuario_con_rol | `UPDATE` sobre LIBRO                     | Error 229          | OK        |
| 5    | usuario_sin_rol | `SELECT` sobre LIBRO, ya miembro del rol | Permitido          | OK        |
| 6    | usuario_sin_rol | `SELECT` sobre LIBRO, quitado del rol    | Error 229          | OK        |

## Detalle de los pasos

En el paso 1, el usuario con el rol lee los 500 libros de `LIBRO`. En el paso 2, el usuario sin el rol intenta la misma lectura, y SQL Server la rechaza con el error 229 antes de devolver ninguna fila, tal como aparece en SSMS (el mensaje nombra la base de prueba):

```
Msg 229, Level 14, State 5, Server admin\SQLEXPRESS, Line 2
The SELECT permission was denied on the object 'LIBRO', database 'tmp_validacion_seg', schema 'dbo'.
```

Los pasos 3 y 4 muestran los límites del rol: solo cubre `LIBRO`, así que su miembro no puede leer `USUARIO`, que guarda datos personales y el hash de las contraseñas, y solo permite leer, así que no puede cambiar el título de un libro. En los pasos 5 y 6, `ALTER ROLE ... ADD MEMBER` agrega a `usuario_sin_rol` al rol, y desde ese momento lee los 500 libros sin recibir ningún permiso propio; `ALTER ROLE ... DROP MEMBER` lo quita, y vuelve a recibir el error 229.

## Conclusión

El rol concede exactamente lo que necesita quien consulta el catálogo: leer `LIBRO`, sin acceso a otras tablas ni permiso para modificarla, y el acceso se da o se quita con solo agregar o quitar al usuario del rol. Después de cada paso, `REVERT` volvió al usuario original, `dbo`, y no quedó ninguna transacción abierta. `LIBRO` no cambió, porque el `UPDATE` del paso 4 se rechazó antes de ejecutarse, y el rol conservó a `usuario_con_rol` como su único miembro: la base quedó igual.
