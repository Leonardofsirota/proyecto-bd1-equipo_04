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

IF OBJECT_ID(N'dbo.trg_PUBLICACION_AuditoriaPrecio', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PUBLICACION_AuditoriaPrecio;
GO

-- Registra cada cambio de precio de una publicación: el valor anterior, el nuevo,
-- quién lo cambió y cuándo. Cada renglón congela el precio de su venta (RN26), pero
-- la publicación solo guarda el vigente: sin este registro se pierde qué precio
-- había antes.
-- UPDATE(precio) solo dice que la columna figura en el SET. El filtro con EXCEPT
-- descarta las filas cuyo precio no cambió, como en precio = precio: si ninguna
-- cambió, no hay evento.
-- origen queda en NULL: ningún trigger de consistencia cambia precios.
-- No lanza errores: solo registra. Corre dentro de la transacción de la sentencia,
-- así que, si otro trigger la rechaza o el llamador la revierte, el evento también
-- se revierte.
CREATE TRIGGER dbo.trg_PUBLICACION_AuditoriaPrecio
ON dbo.PUBLICACION
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(precio)
        RETURN;

    DECLARE @Cambios dbo.AuditoriaCambioType;

    -- En un UPDATE, inserted y deleted tienen las mismas filas: la operación es
    -- siempre U. La intercalación BIN2 hace que la comparación sea exacta.
    INSERT INTO @Cambios
    (
        registro_id,
        operacion,
        columna,
        valor_anterior,
        valor_nuevo
    )
    SELECT
        I.publicacion_id,
        'U',
        V.columna,
        V.anterior,
        V.nuevo
    FROM inserted AS I
    INNER JOIN deleted AS D
        ON D.publicacion_id = I.publicacion_id
    CROSS APPLY (
        VALUES
            ('precio', CONVERT(VARCHAR(255), D.precio), CONVERT(VARCHAR(255), I.precio))
    ) AS V (columna, anterior, nuevo)
    WHERE EXISTS (
        SELECT V.anterior COLLATE Latin1_General_BIN2
        EXCEPT
        SELECT V.nuevo COLLATE Latin1_General_BIN2
    );

    IF EXISTS (SELECT 1 FROM @Cambios)
        EXEC dbo.usp_RegistrarAuditoria
            @Tabla = 'PUBLICACION',
            @Origen = NULL,
            @Cambios = @Cambios;
END;
GO

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
