USE [sistema-venta-libros];
GO

-- dbo.usp_InsertarCategoria se crea en procedimientos_funciones/abm_categorias/script.sql.
-- SET NOEXEC ON hace que los lotes siguientes se compilen sin ejecutarse.
IF OBJECT_ID(N'dbo.usp_InsertarCategoria', N'P') IS NULL
BEGIN
    RAISERROR(N'Falta dbo.usp_InsertarCategoria: ejecutar antes procedimientos_funciones/abm_categorias/script.sql. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- PERMISOS A NIVEL DE USUARIOS
-- Crea dos usuarios de la base: usuario_admin, que administra la base, y
-- usuario_lectura, que solo puede leer y, como única excepción, ejecutar
-- dbo.usp_InsertarCategoria.
-- Cada usuario de la base se asocia a un login del servidor, con el que se conecta
-- (autenticación de SQL Server). El login autentica; el usuario de la base recibe
-- los permisos. Los logins son objetos del servidor: borrar la base no los elimina.
-- Crearlos requiere el permiso ALTER ANY LOGIN (rol securityadmin o sysadmin).
-- Las contraseñas son de ejemplo y cumplen la política de contraseñas de Windows
-- (CHECK_POLICY = ON). En un despliegue real se definen al instalar y no se guardan
-- en el repositorio.
-- Se puede ejecutar varias veces: borra los usuarios y los logins si ya existen y
-- los vuelve a crear con sus permisos.

-- Primero los usuarios: un login con un usuario asociado en esta base no se borra
-- sin dejarlo huérfano.
IF DATABASE_PRINCIPAL_ID(N'usuario_admin') IS NOT NULL
    DROP USER usuario_admin;

IF DATABASE_PRINCIPAL_ID(N'usuario_lectura') IS NOT NULL
    DROP USER usuario_lectura;
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'usuario_admin')
    DROP LOGIN usuario_admin;

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'usuario_lectura')
    DROP LOGIN usuario_lectura;
GO

-- 1. Logins del servidor
CREATE LOGIN usuario_admin
WITH PASSWORD = N'Gestion.Total#2026',
     DEFAULT_DATABASE = [sistema-venta-libros],
     CHECK_POLICY = ON,
     CHECK_EXPIRATION = OFF;

CREATE LOGIN usuario_lectura
WITH PASSWORD = N'Solo.Mirar#2026',
     DEFAULT_DATABASE = [sistema-venta-libros],
     CHECK_POLICY = ON,
     CHECK_EXPIRATION = OFF;
GO

-- 2. Usuarios de la base, asociados a cada login
CREATE USER usuario_admin
FOR LOGIN usuario_admin
WITH DEFAULT_SCHEMA = dbo;

CREATE USER usuario_lectura
FOR LOGIN usuario_lectura
WITH DEFAULT_SCHEMA = dbo;
GO

-- 3. Permisos
-- Administrador: db_owner puede realizar cualquier acción en la base, incluidas la
-- lectura y la escritura de todas las tablas, la creación de objetos y la gestión
-- de permisos.
ALTER ROLE db_owner ADD MEMBER usuario_admin;

-- Solo lectura: db_datareader concede SELECT sobre todas las tablas y vistas, y
-- ningún permiso de escritura.
ALTER ROLE db_datareader ADD MEMBER usuario_lectura;

-- Única excepción a la solo lectura: puede dar de alta categorías, pero solo a
-- través del procedimiento, que valida el nombre (RN09). El procedimiento y CATEGORIA
-- son de dbo: por el encadenamiento de propiedad, SQL Server comprueba el permiso
-- EXECUTE sobre el procedimiento y no el INSERT sobre la tabla. Un INSERT directo
-- sigue rechazado con el error 229.
GRANT EXECUTE ON OBJECT::dbo.usp_InsertarCategoria TO usuario_lectura;
GO
