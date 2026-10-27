CREATE OR ALTER FUNCTION dbo.fn_PorcentajeDescuentoCliente
(
    @UsuarioId INT
)
RETURNS DECIMAL(5, 2)
AS
BEGIN
    DECLARE @TotalHistorico DECIMAL(18, 2);
    DECLARE @Descuento DECIMAL(5, 2);

    SELECT
        @TotalHistorico =
            COALESCE(
                SUM(PD.cantidad * PD.precio_unitario),
                0
            )
    FROM dbo.PEDIDO AS P
    INNER JOIN dbo.PEDIDO_DETALLE AS PD
        ON PD.pedido_id = P.pedido_id
    WHERE P.usuario_id = @UsuarioId;

    SET @Descuento =
        CASE
            WHEN @TotalHistorico <= 100000 THEN 0
            WHEN @TotalHistorico <= 200000 THEN 5
            ELSE 10
        END;

    RETURN @Descuento;
END;
GO