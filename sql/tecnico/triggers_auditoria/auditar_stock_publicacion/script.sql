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

-- Se crean en sql/ddl/triggers-consistencia.sql, y el trigger los nombra para saber
-- qué provocó cada cambio. Con un OBJECT_ID NULL, TRIGGER_NESTLEVEL no mide si ese
-- trigger está en la pila, y el origen quedaría mal registrado sin dar error.
IF OBJECT_ID(N'dbo.trg_PUBLICACION_Agotada', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.trg_USUARIO_Baja', N'TR') IS NULL
   OR OBJECT_ID(N'dbo.trg_PEDIDO_DescontarStock', N'TR') IS NULL
BEGIN
    RAISERROR(N'Faltan triggers: ejecutar antes sql/ddl/triggers-consistencia.sql. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF OBJECT_ID(N'dbo.trg_PUBLICACION_AuditoriaStock', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PUBLICACION_AuditoriaStock;
GO

-- Registra los cambios de stock, disponibilidad y baja de una publicación, y el
-- borrado de una publicación con todos sus valores (RN12, RN13, RN14, RN28).
-- El stock baja con cada venta y lo ajusta el vendedor: el origen separa los
-- descuentos por venta de los ajustes manuales, que son los que hay que poder
-- explicar. El precio no se registra en un UPDATE: es de
-- trg_PUBLICACION_AuditoriaPrecio. En un DELETE se registran todas las columnas,
-- también el precio, porque es la última versión de la fila.
-- origen es el trigger de consistencia que provocó el cambio, del más interno al
-- más externo: trg_PUBLICACION_Agotada (stock en cero), trg_USUARIO_Baja (baja del
-- vendedor) o trg_PEDIDO_DescontarStock (venta). NULL si fue una sentencia directa.
-- En una venta que agota la publicación hay dos eventos: el del stock, provocado por
-- trg_PEDIDO_DescontarStock, y el de la disponibilidad, por trg_PUBLICACION_Agotada.
-- No lanza errores: solo registra. Corre dentro de la transacción de la sentencia,
-- así que, si otro trigger la rechaza o el llamador la revierte, el evento también
-- se revierte.
CREATE TRIGGER dbo.trg_PUBLICACION_AuditoriaStock
ON dbo.PUBLICACION
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- El trigger también se dispara con una sentencia que no afecta filas, como el
    -- UPDATE de trg_PUBLICACION_Agotada cuando ninguna publicación se agotó.
    IF NOT EXISTS (SELECT 1 FROM deleted)
        RETURN;

    -- Un UPDATE que no menciona ninguna de las tres columnas no se registra. En un
    -- DELETE, inserted está vacía y UPDATE() no se consulta.
    IF EXISTS (SELECT 1 FROM inserted)
       AND NOT (UPDATE(stock) OR UPDATE(disponible) OR UPDATE(fecha_eliminacion))
        RETURN;

    DECLARE @Cambios dbo.AuditoriaCambioType;
    DECLARE @Origen VARCHAR(128) =
        CASE
            WHEN TRIGGER_NESTLEVEL(OBJECT_ID(N'dbo.trg_PUBLICACION_Agotada')) > 0 THEN 'trg_PUBLICACION_Agotada'
            WHEN TRIGGER_NESTLEVEL(OBJECT_ID(N'dbo.trg_USUARIO_Baja')) > 0 THEN 'trg_USUARIO_Baja'
            WHEN TRIGGER_NESTLEVEL(OBJECT_ID(N'dbo.trg_PEDIDO_DescontarStock')) > 0 THEN 'trg_PEDIDO_DescontarStock'
        END;

    -- No se dispara con INSERT, así que deleted siempre tiene la fila: sin su par en
    -- inserted, es un DELETE. Un UPDATE guarda solo stock, disponible y
    -- fecha_eliminacion. Un DELETE guarda todas, y el filtro EXCEPT descarta las que
    -- valían NULL, como la fecha de baja de una publicación vigente. La intercalación
    -- BIN2 hace que la comparación sea exacta.
    INSERT INTO @Cambios
    (
        registro_id,
        operacion,
        columna,
        valor_anterior,
        valor_nuevo
    )
    SELECT
        D.publicacion_id,
        CASE WHEN I.publicacion_id IS NULL THEN 'D' ELSE 'U' END,
        V.columna,
        V.anterior,
        V.nuevo
    FROM deleted AS D
    LEFT JOIN inserted AS I
        ON I.publicacion_id = D.publicacion_id
    LEFT JOIN dbo.CONDICION AS CA
        ON CA.condicion_id = D.condicion_id
    LEFT JOIN dbo.CONDICION AS CN
        ON CN.condicion_id = I.condicion_id
    CROSS APPLY (
        VALUES
            ('stock', CONVERT(VARCHAR(255), D.stock), CONVERT(VARCHAR(255), I.stock)),
            ('disponible', CONVERT(VARCHAR(255), D.disponible), CONVERT(VARCHAR(255), I.disponible)),
            ('fecha_eliminacion', CONVERT(VARCHAR(255), D.fecha_eliminacion, 121), CONVERT(VARCHAR(255), I.fecha_eliminacion, 121)),
            ('usuario_id', CONVERT(VARCHAR(255), D.usuario_id), CONVERT(VARCHAR(255), I.usuario_id)),
            ('libro_id', CONVERT(VARCHAR(255), D.libro_id), CONVERT(VARCHAR(255), I.libro_id)),
            ('condicion', CA.nombre, CN.nombre),
            ('precio', CONVERT(VARCHAR(255), D.precio), CONVERT(VARCHAR(255), I.precio)),
            ('fecha_creacion', CONVERT(VARCHAR(255), D.fecha_creacion, 121), CONVERT(VARCHAR(255), I.fecha_creacion, 121))
    ) AS V (columna, anterior, nuevo)
    WHERE (
              I.publicacion_id IS NULL
           OR V.columna IN ('stock', 'disponible', 'fecha_eliminacion')
          )
      AND EXISTS (
              SELECT V.anterior COLLATE Latin1_General_BIN2
              EXCEPT
              SELECT V.nuevo COLLATE Latin1_General_BIN2
          );

    IF EXISTS (SELECT 1 FROM @Cambios)
        EXEC dbo.usp_RegistrarAuditoria
            @Tabla = 'PUBLICACION',
            @Origen = @Origen,
            @Cambios = @Cambios;
END;
GO

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
