USE [sistema-venta-libros];
GO

WITH DetalleVentas AS
(
    SELECT
        P.pedido_id,
        P.fecha_pedido,
        U.usuario_id,
        U.nombre,
        U.apellido,
        PD.pedido_detalle_id,
        L.libro_id,
        L.titulo,
        PD.cantidad,
        PD.precio_unitario,

        CAST(
            PD.cantidad * PD.precio_unitario
            AS DECIMAL(18, 2)
        ) AS subtotal

    FROM dbo.PEDIDO AS P

    INNER JOIN dbo.PEDIDO_DETALLE AS PD
        ON P.pedido_id = PD.pedido_id

    INNER JOIN dbo.USUARIO AS U
        ON P.usuario_id = U.usuario_id

    INNER JOIN dbo.PUBLICACION AS PUB
        ON PD.publicacion_id = PUB.publicacion_id

    INNER JOIN dbo.LIBRO AS L
        ON PUB.libro_id = L.libro_id
),
Resultado AS
(
    -- Renglones de detalle de todas las ventas
    SELECT
        1 AS orden,
        pedido_id,
        fecha_pedido,
        usuario_id,
        nombre,
        apellido,
        pedido_detalle_id,
        libro_id,
        titulo,
        cantidad,
        precio_unitario,
        subtotal,

        CAST(
            SUM(subtotal) OVER (
                PARTITION BY pedido_id
            )
            AS DECIMAL(18, 2)
        ) AS total_venta,

        CAST(NULL AS DECIMAL(18, 2)) AS total_general

    FROM DetalleVentas

    UNION ALL

    -- Renglón final con el total de todas las ventas
    SELECT
        2 AS orden,
        NULL,
        NULL,
        NULL,
        'TOTAL',
        'GENERAL',
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,

        CAST(
            COALESCE(SUM(subtotal), 0)
            AS DECIMAL(18, 2)
        ) AS total_general

    FROM DetalleVentas
)
SELECT
    CASE
        WHEN orden = 2 THEN 'TOTAL GENERAL'
        ELSE CAST(pedido_id AS VARCHAR(20))
    END AS [Nro. Venta],

    fecha_pedido AS [Fecha de Venta],
    usuario_id AS [ID Cliente],
    nombre AS [Nombre Cliente],
    apellido AS [Apellido Cliente],
    pedido_detalle_id AS [Nro. Renglon],
    libro_id AS [ID Libro],
    titulo AS [Titulo del Libro],
    cantidad AS [Cantidad],
    precio_unitario AS [Precio Unitario],
    subtotal AS [Subtotal],
    total_venta AS [Total Venta],
    total_general AS [Total General]

FROM Resultado

ORDER BY
    orden,
    pedido_id,
    pedido_detalle_id;
GO