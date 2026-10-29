-- Devuelve el porcentaje de descuento de un cliente según su total histórico
-- de compras: la suma de todos sus pedidos con un pago aprobado.
-- Tramos: hasta 100.000, 0 %; hasta 200.000, 5 %; más de 200.000, 10 %.
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
    WHERE P.usuario_id = @UsuarioId
        AND EXISTS (
            SELECT 1
            FROM dbo.PAGO AS PA
            INNER JOIN dbo.PAGO_ESTADO AS PS
                ON PS.pago_estado_id = PA.pago_estado_id
            WHERE PA.pedido_id = P.pedido_id
                AND PS.nombre = 'Aprobado'
        );

    SET @Descuento =
        CASE
            WHEN @TotalHistorico <= 100000 THEN 0
            WHEN @TotalHistorico <= 200000 THEN 5
            ELSE 10
        END;

    RETURN @Descuento;
END;
GO

--SELECT
--    U.usuario_id,
--    U.nombre,
--    U.apellido,
--    dbo.fn_PorcentajeDescuentoCliente(
--        U.usuario_id
--    ) AS PorcentajeDescuento
--FROM dbo.USUARIO AS U;
--GO

-- Devuelve el total de un pedido: la suma de cantidad por precio unitario de
-- cada renglón. Si el pedido no existe o no tiene renglones, devuelve 0.
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

--SELECT
--    P.pedido_id,
--    P.fecha_pedido,
--    dbo.fn_TotalPedido(P.pedido_id) AS TotalPedido
--FROM dbo.PEDIDO AS P
--ORDER BY P.pedido_id;
--GO

-- Calcula el importe que se descuenta al aplicar un porcentaje sobre un total,
-- redondeado a dos decimales. Devuelve NULL si falta algún dato o si es
-- inválido: un valor negativo o un porcentaje mayor que 100.
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

-- Cliente en el tramo del 0 %: total del pedido 37.100, descuento 0.
SELECT
    P.pedido_id,
    P.usuario_id,

    dbo.fn_PorcentajeDescuentoCliente(P.usuario_id)
        AS PorcentajeDescuento,

    dbo.fn_TotalPedido(P.pedido_id)
        AS TotalPedido,

    dbo.fn_ImporteDescuento(
        dbo.fn_TotalPedido(P.pedido_id),
        dbo.fn_PorcentajeDescuentoCliente(P.usuario_id)
    ) AS ImporteDescuento
FROM dbo.PEDIDO AS P
WHERE P.pedido_id = 2;
GO

-- Cliente en el tramo del 5 %: total del pedido 35.000, descuento 1.750.
SELECT
    P.pedido_id,
    P.usuario_id,

    dbo.fn_PorcentajeDescuentoCliente(P.usuario_id)
        AS PorcentajeDescuento,

    dbo.fn_TotalPedido(P.pedido_id)
        AS TotalPedido,

    dbo.fn_ImporteDescuento(
        dbo.fn_TotalPedido(P.pedido_id),
        dbo.fn_PorcentajeDescuentoCliente(P.usuario_id)
    ) AS ImporteDescuento
FROM dbo.PEDIDO AS P
WHERE P.pedido_id = 1;
GO

-- Cliente en el tramo del 10 %: total del pedido 38.400, descuento 3.840.
SELECT
    P.pedido_id,
    P.usuario_id,

    dbo.fn_PorcentajeDescuentoCliente(P.usuario_id)
        AS PorcentajeDescuento,

    dbo.fn_TotalPedido(P.pedido_id)
        AS TotalPedido,

    dbo.fn_ImporteDescuento(
        dbo.fn_TotalPedido(P.pedido_id),
        dbo.fn_PorcentajeDescuentoCliente(P.usuario_id)
    ) AS ImporteDescuento
FROM dbo.PEDIDO AS P
WHERE P.pedido_id = 3;
GO
