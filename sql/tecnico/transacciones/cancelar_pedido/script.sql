USE [sistema-venta-libros];
GO

-- Queda registrada en el procedimiento, como en los demás scripts de la etapa:
-- sqlcmd trae QUOTED_IDENTIFIER en OFF.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.usp_CancelarPedido', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CancelarPedido;
GO

-- CANCELAR un pedido
-- El cliente dueño cancela un pedido Pendiente (RN15, RN20), con la reserva vigente o
-- vencida. Un pedido Confirmado, Entregado o Cancelado no se cancela: no hay
-- devoluciones, y un pedido Confirmado ya descontó stock.
-- No toca el stock: solo baja al confirmar el pedido (RN14), y la reserva se libera
-- sola porque dbo.fn_VencimientoReserva devuelve NULL para un pedido que no está
-- Pendiente, y dbo.fn_StockLibre deja de restarla (RN33).
-- Tampoco toca un pago Pendiente: la pasarela todavía puede aprobarlo. Si lo pasara a
-- Cancelado, esa aprobación recibiría el error 50123 de dbo.usp_RegistrarVenta y se
-- perdería el rastro del cobro. Queda abierto, y dbo.usp_RegistrarVenta lo resuelve:
-- aprobado, el pago queda Cancelado con fecha_pago, como cobro sin venta (RN37);
-- rechazado o cancelado, solo cambia el pago. El pedido cancelado no admite pagos
-- nuevos (usp_IniciarPago 50112, trg_PAGO_Alta 50232).
-- Devuelve el ID del pedido, su estado, la cantidad de pagos Pendiente y un mensaje.
CREATE PROCEDURE dbo.usp_CancelarPedido
    @PedidoId INT,
    @UsuarioId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoPedido VARCHAR(50);
    DECLARE @PagosPendientes INT;

    -- Sin bloqueo: el dueño de un pedido no cambia (trg_PEDIDO_Transicion, 50214).
    IF NOT EXISTS (
        SELECT 1
        FROM dbo.PEDIDO
        WHERE pedido_id = @PedidoId
          AND usuario_id = @UsuarioId
    )
        THROW 50311, 'El pedido no existe o no pertenece al cliente.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- La lectura y el UPDATE van en la misma transacción porque, entre comprobar
        -- Pendiente y escribir Cancelado, una aprobación podría confirmar el pedido.
        -- UPDLOCK retiene la fila hasta el COMMIT y la aprobación espera. Sin él, con
        -- READ_COMMITTED_SNAPSHOT la lectura ve la versión confirmada anterior, y el
        -- rechazo llega de trg_PEDIDO_Transicion (50215) en lugar de 50312.
        -- Es el primer y único bloqueo, el mismo primer paso que usp_IniciarPago y
        -- usp_RegistrarVenta: se respeta el orden PEDIDO, PAGO y PUBLICACION.
        SELECT @EstadoPedido = PE.nombre
        FROM dbo.PEDIDO AS P WITH (UPDLOCK, ROWLOCK)
        INNER JOIN dbo.PEDIDO_ESTADO AS PE
            ON PE.pedido_estado_id = P.pedido_estado_id
        WHERE P.pedido_id = @PedidoId;

        IF @EstadoPedido IS NULL OR @EstadoPedido <> 'Pendiente'
            THROW 50312, 'Solo se puede cancelar un pedido pendiente.', 1;

        UPDATE dbo.PEDIDO
        SET pedido_estado_id = (
                SELECT PE.pedido_estado_id
                FROM dbo.PEDIDO_ESTADO AS PE
                WHERE PE.nombre = 'Cancelado'
            )
        WHERE pedido_id = @PedidoId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;

    SELECT @PagosPendientes = COUNT(*)
    FROM dbo.PAGO AS PG
    INNER JOIN dbo.PAGO_ESTADO AS PGE
        ON PGE.pago_estado_id = PG.pago_estado_id
    WHERE PG.pedido_id = @PedidoId
      AND PGE.nombre = 'Pendiente';

    SELECT
        P.pedido_id,
        PE.nombre AS estado_pedido,
        @PagosPendientes AS pagos_pendientes,
        CASE
            WHEN @PagosPendientes > 0
                THEN 'Pedido cancelado: el pago pendiente sigue abierto y, si se aprueba, '
                   + 'queda como cobro sin venta'
            ELSE 'Pedido cancelado correctamente'
        END AS mensaje
    FROM dbo.PEDIDO AS P
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.pedido_estado_id = P.pedido_estado_id
    WHERE P.pedido_id = @PedidoId;
END;
GO
