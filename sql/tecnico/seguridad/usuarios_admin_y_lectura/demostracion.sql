USE [sistema-venta-libros];
GO

-- Demostración de los permisos de script.sql. Requiere
-- procedimientos_funciones/abm_categorias/script.sql y script.sql de esta carpeta.
-- Cada paso suplanta a un usuario con EXECUTE AS USER: las sentencias se ejecutan con
-- sus permisos, como si se hubiera conectado con su login, y REVERT vuelve al
-- usuario original. Suplantar requiere el permiso IMPERSONATE sobre el usuario, que
-- tienen los miembros de db_owner.
-- Corre en una transacción que termina en ROLLBACK, así que se puede ejecutar varias
-- veces sin dejar datos en la base. Lo único que no se revierte es el contador
-- IDENTITY: cada ejecución deja un salto en categoria_id. Con XACT_ABORT en OFF, los
-- errores de permisos provocados no anulan la transacción.
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
WHERE DP.name IN (N'usuario_admin', N'usuario_lectura')
ORDER BY DP.name, R.name;

-- Permisos concedidos directamente a cada usuario. CONNECT lo concede CREATE USER.
SELECT
    DP.name AS usuario,
    P.state_desc AS estado,
    P.permission_name AS permiso,
    P.class_desc AS clase,
    OBJECT_SCHEMA_NAME(P.major_id) + '.' + OBJECT_NAME(P.major_id) AS objeto
FROM sys.database_permissions AS P
INNER JOIN sys.database_principals AS DP
    ON DP.principal_id = P.grantee_principal_id
WHERE DP.name IN (N'usuario_admin', N'usuario_lectura')
ORDER BY DP.name, P.class, P.permission_name;
GO

DECLARE @Permisos TABLE
(
    usuario SYSNAME PRIMARY KEY,
    login_suplantado SYSNAME NOT NULL,
    db_owner INT NULL,
    db_datareader INT NULL,
    select_categoria INT NULL,
    insert_categoria INT NULL,
    execute_insertar INT NULL,
    execute_eliminar INT NULL
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
DECLARE @IdProcedimiento INT;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Permisos efectivos de cada usuario: HAS_PERMS_BY_NAME e IS_ROLEMEMBER se
    -- evalúan para el usuario suplantado.
    EXECUTE AS USER = 'usuario_admin';

    INSERT INTO @Permisos
    VALUES
    (
        USER_NAME(),
        SUSER_SNAME(),
        IS_ROLEMEMBER('db_owner'),
        IS_ROLEMEMBER('db_datareader'),
        HAS_PERMS_BY_NAME('dbo.CATEGORIA', 'OBJECT', 'SELECT'),
        HAS_PERMS_BY_NAME('dbo.CATEGORIA', 'OBJECT', 'INSERT'),
        HAS_PERMS_BY_NAME('dbo.usp_InsertarCategoria', 'OBJECT', 'EXECUTE'),
        HAS_PERMS_BY_NAME('dbo.usp_EliminarCategoria', 'OBJECT', 'EXECUTE')
    );

    REVERT;

    EXECUTE AS USER = 'usuario_lectura';

    INSERT INTO @Permisos
    VALUES
    (
        USER_NAME(),
        SUSER_SNAME(),
        IS_ROLEMEMBER('db_owner'),
        IS_ROLEMEMBER('db_datareader'),
        HAS_PERMS_BY_NAME('dbo.CATEGORIA', 'OBJECT', 'SELECT'),
        HAS_PERMS_BY_NAME('dbo.CATEGORIA', 'OBJECT', 'INSERT'),
        HAS_PERMS_BY_NAME('dbo.usp_InsertarCategoria', 'OBJECT', 'EXECUTE'),
        HAS_PERMS_BY_NAME('dbo.usp_EliminarCategoria', 'OBJECT', 'EXECUTE')
    );

    REVERT;

    -- Paso 1: el administrador inserta directamente en CATEGORIA
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_admin';
    SET @Usuario = USER_NAME();

    -- REVERT queda fuera del TRY: corre aunque la sentencia falle.
    BEGIN TRY
        INSERT INTO dbo.CATEGORIA (nombre)
        VALUES ('Demo Seguridad Admin Directo');

        SET @Obtenido = 'Permitido';
        SET @Detalle = 'categoria_id ' + CAST(SCOPE_IDENTITY() AS VARCHAR(10));
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (1, @Usuario, 'INSERT directo en CATEGORIA', 'Permitido', @Obtenido, @Detalle);

    -- Paso 2: el usuario de solo lectura intenta el mismo INSERT directo
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_lectura';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        INSERT INTO dbo.CATEGORIA (nombre)
        VALUES ('Demo Seguridad Lectura Directo');

        SET @Obtenido = 'Permitido';
        SET @Detalle = 'categoria_id ' + CAST(SCOPE_IDENTITY() AS VARCHAR(10));
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (2, @Usuario, 'INSERT directo en CATEGORIA', 'Error 229', @Obtenido, @Detalle);

    -- Paso 3: el usuario de solo lectura inserta a través del procedimiento. El
    -- procedimiento devuelve el ID, el nombre y su mensaje de confirmación.
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_lectura';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        EXEC dbo.usp_InsertarCategoria
            @Nombre = 'Demo Seguridad Lectura Procedimiento';

        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    SELECT @IdProcedimiento = categoria_id
    FROM dbo.CATEGORIA
    WHERE nombre = 'Demo Seguridad Lectura Procedimiento';

    IF @Obtenido = 'Permitido'
        SET @Detalle = 'categoria_id ' + CAST(@IdProcedimiento AS VARCHAR(10));

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (3, @Usuario, 'EXEC dbo.usp_InsertarCategoria', 'Permitido', @Obtenido, @Detalle);

    -- Comprobaciones complementarias del usuario de solo lectura
    -- Paso 4: puede leer CATEGORIA (db_datareader)
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_lectura';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        SELECT @Detalle = CAST(COUNT(*) AS VARCHAR(10)) + ' filas leídas'
        FROM dbo.CATEGORIA;

        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (4, @Usuario, 'SELECT sobre CATEGORIA', 'Permitido', @Obtenido, @Detalle);

    -- Paso 5: el permiso EXECUTE es solo sobre usp_InsertarCategoria. Intenta borrar,
    -- con otro procedimiento del ABM, la categoría que acaba de dar de alta.
    SELECT @Obtenido = NULL, @Detalle = NULL;
    EXECUTE AS USER = 'usuario_lectura';
    SET @Usuario = USER_NAME();

    BEGIN TRY
        EXEC dbo.usp_EliminarCategoria
            @CategoriaId = @IdProcedimiento;

        SET @Obtenido = 'Permitido';
    END TRY
    BEGIN CATCH
        SET @Obtenido = 'Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
        SET @Detalle = ERROR_MESSAGE();
    END CATCH;

    REVERT;

    INSERT INTO @Resultados (paso, usuario, operacion, esperado, obtenido, detalle)
    VALUES (5, @Usuario, 'EXEC dbo.usp_EliminarCategoria', 'Error 229', @Obtenido, @Detalle);

    -- Estado antes del ROLLBACK: las altas del administrador y del procedimiento, y
    -- ninguna del INSERT rechazado
    SELECT categoria_id, nombre
    FROM dbo.CATEGORIA
    WHERE nombre LIKE 'Demo Seguridad %'
    ORDER BY categoria_id;

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
    db_owner,
    db_datareader,
    select_categoria,
    insert_categoria,
    execute_insertar,
    execute_eliminar
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
-- transacción abierta y el ROLLBACK no dejó ninguna fila de demostración
SELECT
    USER_NAME() AS usuario_actual,
    @@TRANCOUNT AS transacciones_abiertas,
    (
        SELECT COUNT(*)
        FROM dbo.CATEGORIA
        WHERE nombre LIKE 'Demo Seguridad %'
    ) AS filas_demo;
GO
