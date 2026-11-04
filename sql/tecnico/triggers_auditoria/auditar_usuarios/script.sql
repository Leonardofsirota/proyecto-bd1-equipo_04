USE [sistema-venta-libros];
GO

-- Quedan registradas en el trigger, como en los demás scripts de la etapa: sqlcmd
-- trae QUOTED_IDENTIFIER en OFF.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- dbo.usp_RegistrarAuditoria y el tipo dbo.AuditoriaCambioType se crean en
-- triggers_auditoria/estructura_auditoria/script.sql.
-- SET NOEXEC ON hace que los lotes siguientes se compilen sin ejecutarse.
IF OBJECT_ID(N'dbo.usp_RegistrarAuditoria', N'P') IS NULL
BEGIN
    RAISERROR(N'Falta la estructura de auditoría: ejecutar antes triggers_auditoria/estructura_auditoria/script.sql. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF OBJECT_ID(N'dbo.trg_USUARIO_Auditoria', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_USUARIO_Auditoria;
GO

-- Registra el alta, los cambios y el borrado de cada usuario. USUARIO no tiene fecha
-- de alta: el INSERT registra cuándo se registró cada cliente (RN03). El UPDATE
-- registra los cambios de rol, que solo hace el administrador (RN02), las bajas y
-- reactivaciones (RN28) y los cambios de datos personales y de contacto. El DELETE
-- guarda la última versión de la fila.
-- Datos personales tal cual, la fecha de nacimiento con el estilo 23, el rol por el
-- nombre de USUARIO_ROL y fecha_eliminacion con el estilo 121.
-- La contraseña nunca se guarda, ni siquiera su hash: solo se registra que cambió,
-- con '(oculto)' como valor anterior y '(cambiado)' como nuevo. En un INSERT o un
-- DELETE las dos expresiones dan NULL y la fila no se registra.
-- origen queda en NULL: ningún trigger de consistencia escribe en USUARIO.
-- No lanza errores: solo registra. Corre dentro de la transacción de la sentencia,
-- así que, si otro trigger la rechaza o el llamador la revierte, el evento también
-- se revierte.
CREATE TRIGGER dbo.trg_USUARIO_Auditoria
ON dbo.USUARIO
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cambios dbo.AuditoriaCambioType;

    -- Sin fila en deleted es un INSERT, y sin fila en inserted, un DELETE. El rol se
    -- une con LEFT JOIN, una vez para cada lado, porque en un INSERT o un DELETE uno
    -- de los dos falta. La intercalación BIN2 hace que la comparación sea exacta: la
    -- de la base no distingue mayúsculas.
    INSERT INTO @Cambios
    (
        registro_id,
        operacion,
        columna,
        valor_anterior,
        valor_nuevo
    )
    SELECT
        COALESCE(I.usuario_id, D.usuario_id),
        CASE
            WHEN D.usuario_id IS NULL THEN 'I'
            WHEN I.usuario_id IS NULL THEN 'D'
            ELSE 'U'
        END,
        V.columna,
        V.anterior,
        V.nuevo
    FROM inserted AS I
    FULL OUTER JOIN deleted AS D
        ON D.usuario_id = I.usuario_id
    LEFT JOIN dbo.USUARIO_ROL AS ANTERIOR
        ON ANTERIOR.usuario_rol_id = D.usuario_rol_id
    LEFT JOIN dbo.USUARIO_ROL AS NUEVO
        ON NUEVO.usuario_rol_id = I.usuario_rol_id
    CROSS APPLY (
        VALUES
            ('nombre', D.nombre, I.nombre),
            ('apellido', D.apellido, I.apellido),
            ('dni', D.dni, I.dni),
            ('email', D.email, I.email),
            ('telefono', D.telefono, I.telefono),
            ('fecha_nacimiento', CONVERT(VARCHAR(255), D.fecha_nacimiento, 23), CONVERT(VARCHAR(255), I.fecha_nacimiento, 23)),
            ('rol', ANTERIOR.nombre, NUEVO.nombre),
            ('fecha_eliminacion', CONVERT(VARCHAR(255), D.fecha_eliminacion, 121), CONVERT(VARCHAR(255), I.fecha_eliminacion, 121)),
            (
                'password_hash',
                CASE WHEN D.password_hash <> I.password_hash COLLATE Latin1_General_BIN2 THEN '(oculto)' END,
                CASE WHEN D.password_hash <> I.password_hash COLLATE Latin1_General_BIN2 THEN '(cambiado)' END
            )
    ) AS V (columna, anterior, nuevo)
    WHERE EXISTS (
        SELECT V.anterior COLLATE Latin1_General_BIN2
        EXCEPT
        SELECT V.nuevo COLLATE Latin1_General_BIN2
    );

    IF EXISTS (SELECT 1 FROM @Cambios)
        EXEC dbo.usp_RegistrarAuditoria
            @Tabla = 'USUARIO',
            @Origen = NULL,
            @Cambios = @Cambios;
END;
GO

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
