SELECT
    U.usuario_id,
    U.nombre,
    U.apellido,
    dbo.fn_PorcentajeDescuentoCliente(
        U.usuario_id
    ) AS PorcentajeDescuento
FROM dbo.USUARIO AS U;
GO