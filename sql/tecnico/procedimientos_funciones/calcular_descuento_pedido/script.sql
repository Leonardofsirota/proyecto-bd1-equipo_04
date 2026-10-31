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

--SELECT
--    P.pedido_id,
--    P.fecha_pedido,
--    dbo.fn_TotalPedido(P.pedido_id) AS TotalPedido
--FROM dbo.PEDIDO AS P
--ORDER BY P.pedido_id;
--GO

IF OBJECT_ID(N'dbo.fn_PorcentajeDescuentoPedido', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_PorcentajeDescuentoPedido;
GO

-- Devuelve el porcentaje de descuento de un pedido según su total (RN30). Es
-- informativo: no modifica el total del pedido ni el importe de sus pagos.
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

--SELECT
--    P.pedido_id,
--    dbo.fn_PorcentajeDescuentoPedido(
--        P.pedido_id
--    ) AS PorcentajeDescuento
--FROM dbo.PEDIDO AS P
--ORDER BY P.pedido_id;
--GO

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

-- Pedido en el tramo del 0 %: total del pedido 35.000, descuento 0.
SELECT
    P.pedido_id,

    dbo.fn_PorcentajeDescuentoPedido(P.pedido_id)
        AS PorcentajeDescuento,

    dbo.fn_TotalPedido(P.pedido_id)
        AS TotalPedido,

    dbo.fn_ImporteDescuento(
        dbo.fn_TotalPedido(P.pedido_id),
        dbo.fn_PorcentajeDescuentoPedido(P.pedido_id)
    ) AS ImporteDescuento
FROM dbo.PEDIDO AS P
WHERE P.pedido_id = 1;
GO

-- Pedido en el tramo del 5 %: total del pedido 100.700, descuento 5.035.
SELECT
    P.pedido_id,

    dbo.fn_PorcentajeDescuentoPedido(P.pedido_id)
        AS PorcentajeDescuento,

    dbo.fn_TotalPedido(P.pedido_id)
        AS TotalPedido,

    dbo.fn_ImporteDescuento(
        dbo.fn_TotalPedido(P.pedido_id),
        dbo.fn_PorcentajeDescuentoPedido(P.pedido_id)
    ) AS ImporteDescuento
FROM dbo.PEDIDO AS P
WHERE P.pedido_id = 15;
GO

-- Pedido en el tramo del 10 %: total del pedido 203.600, descuento 20.360.
SELECT
    P.pedido_id,

    dbo.fn_PorcentajeDescuentoPedido(P.pedido_id)
        AS PorcentajeDescuento,

    dbo.fn_TotalPedido(P.pedido_id)
        AS TotalPedido,

    dbo.fn_ImporteDescuento(
        dbo.fn_TotalPedido(P.pedido_id),
        dbo.fn_PorcentajeDescuentoPedido(P.pedido_id)
    ) AS ImporteDescuento
FROM dbo.PEDIDO AS P
WHERE P.pedido_id = 18;
GO

-- Pedido cancelado de más de 100.000: porcentaje y descuento 0.
SELECT
    P.pedido_id,
    PE.nombre AS Estado,

    dbo.fn_PorcentajeDescuentoPedido(P.pedido_id)
        AS PorcentajeDescuento,

    dbo.fn_TotalPedido(P.pedido_id)
        AS TotalPedido,

    dbo.fn_ImporteDescuento(
        dbo.fn_TotalPedido(P.pedido_id),
        dbo.fn_PorcentajeDescuentoPedido(P.pedido_id)
    ) AS ImporteDescuento
FROM dbo.PEDIDO AS P
INNER JOIN dbo.PEDIDO_ESTADO AS PE
    ON PE.pedido_estado_id = P.pedido_estado_id
WHERE P.pedido_id = 62;
GO

-- Pedido inexistente: porcentaje 0.
SELECT dbo.fn_PorcentajeDescuentoPedido(0) AS PorcentajeDescuento;
GO
