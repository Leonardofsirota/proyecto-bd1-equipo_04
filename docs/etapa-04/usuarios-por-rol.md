# Usuarios por rol - Etapa 4

Este documento explica la consulta [`administrador/usuarios-por-rol.sql`](../../sql/consultas/administrador/usuarios-por-rol.sql), que resuelve el caso de uso [Consultar usuarios por rol](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Lista los usuarios de un rol, o los de todos los roles, con sus datos de contacto y si están activos o dados de baja. No muestra el hash de la contraseña. Si el rol indicado no existe o no tiene usuarios, la consulta no devuelve filas.

## 2. Quién la usa

El **Administrador**, como base para gestionar los usuarios y sus roles (RN01, RN02).

## 3. Cómo lo resuelve

- **Rol elegido:** se indica con la variable `@rol`. Con `NULL`, la condición `@rol IS NULL` se cumple para todos los usuarios y el filtro no descarta ninguno.
- **Uniones:** une cada usuario con su rol.
- **Estado:** un `CASE` lo deduce de la fecha de baja: si está vacía, el usuario está activo. Los dados de baja se conservan (RN28).
- **Orden:** por rol, primero los activos, y después por apellido y nombre.

## 4. Resultado esperado

Con `@rol = 'Vendedor'` devuelve 40 usuarios: 38 activos y 2 dados de baja, al final. Los primeros y los últimos son:

|  ID | Nombre   | Apellido | DNI      | Estado       | Fecha de baja |
| --: | -------- | -------- | -------- | ------------ | ------------- |
|   2 | Carlos   | Benítez  | 30112457 | Activo       | —             |
|  47 | Mercedes | Benítez  | 37768066 | Activo       | —             |
|  24 | Miguel   | Benítez  | 41567099 | Activo       | —             |
|   … |          |          |          |              |               |
|  27 | Marcelo  | Cáceres  | 31510573 | Dado de baja | 08/09/2026    |
|  26 | Josefina | Encina   | 22635277 | Dado de baja | 20/06/2026    |

Con `@rol = NULL` devuelve los 500 usuarios: 3 administradores, 457 clientes y 40 vendedores.
