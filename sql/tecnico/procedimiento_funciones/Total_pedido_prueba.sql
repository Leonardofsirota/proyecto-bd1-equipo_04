SELECT
    P.pedido_id,
    P.fecha_pedido,
    dbo.fn_TotalPedido(P.pedido_id) AS TotalPedido
FROM dbo.PEDIDO AS P
ORDER BY P.pedido_id;
GO