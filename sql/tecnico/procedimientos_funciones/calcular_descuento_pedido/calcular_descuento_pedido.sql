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

SELECT
    U.usuario_id,
    U.nombre,
    U.apellido,
    dbo.fn_PorcentajeDescuentoCliente(
        U.usuario_id
    ) AS PorcentajeDescuento
FROM dbo.USUARIO AS U;
GO

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

SELECT
    P.pedido_id,
    P.fecha_pedido,
    dbo.fn_TotalPedido(P.pedido_id) AS TotalPedido
FROM dbo.PEDIDO AS P
ORDER BY P.pedido_id;
GO

CREATE OR ALTER FUNCTION dbo.fn_ImporteDescuento
(
    @TotalCompra DECIMAL(18, 2),
    @Porcentaje DECIMAL(5, 2)
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    IF @TotalCompra IS NULL OR @Porcentaje IS NULL
        RETURN NULL;

    IF @TotalCompra < 0 OR @Porcentaje < 0
        RETURN NULL;

    IF @Porcentaje > 100
        RETURN NULL;

    RETURN CAST(
        ROUND(
            @TotalCompra * @Porcentaje / 100.0,
            2
        )
        AS DECIMAL(18, 2)
    );
END;
GO

SELECT
    dbo.fn_PorcentajeDescuentoCliente(1)
        AS PorcentajeDescuento,

    dbo.fn_TotalPedido(1)
        AS TotalPedido,

    dbo.fn_ImporteDescuento(
        dbo.fn_TotalPedido(1),
        dbo.fn_PorcentajeDescuentoCliente(1)
    ) AS ImporteDescuento;
GO
