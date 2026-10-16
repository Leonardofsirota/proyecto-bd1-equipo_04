/* Comprobante de venta: encabezado (número, fecha y cliente) y detalle de cada
   venta, con el subtotal por renglón y el total acumulado de la venta. */

SELECT
    -- Encabezado de la venta
    P.pedido_id AS [Nro. Venta],
    P.fecha_pedido AS [Fecha de Venta],
    U.usuario_id AS [ID Cliente],
    U.nombre AS [Nombre Cliente],
    U.apellido AS [Apellido Cliente],

    -- Detalle de la venta
    PD.pedido_detalle_id AS [Nro. Renglon],
    L.libro_id AS [ID Libro],
    L.titulo AS [Titulo del Libro],
    PD.cantidad AS [Cantidad],
    PD.precio_unitario AS [Precio Unitario],

    -- Subtotal de cada renglon
    CAST(
        PD.cantidad * PD.precio_unitario
        AS DECIMAL(18, 2)
    ) AS [Subtotal],

    -- Total acumulado de cada venta
    CAST(
        SUM(PD.cantidad * PD.precio_unitario)
        OVER (PARTITION BY P.pedido_id)
        AS DECIMAL(18, 2)
    ) AS [Total Venta]

FROM dbo.PEDIDO AS P

INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON P.pedido_id = PD.pedido_id

INNER JOIN dbo.USUARIO AS U
    ON P.usuario_id = U.usuario_id

INNER JOIN dbo.PUBLICACION AS PUB
    ON PD.publicacion_id = PUB.publicacion_id

INNER JOIN dbo.LIBRO AS L
    ON PUB.libro_id = L.libro_id

ORDER BY
    P.pedido_id,
    PD.pedido_detalle_id;
