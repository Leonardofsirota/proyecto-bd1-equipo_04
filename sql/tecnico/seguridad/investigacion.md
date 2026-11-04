# Seguridad - Etapa 5

## 1. Definición y objetivo

La **seguridad** de una base de datos define quién puede conectarse y qué puede hacer cada uno con cada objeto. SQL Server la resuelve en dos pasos:

- **Autenticación:** al conectarse, el servidor comprueba la identidad con un **login**, que es un objeto del servidor. Puede ser de Windows (la cuenta del sistema operativo) o de SQL Server (nombre y contraseña).
- **Autorización:** dentro de cada base, el login se asocia a un **usuario de base de datos**, y antes de cada sentencia SQL Server comprueba que ese usuario tenga el permiso necesario sobre el objeto.

| Concepto                    | Qué es                                                                 | En el proyecto                                                                           |
| --------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Login                       | Identidad en el servidor. Autentica la conexión                        | `usuario_admin`, `usuario_lectura`, `usuario_con_rol` y `usuario_sin_rol`, de SQL Server |
| Usuario de base de datos    | Identidad dentro de una base, asociada a un login. Recibe los permisos | Los mismos cuatro nombres, en `sistema-venta-libros`                                     |
| Rol fijo de base de datos   | Rol predefinido con un conjunto de permisos                            | `db_owner` y `db_datareader`                                                             |
| Rol definido por el usuario | Grupo creado con `CREATE ROLE`, que recibe permisos y miembros         | `rol_lectura_libros`                                                                     |
| Objeto protegible           | Lo que se protege: servidor, base, esquema, tabla, procedimiento       | `CATEGORIA`, `LIBRO`, `USUARIO`, `usp_InsertarCategoria`                                 |
| Permiso                     | Una acción sobre un objeto                                             | `SELECT` sobre `LIBRO`, `EXECUTE` sobre `usp_InsertarCategoria`                          |

Tres sentencias administran los permisos: `GRANT` concede un permiso, `DENY` lo prohíbe explícitamente y prevalece sobre cualquier `GRANT`, también sobre uno heredado de un rol, y `REVOKE` quita un `GRANT` o un `DENY` anterior.

Los usuarios de base de datos no son los usuarios del sistema de ventas. Los clientes, vendedores y administradores de la tabla `USUARIO` (RN01) son datos: la aplicación se conecta con un login compartido y declara qué usuario actúa, como se explica en el tema de auditoría. Sus reglas, como que solo un cliente haga pedidos (RN04), las aplican los procedimientos y los triggers. Los permisos de SQL Server controlan qué puede hacer cada login con la base.

El objetivo es el **mínimo privilegio**: cada login tiene solo los permisos que necesita su función, las escrituras pasan por procedimientos que validan, y los datos sensibles quedan fuera del alcance de quien no los usa.

## 2. Ventajas y aplicaciones

- **Escritura solo a través de procedimientos:** con `EXECUTE` sobre `usp_InsertarCategoria` y sin `INSERT` sobre `CATEGORIA`, el usuario de solo lectura escribe en la tabla solo a través del procedimiento, que valida el nombre. Un `INSERT` directo se rechaza.
- **Permisos administrados por grupo:** el permiso se concede una vez, al rol, y cada usuario lo obtiene al ser miembro. En la demostración, agregar o quitar un usuario del rol le da o le quita el acceso, sin tocar permisos.
- **Granularidad:** los permisos se conceden por objeto y por acción. El usuario de solo lectura puede ejecutar el alta de categorías pero no la baja, del mismo ABM, y el miembro de `rol_lectura_libros` puede leer `LIBRO` pero no modificarlo.
- **Protección de datos sensibles:** el miembro del rol lee el catálogo, pero no `USUARIO`, que guarda los datos personales de los clientes y el hash de sus contraseñas.
- **Separación de funciones:** un administrador de la base (`db_owner`) no necesita el rol `sysadmin` de toda la instancia, y una cuenta de consulta no necesita escribir.
- **Trazabilidad junto con la auditoría:** la auditoría guarda `ORIGINAL_LOGIN()`, el login que se autenticó, que no cambia aunque la sesión suplante a otro usuario. Cada evento queda asociado a una identidad verificada por el servidor.

## 3. Implementación en SQL Server Express

SQL Server Express tiene el mismo modelo de seguridad y el mismo T-SQL que las demás ediciones: logins, usuarios, roles fijos y definidos por el usuario, `GRANT`, `DENY`, `REVOKE` y `EXECUTE AS`. Todas las evidencias se obtuvieron en SQL Server 2025 Express Edition.

```sql
-- Patrón de los scripts del proyecto, resumido de los dos casos
CREATE LOGIN usuario_lectura WITH PASSWORD = N'...', CHECK_POLICY = ON;   -- autenticación
CREATE USER usuario_lectura FOR LOGIN usuario_lectura;                     -- autorización

ALTER ROLE db_datareader ADD MEMBER usuario_lectura;                       -- rol fijo
GRANT EXECUTE ON OBJECT::dbo.usp_InsertarCategoria TO usuario_lectura;     -- permiso sobre un objeto

CREATE ROLE rol_lectura_libros AUTHORIZATION dbo;                          -- rol propio
GRANT SELECT ON OBJECT::dbo.LIBRO TO rol_lectura_libros;
ALTER ROLE rol_lectura_libros ADD MEMBER usuario_con_rol;

EXECUTE AS USER = 'usuario_lectura';    -- probar con los permisos de otro usuario
INSERT INTO dbo.CATEGORIA (nombre) VALUES ('...');                         -- rechazado
REVERT;
```

Recursos que usan los scripts del proyecto:

- **Modos de autenticación:** solo Windows, o mixto (Windows y SQL Server). La instancia de las evidencias es solo Windows: ahí los logins de SQL Server se crean, pero no pueden conectarse. Usarlos exige activar el modo mixto y reiniciar el servicio; las demostraciones no lo necesitan, porque suplantan a cada usuario con `EXECUTE AS USER`.
- **Roles fijos de base de datos:** `db_owner` permite cualquier acción en la base, `db_datareader` concede `SELECT` sobre todas las tablas y vistas, y `db_datawriter`, `INSERT`, `UPDATE` y `DELETE`. `ALTER ROLE ... ADD MEMBER` existe desde SQL Server 2012, la versión mínima del proyecto.
- **Encadenamiento de propiedad:** cuando un procedimiento accede a un objeto del mismo dueño, SQL Server solo comprueba el permiso sobre el procedimiento. Como todos los objetos del proyecto están en `dbo`, basta el permiso sobre el procedimiento. La cadena no alcanza al SQL dinámico.
- **`DENY` prevalece sobre `GRANT`:** también sobre el que da un rol y para un miembro de `db_owner`. `dbo`, y con él los logins de `sysadmin`, tiene todos los permisos en su base y no admite `DENY`.
- **Error 229:** el permiso se comprueba antes de ejecutar, así que la sentencia rechazada no cambia nada ni anula la transacción. Por eso las demostraciones siguen después de cada error y terminan en su propio `ROLLBACK`.
- **`EXECUTE AS USER` y `REVERT`:** la sesión pasa a tener los permisos del usuario suplantado dentro de la base actual, y `REVERT` la devuelve al original. Requiere el permiso `IMPERSONATE`, que tienen los miembros de `db_owner`. La suplantación sigue activa aun después de un error, así que el `REVERT` va fuera del `TRY`; mientras dura, `ORIGINAL_LOGIN()` sigue devolviendo el login real.
- **`HAS_PERMS_BY_NAME` e `IS_ROLEMEMBER`:** las demostraciones los consultan bajo la suplantación para ver los permisos efectivos y la pertenencia a roles de cada usuario, sumando lo que hereda de sus roles.
- **Los logins son objetos del servidor:** borrar la base no los elimina. Los scripts borran primero el usuario y después el login, y se pueden ejecutar varias veces.
- **Contraseñas:** las de los scripts son de ejemplo. En un despliegue real se definen al instalar, o se usan logins de Windows.

## 4. Casos concretos aplicados al sistema de ventas

- **[`usuarios_admin_y_lectura`](usuarios_admin_y_lectura/)**: el administrador es miembro de `db_owner`, y el usuario de solo lectura, de `db_datareader`, con el permiso `EXECUTE` sobre el alta de categorías de [`abm_categorias`](../procedimientos_funciones/abm_categorias/) como única excepción. La demostración muestra que el `INSERT` directo sobre `CATEGORIA` funciona para el administrador y se rechaza para el de solo lectura, que sí da de alta la categoría con el procedimiento (RN09), puede leer y no puede eliminar. Resultado: 5 de 5 pasos con el resultado esperado.
  [`script.sql`](usuarios_admin_y_lectura/script.sql) · [`demostracion.sql`](usuarios_admin_y_lectura/demostracion.sql) · [`evidencias/demostracion.md`](usuarios_admin_y_lectura/evidencias/demostracion.md)

- **[`rol_lectura_libros`](rol_lectura_libros/)**: un rol con solo `SELECT` sobre `LIBRO`, para quien consulta el catálogo desde otro sistema. El miembro lee los libros y el que no es miembro es rechazado; el miembro no lee `USUARIO` ni modifica `LIBRO`, y entrar o salir del rol da o quita el acceso. Resultado: 6 de 6 pasos con el resultado esperado.
  [`script.sql`](rol_lectura_libros/script.sql) · [`demostracion.sql`](rol_lectura_libros/demostracion.sql) · [`evidencias/demostracion.md`](rol_lectura_libros/evidencias/demostracion.md)

- **[Auditoría bajo `EXECUTE AS`](../triggers_auditoria/auditar_precio_publicacion/)**, implementada en el tema de triggers de auditoría: en el caso 6 de su demostración, un usuario con permisos solo sobre `PUBLICACION` cambia un precio. El trigger registra el evento aunque el usuario no tenga permisos sobre la auditoría, gracias al encadenamiento de propiedad, y el evento guarda el login real. Resultado de la demostración: 26 de 26 comprobaciones.
  [`script.sql`](../triggers_auditoria/auditar_precio_publicacion/script.sql) · [`demostracion.sql`](../triggers_auditoria/auditar_precio_publicacion/demostracion.sql) · [`evidencias/demostracion.md`](../triggers_auditoria/auditar_precio_publicacion/evidencias/demostracion.md)
