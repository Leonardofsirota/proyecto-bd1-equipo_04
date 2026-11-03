USE [sistema-venta-libros];
GO

-- PERMISOS A NIVEL DE ROLES
-- Crea el rol rol_lectura_libros, que solo permite leer LIBRO, y dos usuarios de la
-- base: usuario_con_rol, miembro del rol, y usuario_sin_rol, que no recibe ningún
-- permiso. Representa, por ejemplo, a quienes consultan el catálogo desde otro
-- sistema: ven los libros, pero no los usuarios, los pedidos ni los pagos.
-- El permiso se concede una sola vez, al rol, y cada usuario lo obtiene al ser
-- miembro: dar o quitar el acceso es agregarlo al rol o quitarlo, sin tocar permisos.
-- Cada usuario de la base se asocia a un login del servidor, con el que se conecta
-- (autenticación de SQL Server). Los logins son objetos del servidor: borrar la base
-- no los elimina. Crearlos requiere el permiso ALTER ANY LOGIN (rol securityadmin o
-- sysadmin).
-- Las contraseñas son de ejemplo y cumplen la política de contraseñas de Windows
-- (CHECK_POLICY = ON). En un despliegue real se definen al instalar y no se guardan
-- en el repositorio.
-- Se puede ejecutar varias veces: borra los usuarios, el rol y los logins si ya
-- existen y los vuelve a crear con sus permisos.

-- Primero los usuarios: un login con un usuario asociado en esta base no se borra
-- sin dejarlo huérfano, y un rol con miembros no se puede borrar.
IF DATABASE_PRINCIPAL_ID(N'usuario_con_rol') IS NOT NULL
    DROP USER usuario_con_rol;

IF DATABASE_PRINCIPAL_ID(N'usuario_sin_rol') IS NOT NULL
    DROP USER usuario_sin_rol;
GO

-- Si otro usuario quedó como miembro del rol, DROP ROLE falla con el error 15144 y
-- el script se detiene.
IF EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = N'rol_lectura_libros'
      AND type = 'R'
)
    DROP ROLE rol_lectura_libros;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'usuario_con_rol')
    DROP LOGIN usuario_con_rol;

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'usuario_sin_rol')
    DROP LOGIN usuario_sin_rol;
GO

-- 1. Logins del servidor
CREATE LOGIN usuario_con_rol
WITH PASSWORD = N'Lee.Libros#2026',
     DEFAULT_DATABASE = [sistema-venta-libros],
     CHECK_POLICY = ON,
     CHECK_EXPIRATION = OFF;

CREATE LOGIN usuario_sin_rol
WITH PASSWORD = N'Nada.Permitido#2026',
     DEFAULT_DATABASE = [sistema-venta-libros],
     CHECK_POLICY = ON,
     CHECK_EXPIRATION = OFF;
GO

-- 2. Usuarios de la base, asociados a cada login. Un usuario nuevo solo es miembro
-- de public, que no tiene permisos sobre las tablas del sistema de ventas.
CREATE USER usuario_con_rol
FOR LOGIN usuario_con_rol
WITH DEFAULT_SCHEMA = dbo;

CREATE USER usuario_sin_rol
FOR LOGIN usuario_sin_rol
WITH DEFAULT_SCHEMA = dbo;
GO

-- 3. Rol de solo lectura sobre LIBRO
CREATE ROLE rol_lectura_libros AUTHORIZATION dbo;
GO

-- Solo SELECT y solo sobre LIBRO: ningún permiso de escritura ni sobre otras tablas.
GRANT SELECT ON OBJECT::dbo.LIBRO TO rol_lectura_libros;

-- 4. Asignación del rol: solo usuario_con_rol es miembro
ALTER ROLE rol_lectura_libros ADD MEMBER usuario_con_rol;
GO
