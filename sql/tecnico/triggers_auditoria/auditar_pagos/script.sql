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

IF OBJECT_ID(N'dbo.trg_PAGO_Auditoria', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PAGO_Auditoria;
GO

-- Registra cada intento de pago y cómo se resolvió. PAGO solo fecha la aprobación:
-- un rechazo o una cancelación no tienen fecha ni autor en ningún otro lugar. El
-- evento muestra quién inició y quién resolvió cada intento (RN23 a RN25, RN29) y el
-- cobro sin venta (RN37), que deja el pago Cancelado con fecha_pago.
-- INSERT: el pedido, el importe, el método y el estado con que nace el pago.
-- UPDATE: el estado, fecha_pago y fecha_creacion, lo único que trg_PAGO_Transicion
-- deja cambiar (50221 rechaza el resto). Mover fecha_creacion altera el plazo de la
-- reserva (RN34).
-- No audita DELETE: trg_PAGO_SinBorrado lo rechaza siempre, así que nunca hay un
-- borrado confirmado que registrar.
-- El estado y el método se guardan por el nombre de su catálogo, el importe como
-- DECIMAL y las fechas con el estilo 121. origen queda en NULL: ningún trigger de
-- consistencia escribe en PAGO.
-- No lanza errores: solo registra. Corre dentro de la transacción de la sentencia,
-- así que, si otro trigger la rechaza o el llamador la revierte, el evento también
-- se revierte.
CREATE TRIGGER dbo.trg_PAGO_Auditoria
ON dbo.PAGO
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cambios dbo.AuditoriaCambioType;

    -- inserted siempre tiene la fila, y deleted solo en un UPDATE: sin fila anterior,
    -- la operación es I. Cada columna lleva la operación en que se registra, y el
    -- filtro deja solo las de la operación de la fila. La intercalación BIN2 hace que
    -- la comparación sea exacta.
    INSERT INTO @Cambios
    (
        registro_id,
        operacion,
        columna,
        valor_anterior,
        valor_nuevo
    )
    SELECT
        I.pago_id,
        O.operacion,
        V.columna,
        V.anterior,
        V.nuevo
    FROM inserted AS I
    LEFT JOIN deleted AS D
        ON D.pago_id = I.pago_id
    INNER JOIN dbo.PAGO_ESTADO AS NUEVO
        ON NUEVO.pago_estado_id = I.pago_estado_id
    INNER JOIN dbo.PAGO_METODO AS METODO
        ON METODO.pago_metodo_id = I.pago_metodo_id
    LEFT JOIN dbo.PAGO_ESTADO AS ANTERIOR
        ON ANTERIOR.pago_estado_id = D.pago_estado_id
    CROSS APPLY (
        SELECT CASE WHEN D.pago_id IS NULL THEN 'I' ELSE 'U' END
    ) AS O (operacion)
    CROSS APPLY (
        VALUES
            ('I', 'pedido_id', NULL, CONVERT(VARCHAR(255), I.pedido_id)),
            ('I', 'importe', NULL, CONVERT(VARCHAR(255), I.importe)),
            ('I', 'metodo', NULL, METODO.nombre),
            ('I', 'estado', NULL, NUEVO.nombre),
            ('U', 'estado', ANTERIOR.nombre, NUEVO.nombre),
            ('U', 'fecha_pago', CONVERT(VARCHAR(255), D.fecha_pago, 121), CONVERT(VARCHAR(255), I.fecha_pago, 121)),
            ('U', 'fecha_creacion', CONVERT(VARCHAR(255), D.fecha_creacion, 121), CONVERT(VARCHAR(255), I.fecha_creacion, 121))
    ) AS V (operacion, columna, anterior, nuevo)
    WHERE V.operacion = O.operacion
      AND EXISTS (
              SELECT V.anterior COLLATE Latin1_General_BIN2
              EXCEPT
              SELECT V.nuevo COLLATE Latin1_General_BIN2
          );

    IF EXISTS (SELECT 1 FROM @Cambios)
        EXEC dbo.usp_RegistrarAuditoria
            @Tabla = 'PAGO',
            @Origen = NULL,
            @Cambios = @Cambios;
END;
GO

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
