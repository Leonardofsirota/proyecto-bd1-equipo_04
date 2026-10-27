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