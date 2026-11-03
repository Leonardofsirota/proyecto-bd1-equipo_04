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

-- Se crea en sql/ddl/triggers-consistencia.sql, y el trigger lo nombra para saber
-- qué provocó cada cambio. Con un OBJECT_ID NULL, TRIGGER_NESTLEVEL no mide si ese
-- trigger está en la pila, y el origen quedaría mal registrado sin dar error.
IF OBJECT_ID(N'dbo.trg_PAGO_ConfirmarPedido', N'TR') IS NULL
BEGIN
    RAISERROR(N'Faltan triggers: ejecutar antes sql/ddl/triggers-consistencia.sql. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF OBJECT_ID(N'dbo.trg_PEDIDO_Auditoria', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PEDIDO_Auditoria;
GO

-- Registra cada cambio de estado de un pedido y de su fecha_pedido. PEDIDO solo
-- guarda la fecha en que se creó: la confirmación, la entrega y la cancelación
-- (RN19, RN20, RN37) no tienen fecha ni autor en ningún otro lugar. fecha_pedido es
-- lo único que trg_PEDIDO_Transicion deja cambiar además del estado, y moverla altera
-- el plazo de la reserva (RN34).
-- El estado se guarda por el nombre de PEDIDO_ESTADO, y la fecha con el estilo 121.
-- origen es trg_PAGO_ConfirmarPedido cuando la confirmación la provocó la aprobación
-- del pago, y NULL en una sentencia directa o de un procedimiento.
-- No audita INSERT, porque el pedido ya guarda su cliente y su fecha, ni DELETE,
-- porque un pedido con renglones o pagos no se puede borrar.
-- No lanza errores: solo registra. Corre dentro de la transacción de la sentencia,
-- así que, si otro trigger la rechaza o el llamador la revierte, el evento también
-- se revierte.
CREATE TRIGGER dbo.trg_PEDIDO_Auditoria
ON dbo.PEDIDO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- UPDATE() solo dice que la columna figura en el SET. El filtro con EXCEPT
    -- descarta los valores que no cambiaron, como en fecha_pedido = fecha_pedido.
    IF NOT (UPDATE(pedido_estado_id) OR UPDATE(fecha_pedido))
        RETURN;

    DECLARE @Cambios dbo.AuditoriaCambioType;
    DECLARE @Origen VARCHAR(128) =
        CASE
            WHEN TRIGGER_NESTLEVEL(OBJECT_ID(N'dbo.trg_PAGO_ConfirmarPedido')) > 0 THEN 'trg_PAGO_ConfirmarPedido'
        END;

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
        I.pedido_id,
        'U',
        V.columna,
        V.anterior,
        V.nuevo
    FROM inserted AS I
    INNER JOIN deleted AS D
        ON D.pedido_id = I.pedido_id
    INNER JOIN dbo.PEDIDO_ESTADO AS ANTERIOR
        ON ANTERIOR.pedido_estado_id = D.pedido_estado_id
    INNER JOIN dbo.PEDIDO_ESTADO AS NUEVO
        ON NUEVO.pedido_estado_id = I.pedido_estado_id
    CROSS APPLY (
        VALUES
            ('estado', ANTERIOR.nombre, NUEVO.nombre),
            ('fecha_pedido', CONVERT(VARCHAR(255), D.fecha_pedido, 121), CONVERT(VARCHAR(255), I.fecha_pedido, 121))
    ) AS V (columna, anterior, nuevo)
    WHERE EXISTS (
        SELECT V.anterior COLLATE Latin1_General_BIN2
        EXCEPT
        SELECT V.nuevo COLLATE Latin1_General_BIN2
    );

    IF EXISTS (SELECT 1 FROM @Cambios)
        EXEC dbo.usp_RegistrarAuditoria
            @Tabla = 'PEDIDO',
            @Origen = @Origen,
            @Cambios = @Cambios;
END;
GO

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
