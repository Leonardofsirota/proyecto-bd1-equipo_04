USE [sistema-venta-libros];
GO

-- Demostración de las funciones de script.sql con pedidos de los datos de prueba.

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

-- Reparto del descuento del pedido 15 (tramo del 5 %) entre sus tres renglones:
-- 980, 920 y 3.135 suman el descuento del pedido, 5.035, y lo cobrado suma
-- 95.665, el importe de su pago aprobado.
SELECT
    PD.pedido_detalle_id,

    PD.cantidad * PD.precio_unitario
        AS Subtotal,

    dbo.fn_DescuentoRenglon(PD.pedido_detalle_id)
        AS DescuentoRenglon,

    PD.cantidad * PD.precio_unitario
        - dbo.fn_DescuentoRenglon(PD.pedido_detalle_id)
        AS Cobrado
FROM dbo.PEDIDO_DETALLE AS PD
WHERE PD.pedido_id = 15
ORDER BY PD.pedido_detalle_id;
GO

-- Renglón inexistente: NULL.
SELECT dbo.fn_DescuentoRenglon(0) AS DescuentoRenglon;
GO

-- Listados de todos los pedidos, desactivados.
--SELECT
--    P.pedido_id,
--    P.fecha_pedido,
--    dbo.fn_TotalPedido(P.pedido_id) AS TotalPedido
--FROM dbo.PEDIDO AS P
--ORDER BY P.pedido_id;
--GO

--SELECT
--    P.pedido_id,
--    dbo.fn_PorcentajeDescuentoPedido(
--        P.pedido_id
--    ) AS PorcentajeDescuento
--FROM dbo.PEDIDO AS P
--ORDER BY P.pedido_id;
--GO
