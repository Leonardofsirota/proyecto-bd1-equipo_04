# Seguridad - Etapa 5

## 1. Definición y objetivo

La **seguridad** de una base de datos define quién puede conectarse y qué puede hacer cada uno con cada objeto. SQL Server la resuelve en dos pasos:

- **Autenticación:** al conectarse, el servidor comprueba la identidad con un **login**, que es un objeto del servidor. Puede ser de Windows (la cuenta del sistema operativo) o de SQL Server (nombre y contraseña).
- **Autorización:** dentro de cada base, el login se asocia a un **usuario de base de datos**, y antes de cada sentencia SQL Server comprueba que ese usuario tenga el permiso necesario sobre el objeto.

| Concepto | Qué es | En el proyecto |
| --- | --- | --- |
| Login | Identidad en el servidor. Autentica la conexión | `usuario_admin`, `usuario_lectura`, `usuario_con_rol` y `usuario_sin_rol`, de SQL Server |
| Usuario de base de datos | Identidad dentro de una base, asociada a un login. Recibe los permisos | Los mismos cuatro nombres, en `sistema-venta-libros` |
| Rol fijo de base de datos | Rol predefinido con un conjunto de permisos | `db_owner` y `db_datareader` |
| Rol definido por el usuario | Grupo creado con `CREATE ROLE`, que recibe permisos y miembros | `rol_lectura_libros` |
| Objeto protegible | Lo que se protege: servidor, base, esquema, tabla, procedimiento | `CATEGORIA`, `LIBRO`, `USUARIO`, `usp_InsertarCategoria` |
| Permiso | Una acción sobre un objeto | `SELECT` sobre `LIBRO`, `EXECUTE` sobre `usp_InsertarCategoria` |

Tres sentencias administran los permisos: `GRANT` concede un permiso, `DENY` lo prohíbe explícitamente y prevalece sobre cualquier `GRANT`, también sobre uno heredado de un rol, y `REVOKE` quita un `GRANT` o un `DENY` anterior.

Los usuarios de base de datos no son los usuarios del sistema de ventas. Los clientes, vendedores y administradores de la tabla `USUARIO` (RN01) son datos: la aplicación se conecta con un login compartido y declara qué usuario actúa con `usp_EstablecerUsuarioSesion`, del tema de auditoría. Sus reglas, como que solo un cliente haga pedidos (RN04), las aplican los procedimientos y los triggers. Los permisos de SQL Server controlan qué puede hacer cada login con la base.

El objetivo es el **mínimo privilegio**: cada login tiene solo los permisos que necesita su función, las escrituras pasan por procedimientos que validan, y los datos sensibles quedan fuera del alcance de quien no los usa.

## 2. Ventajas y aplicaciones

- **Escritura solo a través de procedimientos:** con `EXECUTE` sobre `usp_InsertarCategoria` y sin `INSERT` sobre `CATEGORIA`, el usuario de solo lectura solo puede dar de alta categorías a través del procedimiento, que recorta el nombre y rechaza uno vacío, de más de 100 caracteres o repetido con sus propios mensajes (errores 50001, 50008 y 50002). Un `INSERT` directo recibe el error 229: ese usuario no tiene otra forma de escribir en la tabla.
- **Permisos administrados por grupo:** el permiso se concede una vez, al rol, y cada usuario lo obtiene al ser miembro. En la demostración del rol, agregar a `usuario_sin_rol` como miembro le dio acceso a `LIBRO`, y quitarlo se lo sacó, sin conceder ni revocar permisos.
- **Granularidad:** los permisos se conceden por objeto y por acción. El usuario de solo lectura puede ejecutar `usp_InsertarCategoria` pero no `usp_EliminarCategoria`, del mismo ABM, y el miembro de `rol_lectura_libros` puede leer `LIBRO` pero no modificarlo.
- **Protección de datos sensibles:** el miembro del rol lee el catálogo, pero no `USUARIO`, que guarda los datos personales de los clientes y el hash de sus contraseñas.
- **Separación de funciones:** un administrador de la base (`db_owner`) no necesita el rol `sysadmin` de toda la instancia, y una cuenta de consulta no necesita escribir.
- **Trazabilidad junto con la auditoría:** `AUDITORIA.login_bd` guarda `ORIGINAL_LOGIN()`, el login que se autenticó, que no cambia aunque la sesión suplante a otro usuario. Cada evento queda asociado a una identidad verificada por el servidor.

## 3. Implementación en SQL Server Express

SQL Server Express tiene el mismo modelo de seguridad y el mismo T-SQL que las demás ediciones: logins, usuarios, roles fijos y definidos por el usuario, `GRANT`, `DENY`, `REVOKE` y `EXECUTE AS`. Todas las evidencias se obtuvieron en SQL Server 2025 Express Edition.

```sql
-- Patrón de los scripts del proyecto, resumido de los dos casos

-- 1. Autenticación: login del servidor
CREATE LOGIN usuario_lectura
WITH PASSWORD = N'...',
     DEFAULT_DATABASE = [sistema-venta-libros],
     CHECK_POLICY = ON,                 -- aplica la política de contraseñas de Windows
     CHECK_EXPIRATION = OFF;

-- 2. Autorización: usuario de la base, asociado al login
CREATE USER usuario_lectura FOR LOGIN usuario_lectura WITH DEFAULT_SCHEMA = dbo;

-- 3. Permisos: rol fijo, permiso sobre un objeto o rol propio
ALTER ROLE db_datareader ADD MEMBER usuario_lectura;
GRANT EXECUTE ON OBJECT::dbo.usp_InsertarCategoria TO usuario_lectura;

CREATE ROLE rol_lectura_libros AUTHORIZATION dbo;
GRANT SELECT ON OBJECT::dbo.LIBRO TO rol_lectura_libros;
ALTER ROLE rol_lectura_libros ADD MEMBER usuario_con_rol;

-- Prueba: ejecutar con los permisos de otro usuario
EXECUTE AS USER = 'usuario_lectura';
BEGIN TRY
    INSERT INTO dbo.CATEGORIA (nombre) VALUES ('...');   -- error 229
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS mensaje;
END CATCH;
REVERT;                                 -- fuera del TRY: corre aunque la sentencia falle
```

Recursos que usan los scripts del proyecto:

- **Modos de autenticación:** solo Windows, o mixto (Windows y SQL Server). La instancia de las evidencias está configurada solo con autenticación de Windows (`SERVERPROPERTY('IsIntegratedSecurityOnly')` = 1). Ahí se pueden crear logins de SQL Server, pero no conectarse con ellos: el intento devolvió `Login failed`, y el log del servidor registró `Server is configured for Integrated authentication only`. Para usarlos hay que activar el modo mixto en las propiedades del servidor y reiniciar el servicio. Las demostraciones no lo necesitan, porque suplantan a cada usuario con `EXECUTE AS USER`.
- **Roles fijos de base de datos:** `db_owner` permite cualquier acción en la base, `db_datareader` concede `SELECT` sobre todas las tablas y vistas, y `db_datawriter`, `INSERT`, `UPDATE` y `DELETE`. `ALTER ROLE ... ADD MEMBER` existe desde SQL Server 2012 y reemplaza a `sp_addrolemember`, obsoleto: es compatible con la versión mínima del proyecto.
- **Encadenamiento de propiedad:** cuando un procedimiento accede a un objeto del mismo dueño, SQL Server solo comprueba el permiso sobre el procedimiento. Todos los objetos del proyecto están en el esquema `dbo`, y por eso `usuario_lectura` inserta a través de `usp_InsertarCategoria` sin permiso sobre `CATEGORIA`. La cadena no cubre el SQL dinámico: en una prueba aparte, no guardada como evidencia, una copia del procedimiento que hacía el `INSERT` con `sp_executesql` recibió el error 229 sobre `CATEGORIA`.
- **`DENY` prevalece sobre `GRANT`:** en pruebas aparte, un `DENY SELECT` sobre `LIBRO` a `usuario_con_rol` le quitó el permiso que le da el rol, y un `DENY INSERT` sobre `CATEGORIA` a `usuario_admin` también rigió para ese miembro de `db_owner`. A `dbo` no se le pueden conceder, denegar ni revocar permisos (`Cannot grant, deny, or revoke permissions to sa, dbo, ...`): tiene todos en su base, y los logins de `sysadmin` entran a cada base como `dbo`.
- **El error de permisos es el 229, de nivel 14**, y la comprobación ocurre antes de ejecutar la sentencia: el `INSERT` rechazado no consumió ningún valor IDENTITY, y el `UPDATE` rechazado no cambió el checksum de `LIBRO`. Con `XACT_ABORT` en OFF tampoco anula la transacción (`XACT_STATE()` sigue en 1), y por eso las demostraciones pueden seguir después de cada error y terminar en un `ROLLBACK` propio.
- **`EXECUTE AS USER` y `REVERT`:** la sesión pasa a tener los permisos del usuario suplantado dentro de la base actual, y `REVERT` la devuelve al original. Requiere el permiso `IMPERSONATE` sobre ese usuario, que tienen los miembros de `db_owner`: `usuario_admin` pudo suplantar a `usuario_lectura`, y `usuario_lectura` no pudo suplantar a otro (error 15517). La suplantación sigue activa hasta el `REVERT`, aun después de un error, así que el `REVERT` va fuera del `TRY`. Bajo la suplantación, `USER_NAME()` y `SUSER_SNAME()` devuelven el usuario y el login suplantados, y `ORIGINAL_LOGIN()`, el login real.
- **`HAS_PERMS_BY_NAME` e `IS_ROLEMEMBER`:** evalúan los permisos efectivos y la pertenencia a roles del usuario actual, sumando los que hereda de sus roles. Las demostraciones los consultan bajo la suplantación de cada usuario.
- **Los logins son objetos del servidor:** borrar la base no los elimina. Los scripts borran primero el usuario y después el login, para no dejar un usuario huérfano, y se pueden ejecutar varias veces. Crear un login requiere el permiso `ALTER ANY LOGIN` (roles `securityadmin` o `sysadmin`).
- **Contraseñas:** las de los scripts son de ejemplo. En un despliegue real se definen al instalar y no se guardan en el repositorio, o se usan logins de Windows (`CREATE LOGIN [EQUIPO\cuenta] FROM WINDOWS`), que no tienen contraseña en SQL Server.

## 4. Casos concretos aplicados al sistema de ventas

- **[`usuarios_admin_y_lectura`](usuarios_admin_y_lectura/)**: permisos a nivel de usuarios. `usuario_admin`, miembro de `db_owner`, administra la base, y `usuario_lectura`, miembro de `db_datareader`, solo lee, con la única excepción del permiso `EXECUTE` sobre `usp_InsertarCategoria`, de [`abm_categorias`](../procedimientos_funciones/abm_categorias/). El `INSERT` directo sobre `CATEGORIA` funciona para el administrador y falla con el error 229 para el usuario de solo lectura, que sí da de alta la categoría a través del procedimiento (RN09). Además, el usuario de solo lectura puede leer `CATEGORIA` y no puede ejecutar `usp_EliminarCategoria`. Resultado: 5 de 5 pasos con el resultado esperado.
  [`script.sql`](usuarios_admin_y_lectura/script.sql) · [`demostracion.sql`](usuarios_admin_y_lectura/demostracion.sql) · [`evidencias/demostracion.md`](usuarios_admin_y_lectura/evidencias/demostracion.md)

- **[`rol_lectura_libros`](rol_lectura_libros/)**: permisos a nivel de roles. `rol_lectura_libros` solo tiene `SELECT` sobre `LIBRO`, como necesitaría quien consulta el catálogo desde otro sistema. `usuario_con_rol`, su miembro, lee los 500 libros, y `usuario_sin_rol`, sin el rol ni permisos propios, recibe el error 229. El miembro del rol tampoco puede leer `USUARIO` ni modificar `LIBRO`, y agregar a `usuario_sin_rol` al rol le da acceso, que pierde al quitarlo. Resultado: 6 de 6 pasos con el resultado esperado.
  [`script.sql`](rol_lectura_libros/script.sql) · [`demostracion.sql`](rol_lectura_libros/demostracion.sql) · [`evidencias/demostracion.md`](rol_lectura_libros/evidencias/demostracion.md)

- **[Auditoría bajo `EXECUTE AS`](../triggers_auditoria/auditar_precio_publicacion/)**, implementada en el tema de triggers de auditoría: en el caso 6 de su demostración, un usuario sin login con permisos solo de `SELECT` y `UPDATE` sobre `PUBLICACION` cambia un precio. `trg_PUBLICACION_AuditoriaPrecio` registra el evento en `AUDITORIA` a través de `usp_RegistrarAuditoria`, sobre los que el usuario no tiene permisos, gracias al encadenamiento de propiedad, y `login_bd` guarda el login real y no el suplantado.
  [`script.sql`](../triggers_auditoria/auditar_precio_publicacion/script.sql) · [`evidencias/demostracion.md`](../triggers_auditoria/auditar_precio_publicacion/evidencias/demostracion.md)
