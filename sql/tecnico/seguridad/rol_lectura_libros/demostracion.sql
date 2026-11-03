USE [sistema-venta-libros];
GO

-- Demostración de los permisos de script.sql. Requiere script.sql de esta carpeta.
-- Cada paso suplanta a un usuario con EXECUTE AS USER: las sentencias se ejecutan con
-- sus permisos, como si se hubiera conectado con su login, y REVERT vuelve al
-- usuario original. Suplantar requiere el permiso IMPERSONATE sobre el usuario, que
-- tienen los miembros de db_owner.
-- Corre en una transacción que termina en ROLLBACK: si una escritura que debería
-- fallar se aceptara, no quedaría en la base. Los pasos 5 y 6 agregan a
-- usuario_sin_rol al rol y lo quitan, y el ROLLBACK también revierte esos cambios si
-- algo falla en el medio. Con XACT_ABORT en OFF, los errores de permisos provocados
-- no anulan la transacción.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

-- Usuarios, logins y roles que creó script.sql
SELECT
    DP.name AS usuario,
    SP.name AS login,
    SP.type_desc AS tipo_login,
    R.name AS rol
FROM sys.database_principals AS DP
LEFT JOIN sys.server_principals AS SP
    ON SP.sid = DP.sid
LEFT JOIN sys.database_role_members AS RM
    ON RM.member_principal_id = DP.principal_id
LEFT JOIN sys.database_principals AS R
    ON R.principal_id = RM.role_principal_id
WHERE DP.name IN (N'usuario_con_rol', N'usuario_sin_rol')
ORDER BY DP.name;

-- Permisos concedidos directamente al rol y a cada usuario. CONNECT lo concede
-- CREATE USER.
SELECT
    DP.name AS principal,
    DP.type_desc AS tipo,
    P.state_desc AS estado,
    P.permission_name AS permiso,
    P.class_desc AS clase,
    OBJECT_SCHEMA_NAME(P.major_id) + '.' + OBJECT_NAME(P.major_id) AS objeto
FROM sys.database_permissions AS P
INNER JOIN sys.database_principals AS DP
    ON DP.principal_id = P.grantee_principal_id
WHERE DP.name IN (N'rol_lectura_libros', N'usuario_con_rol', N'usuario_sin_rol')
ORDER BY DP.type, DP.name, P.class, P.permission_name;
GO

DECLARE @Permisos TABLE
(
    usuario SYSNAME PRIMARY KEY,
    login_suplantado SYSNAME NOT NULL,
    miembro_rol INT NULL,
    select_libro INT NULL,
    insert_libro INT NULL,
    update_libro INT NULL,
    delete_libro INT NULL,
    select_usuario INT NULL
);

DECLARE @Resultados TABLE
(
    paso INT PRIMARY KEY,
    usuario SYSNAME NOT NULL,
    operacion VARCHAR(80) NOT NULL,
    esperado VARCHAR(20) NOT NULL,
    obtenido VARCHAR(20) NULL,
    detalle NVARCHAR(4000) NULL
);

DECLARE @Usuario SYSNAME;
DECLARE @Obtenido VARCHAR(20);
DECLARE @Detalle NVARCHAR(4000);

BEGIN TRY
    BEGIN TRANSACTION;

    -- Permisos efectivos de cada usuario: HAS_PERMS_BY_NAME e IS_ROLEMEMBER se
    -- evalúan para el usuario suplantado.
    EXECUTE AS USER = 'usuario_con_rol';

    INSERT INTO @Permisos
    VALUES
    (
        USER_NAME(),
        SUSER_SNAME(),
        IS_ROLEMEMBER('rol_lectura_libros'),
        HAS_PERMS_BY_NAME('dbo.LIBRO', 'OBJECT', 'SELECT'),
        HAS_PERMS_BY_NAME('dbo.LIBRO', 'OBJECT', 'INSERT'),
        HAS_PERMS_BY_NAME('dbo.LIBRO', 'OBJECT', 'UPDATE'),
        HAS_PERMS_BY_NAME('dbo.LIBRO', 'OBJECT', 'DELETE'),
        HAS_PERMS_BY_NAME('dbo.USUARIO', 'OBJECT', 'SELECT')
    );

    REVERT;

    EXECUTE AS USER = 'usuario_sin_rol';

    INSERT INTO @Permisos
    VALUES
    (
        USER_NAME(),
        SUSER_SNAME(),
        IS_ROLEMEMBER('rol_lectura_libros'),
        HAS_PERMS_BY_NAME('dbo.LIBRO', 'OBJECT', 'SELECT'),
        HAS_PERMS_BY_NAME('dbo.LIBRO', 'OBJECT', 'INSERT'),
        HAS_PERMS_BY_NAME('dbo.LIBRO', 'OBJECT', 'UPDATE'),
        HAS_PERMS_BY_NAME('dbo.LIBRO', 'OBJECT', 'DELETE'),
        HAS_PERMS_BY_NAME('dbo.USUARIO', 'OBJECT', 'SELECT')
    );

    REVERT;

    -- Paso 1: el usuario con el rol lee LIBRO. Cuenta las filas y muestra las
    -- primeras cinco.
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_con_rol';
    SET @Usuario = USER_NAME();

    -- REVERT queda fuera del TRY: corre aunque la sentencia falle.
    BEGIN TRY
        SELECT @Detalle = CAST(COUNT(*) AS VARCHAR(10)) + ' filas leídas'
        FROM dbo.LIBRO;

        SELECT TOP (5) libro_id, isbn, titulo, anio_publicacion
        FROM dbo.LIBRO
        ORDER BY libro_id;

        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (1, @Usuario, 'SELECT sobre LIBRO', 'Permitido', @Obtenido, @Detalle);

    -- Paso 2: el usuario sin el rol intenta la misma lectura
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_sin_rol';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        SELECT @Detalle = CAST(COUNT(*) AS VARCHAR(10)) + ' filas leídas'
        FROM dbo.LIBRO;

        SELECT TOP (5) libro_id, isbn, titulo, anio_publicacion
        FROM dbo.LIBRO
        ORDER BY libro_id;

        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (2, @Usuario, 'SELECT sobre LIBRO', 'Error 229', @Obtenido, @Detalle);

    -- Comprobaciones complementarias
    -- Paso 3: el rol solo permite leer LIBRO, no otras tablas
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_con_rol';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        SELECT @Detalle = CAST(COUNT(*) AS VARCHAR(10)) + ' filas leídas'
        FROM dbo.USUARIO;

        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (3, @Usuario, 'SELECT sobre USUARIO', 'Error 229', @Obtenido, @Detalle);

    -- Paso 4: el rol solo permite leer: no puede modificar LIBRO
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_con_rol';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        UPDATE dbo.LIBRO
        SET titulo = titulo + ' (modificado)'
        WHERE libro_id = (SELECT MIN(libro_id) FROM dbo.LIBRO);

        -- @@ROWCOUNT se lee antes de cualquier otra sentencia, que lo reinicia.
        SET @Detalle = CAST(@@ROWCOUNT AS VARCHAR(10)) + ' filas modificadas';
        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (4, @Usuario, 'UPDATE sobre LIBRO', 'Error 229', @Obtenido, @Detalle);

    -- Paso 5: el permiso viene del rol. Al agregar a usuario_sin_rol como miembro,
    -- puede leer LIBRO sin recibir ningún permiso propio.
    ALTER ROLE rol_lectura_libros ADD MEMBER usuario_sin_rol;

    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_sin_rol';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        SELECT @Detalle = CAST(COUNT(*) AS VARCHAR(10)) + ' filas leídas'
        FROM dbo.LIBRO;

        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (5, @Usuario, 'SELECT sobre LIBRO, ya miembro del rol', 'Permitido', @Obtenido, @Detalle);

    -- Paso 6: al quitarlo del rol, pierde el acceso
    ALTER ROLE rol_lectura_libros DROP MEMBER usuario_sin_rol;

    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_sin_rol';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        SELECT @Detalle = CAST(COUNT(*) AS VARCHAR(10)) + ' filas leídas'
        FROM dbo.LIBRO;

        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (6, @Usuario, 'SELECT sobre LIBRO, quitado del rol', 'Error 229', @Obtenido, @Detalle);

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

-- Las variables de tabla conservan sus filas después del ROLLBACK
SELECT
    usuario,
    login_suplantado,
    miembro_rol,
    select_libro,
    insert_libro,
    update_libro,
    delete_libro,
    select_usuario
FROM @Permisos
ORDER BY usuario;

SELECT
    paso,
    usuario,
    operacion,
    esperado,
    obtenido,
    CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END AS resultado,
    detalle
FROM @Resultados
ORDER BY paso;

-- Comprobación final: REVERT devolvió el usuario original, no quedó ninguna
-- transacción abierta, usuario_con_rol sigue siendo el único miembro del rol y
-- ningún título quedó modificado
SELECT
    USER_NAME() AS usuario_actual,
    @@TRANCOUNT AS transacciones_abiertas,
    (
        SELECT COUNT(*)
        FROM sys.database_role_members AS RM
        INNER JOIN sys.database_principals AS R
            ON R.principal_id = RM.role_principal_id
        WHERE R.name = N'rol_lectura_libros'
    ) AS miembros_rol,
    IS_ROLEMEMBER('rol_lectura_libros', 'usuario_con_rol') AS con_rol_es_miembro,
    IS_ROLEMEMBER('rol_lectura_libros', 'usuario_sin_rol') AS sin_rol_es_miembro,
    (
        SELECT COUNT(*)
        FROM dbo.LIBRO
        WHERE titulo LIKE '%(modificado)'
    ) AS filas_demo;
GO
