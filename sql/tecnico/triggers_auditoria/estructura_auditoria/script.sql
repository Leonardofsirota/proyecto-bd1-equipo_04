USE [sistema-venta-libros];
GO

-- Quedan registradas en cada objeto, como en los demás scripts de la etapa: sqlcmd
-- trae QUOTED_IDENTIFIER en OFF.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Estructura compartida por los triggers de auditoría: dónde se guardan los cambios,
-- quién los hizo y el procedimiento que los registra. Cada trigger se crea en el
-- script.sql de su carpeta, después de este.
-- Se puede ejecutar varias veces: las tablas se crean solo si no existen, así que
-- volver a ejecutarlo no borra la auditoría. Los demás objetos se vuelven a crear.
-- SET NOEXEC ON hace que los lotes siguientes se compilen sin ejecutarse.
IF OBJECT_ID(N'dbo.USUARIO', N'U') IS NULL
BEGIN
    RAISERROR(N'Falta la base del sistema: ejecutar antes sistema-venta-libros.sql. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- ----------------------------------------------------------------------------
-- 1. Tablas
--
-- Encabezado y detalle, en 3FN: quién y cuándo dependen del evento (una fila
-- cambiada por una sentencia), no de cada columna cambiada.
-- No tienen claves foráneas hacia las tablas auditadas ni hacia USUARIO: el DELETE
-- de una fila auditada fallaría, y el evento de su borrado no tendría a qué apuntar.
-- ----------------------------------------------------------------------------

-- Un evento por fila cambiada. login_bd lo autentica el servidor, y ORIGINAL_LOGIN()
-- no cambia con EXECUTE AS, a diferencia de SUSER_SNAME(). usuario_id es el usuario
-- del sistema que declaró la aplicación (dbo.fn_UsuarioSesion): NULL si nadie lo
-- declaró. origen es el trigger de consistencia que provocó el cambio, si lo hubo.
IF OBJECT_ID(N'dbo.AUDITORIA', N'U') IS NULL
    CREATE TABLE dbo.AUDITORIA (
        auditoria_id INT IDENTITY(1,1) NOT NULL,
        fecha        DATETIME          NOT NULL CONSTRAINT df_auditoria_fecha    DEFAULT (GETDATE()),
        tabla        VARCHAR(128)      NOT NULL,
        operacion    CHAR(1)           NOT NULL,
        registro_id  INT               NOT NULL,
        login_bd     NVARCHAR(128)     NOT NULL CONSTRAINT df_auditoria_login_bd DEFAULT (ORIGINAL_LOGIN()),
        usuario_id   INT               NULL,
        origen       VARCHAR(128)      NULL,
        CONSTRAINT pk_auditoria           PRIMARY KEY CLUSTERED (auditoria_id),
        CONSTRAINT chk_auditoria_tabla     CHECK (LEN(tabla) > 0),
        CONSTRAINT chk_auditoria_operacion CHECK (operacion IN ('I', 'U', 'D'))
    );
GO

-- Para consultar el historial de una fila.
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.AUDITORIA')
      AND name = N'ix_auditoria_tabla_registro'
)
    CREATE NONCLUSTERED INDEX ix_auditoria_tabla_registro
        ON dbo.AUDITORIA (tabla, registro_id);
GO

-- Un valor por columna cambiada, guardado como texto para que una sola tabla sirva a
-- todas: un INSERT guarda solo valor_nuevo, un DELETE solo valor_anterior y un UPDATE,
-- las dos versiones de las columnas cuyo valor cambió.
IF OBJECT_ID(N'dbo.AUDITORIA_DETALLE', N'U') IS NULL
    CREATE TABLE dbo.AUDITORIA_DETALLE (
        auditoria_detalle_id INT IDENTITY(1,1) NOT NULL,
        auditoria_id         INT               NOT NULL,
        columna              VARCHAR(128)      NOT NULL,
        valor_anterior       VARCHAR(255)      NULL,
        valor_nuevo          VARCHAR(255)      NULL,
        CONSTRAINT pk_auditoria_detalle           PRIMARY KEY CLUSTERED (auditoria_detalle_id),
        CONSTRAINT uq_auditoria_detalle           UNIQUE NONCLUSTERED (auditoria_id, columna),
        CONSTRAINT chk_auditoria_detalle_valores  CHECK (valor_anterior IS NOT NULL OR valor_nuevo IS NOT NULL),
        CONSTRAINT fk_auditoria_detalle_auditoria FOREIGN KEY (auditoria_id) REFERENCES dbo.AUDITORIA (auditoria_id)
    );
GO

-- ----------------------------------------------------------------------------
-- 2. Usuario del sistema
--
-- La aplicación se conecta con un login compartido, que no dice qué cliente o
-- vendedor actuó. Por eso declara el usuario al tomar la conexión, y queda en
-- CONTEXT_INFO, que dura lo que la sesión. Se usa CONTEXT_INFO y no SESSION_CONTEXT
-- por la compatibilidad con SQL Server 2012.
-- Límite: el servidor no verifica el usuario declarado, a diferencia del login.
-- ----------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.fn_UsuarioSesion', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_UsuarioSesion;
GO

-- Devuelve el usuario declarado en la sesión, o NULL si no se declaró o se limpió.
-- CONTEXT_INFO() devuelve 128 bytes rellenos con ceros, y el ID ocupa los 4 primeros.
CREATE FUNCTION dbo.fn_UsuarioSesion()
RETURNS INT
AS
BEGIN
    RETURN NULLIF(CAST(SUBSTRING(CONTEXT_INFO(), 1, 4) AS INT), 0);
END;
GO

IF OBJECT_ID(N'dbo.usp_EstablecerUsuarioSesion', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_EstablecerUsuarioSesion;
GO

-- Declara el usuario del sistema que actúa en la sesión. Con NULL lo limpia.
-- Un usuario inexistente o dado de baja no se declara, y la sesión conserva el
-- valor anterior. SET CONTEXT_INFO hecho dentro de un procedimiento persiste en la
-- sesión después de que termina.
CREATE PROCEDURE dbo.usp_EstablecerUsuarioSesion
    @UsuarioId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Contexto VARBINARY(128);

    IF @UsuarioId IS NULL
    BEGIN
        SET CONTEXT_INFO 0x;
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.USUARIO
        WHERE usuario_id = @UsuarioId
          AND fecha_eliminacion IS NULL
    )
        THROW 50401, 'El usuario no existe o esta dado de baja (RN28).', 1;

    SET @Contexto = CAST(@UsuarioId AS BINARY(4));
    SET CONTEXT_INFO @Contexto;
END;
GO

-- ----------------------------------------------------------------------------
-- 3. Registro de los cambios
-- ----------------------------------------------------------------------------

-- Se elimina antes del tipo porque depende de él.
IF OBJECT_ID(N'dbo.usp_RegistrarAuditoria', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RegistrarAuditoria;
GO

IF TYPE_ID(N'dbo.AuditoriaCambioType') IS NOT NULL
    DROP TYPE dbo.AuditoriaCambioType;
GO

-- Los cambios que un trigger pasa a dbo.usp_RegistrarAuditoria: una fila por cada
-- columna cambiada de cada fila auditada.
CREATE TYPE dbo.AuditoriaCambioType AS TABLE
(
    registro_id    INT          NOT NULL,
    operacion      CHAR(1)      NOT NULL,
    columna        VARCHAR(128) NOT NULL,
    valor_anterior VARCHAR(255) NULL,
    valor_nuevo    VARCHAR(255) NULL,
    PRIMARY KEY (registro_id, operacion, columna)
);
GO

-- Registra los cambios de una sentencia: un evento por fila y, en el detalle, sus
-- columnas cambiadas. fecha y login_bd salen de los DEFAULT de AUDITORIA, y
-- usuario_id, de la sesión.
-- No abre una transacción ni usa TRY: corre dentro de la transacción del trigger que
-- lo llama. Si la sentencia que disparó el trigger se revierte, sus eventos también,
-- así que una operación revertida no deja registros.
-- Los triggers y este procedimiento son de dbo, igual que las tablas: el usuario que
-- modifica una tabla auditada no necesita permisos sobre AUDITORIA.
CREATE PROCEDURE dbo.usp_RegistrarAuditoria
    @Tabla VARCHAR(128),
    @Origen VARCHAR(128),
    @Cambios dbo.AuditoriaCambioType READONLY
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UsuarioId INT = dbo.fn_UsuarioSesion();
    DECLARE @Eventos TABLE
    (
        auditoria_id INT     NOT NULL PRIMARY KEY,
        registro_id  INT     NOT NULL,
        operacion    CHAR(1) NOT NULL
    );

    -- Llamado directamente, registraría cambios que no ocurrieron.
    IF TRIGGER_NESTLEVEL() = 0
        THROW 50402, 'usp_RegistrarAuditoria: solo se llama desde un trigger de auditoria.', 1;

    -- OUTPUT devuelve el ID de cada evento junto con su fila, para unirle el detalle.
    INSERT INTO dbo.AUDITORIA
    (
        tabla,
        operacion,
        registro_id,
        usuario_id,
        origen
    )
    OUTPUT
        inserted.auditoria_id,
        inserted.registro_id,
        inserted.operacion
    INTO @Eventos (auditoria_id, registro_id, operacion)
    SELECT
        @Tabla,
        C.operacion,
        C.registro_id,
        @UsuarioId,
        @Origen
    FROM @Cambios AS C
    GROUP BY
        C.registro_id,
        C.operacion
    ORDER BY C.registro_id;

    INSERT INTO dbo.AUDITORIA_DETALLE
    (
        auditoria_id,
        columna,
        valor_anterior,
        valor_nuevo
    )
    SELECT
        E.auditoria_id,
        C.columna,
        C.valor_anterior,
        C.valor_nuevo
    FROM @Cambios AS C
    INNER JOIN @Eventos AS E
        ON E.registro_id = C.registro_id
       AND E.operacion = C.operacion
    ORDER BY
        E.auditoria_id,
        C.columna;
END;
GO

-- ----------------------------------------------------------------------------
-- 4. Consulta
-- ----------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.vw_Auditoria', N'V') IS NOT NULL
    DROP VIEW dbo.vw_Auditoria;
GO

-- Una fila por columna cambiada, con los datos de su evento y el email del usuario
-- del sistema. LEFT JOIN con USUARIO: el usuario puede no estar declarado o haberse
-- borrado, y el evento conserva su ID.
CREATE VIEW dbo.vw_Auditoria
AS
SELECT
    A.auditoria_id,
    A.fecha,
    A.tabla,
    A.operacion,
    A.registro_id,
    AD.columna,
    AD.valor_anterior,
    AD.valor_nuevo,
    A.login_bd,
    A.usuario_id,
    U.email AS usuario_email,
    A.origen
FROM dbo.AUDITORIA AS A
INNER JOIN dbo.AUDITORIA_DETALLE AS AD
    ON AD.auditoria_id = A.auditoria_id
LEFT JOIN dbo.USUARIO AS U
    ON U.usuario_id = A.usuario_id;
GO

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
