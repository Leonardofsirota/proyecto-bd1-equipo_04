CREATE OR ALTER FUNCTION dbo.fn_TotalPedido
(
    @PedidoId INT
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    DECLARE @Total DECIMAL(18, 2);

    SELECT
        @Total = COALESCE(
            SUM(PD.cantidad * PD.precio_unitario),
            0
        )
    FROM dbo.PEDIDO_DETALLE AS PD
    WHERE PD.pedido_id = @PedidoId;

    RETURN @Total;
END;
GO