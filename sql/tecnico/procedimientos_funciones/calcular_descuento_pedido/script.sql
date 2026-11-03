USE [sistema-venta-libros];
GO

-- Reemplazada por dbo.fn_PorcentajeDescuentoPedido.
IF OBJECT_ID(N'dbo.fn_PorcentajeDescuentoCliente', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_PorcentajeDescuentoCliente;
GO

IF OBJECT_ID(N'dbo.fn_TotalPedido', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_TotalPedido;
GO

-- Devuelve el total de un pedido: la suma de cantidad por precio unitario de
-- cada renglón. Si el pedido no existe o no tiene renglones, devuelve 0.
-- También la usan dbo.usp_CrearPedido y dbo.usp_IniciarPago (registrar_venta/script.sql).
CREATE FUNCTION dbo.fn_TotalPedido
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

IF OBJECT_ID(N'dbo.fn_PorcentajeDescuentoPedido', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_PorcentajeDescuentoPedido;
GO

-- Devuelve el porcentaje de descuento de un pedido según su total (RN30). El total
-- del pedido sigue siendo la suma de sus renglones; el descuento se aplica al importe
-- del pago (usp_IniciarPago, en registrar_venta/script.sql, y trg_PAGO_Alta).
-- Si el pedido no existe o está cancelado, devuelve 0.
-- Tramos: hasta 100.000, 0 %; hasta 200.000, 5 %; más de 200.000, 10 %.
CREATE FUNCTION dbo.fn_PorcentajeDescuentoPedido
(
    @PedidoId INT
)
RETURNS DECIMAL(5, 2)
AS
BEGIN
    DECLARE @Estado VARCHAR(50);
    DECLARE @TotalPedido DECIMAL(18, 2);
    DECLARE @Descuento DECIMAL(5, 2);

    SELECT @Estado = PE.nombre
    FROM dbo.PEDIDO AS P
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.pedido_estado_id = P.pedido_estado_id
    WHERE P.pedido_id = @PedidoId;

    IF @Estado IS NULL OR @Estado = 'Cancelado'
        RETURN 0;

    SET @TotalPedido = dbo.fn_TotalPedido(@PedidoId);

    SET @Descuento =
        CASE
            WHEN @TotalPedido <= 100000 THEN 0
            WHEN @TotalPedido <= 200000 THEN 5
            ELSE 10
        END;

    RETURN @Descuento;
END;
GO

IF OBJECT_ID(N'dbo.fn_ImporteDescuento', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_ImporteDescuento;
GO

-- Calcula el importe que se descuenta al aplicar un porcentaje sobre un total,
-- redondeado a dos decimales. Devuelve NULL si falta algún dato o si es
-- inválido: un valor negativo o un porcentaje mayor que 100.
CREATE FUNCTION dbo.fn_ImporteDescuento
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

IF OBJECT_ID(N'dbo.fn_DescuentoRenglon', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_DescuentoRenglon;
GO

-- Devuelve la parte del descuento de un pedido que corresponde a uno de sus
-- renglones, en proporción a su subtotal (RN32). La usan los reportes de ventas
-- que reparten un pedido entre vendedores, categorías, libros o publicaciones:
-- lo cobrado por un renglón es su subtotal menos esta parte.
-- Para que las partes de un pedido sumen exactamente su descuento, cada renglón
-- recibe el descuento proporcional acumulado hasta él menos el acumulado hasta el
-- renglón anterior, en el orden de pedido_detalle_id y redondeados a dos decimales.
-- Repartir cada parte por separado podría dejar una diferencia de centavos.
-- Devuelve 0 si el pedido no tiene descuento, y NULL si el renglón no existe.
CREATE FUNCTION dbo.fn_DescuentoRenglon
(
    @PedidoDetalleId INT
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    DECLARE @PedidoId INT;
    DECLARE @Subtotal DECIMAL(18, 2);
    DECLARE @Total DECIMAL(18, 2);
    DECLARE @Descuento DECIMAL(18, 2);
    DECLARE @Acumulado DECIMAL(18, 2);

    SELECT
        @PedidoId = PD.pedido_id,
        @Subtotal = PD.cantidad * PD.precio_unitario
    FROM dbo.PEDIDO_DETALLE AS PD
    WHERE PD.pedido_detalle_id = @PedidoDetalleId;

    IF @PedidoId IS NULL
        RETURN NULL;

    -- El mismo cálculo con que usp_IniciarPago fija el importe del pago.
    SET @Total = dbo.fn_TotalPedido(@PedidoId);
    SET @Descuento = dbo.fn_ImporteDescuento(
        @Total,
        dbo.fn_PorcentajeDescuentoPedido(@PedidoId)
    );

    -- Con descuento, el total supera 100.000: la división no puede ser por cero.
    IF COALESCE(@Descuento, 0) = 0
        RETURN 0;

    -- Subtotales de este renglón y de los anteriores del mismo pedido.
    SELECT @Acumulado = SUM(PD.cantidad * PD.precio_unitario)
    FROM dbo.PEDIDO_DETALLE AS PD
    WHERE PD.pedido_id = @PedidoId
        AND PD.pedido_detalle_id <= @PedidoDetalleId;

    RETURN
        CAST(ROUND(@Acumulado * @Descuento / @Total, 2) AS DECIMAL(18, 2))
        - CAST(ROUND((@Acumulado - @Subtotal) * @Descuento / @Total, 2) AS DECIMAL(18, 2));
END;
GO
