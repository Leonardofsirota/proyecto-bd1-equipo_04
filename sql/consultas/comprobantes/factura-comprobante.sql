/* Comprobante de venta: encabezado (número, fecha, método de pago y cliente)
   y detalle de una venta, con el subtotal por renglón y el total de la venta.

   Una venta es un pedido con un pago aprobado. No hace falta filtrar por el
   estado del pedido, porque al aprobarse el pago pasa a confirmado (RN19). Si
   el pedido indicado no tiene un pago aprobado, la consulta no devuelve filas. */

DECLARE @pedido_id INT = 151;

SELECT
    -- Encabezado de la venta
    P.pedido_id AS [Nro. Venta],
    PA.fecha_pago AS [Fecha de Venta], -- aprobación del pago (RN19 y RN25)
    PM.nombre AS [Metodo de Pago],
    U.usuario_id AS [ID Cliente],
    U.nombre AS [Nombre Cliente],
    U.apellido AS [Apellido Cliente],

    -- Detalle de la venta, con los renglones numerados desde 1
    ROW_NUMBER() OVER (
        PARTITION BY P.pedido_id
        ORDER BY PD.pedido_detalle_id
    ) AS [Nro. Renglon],
    L.libro_id AS [ID Libro],
    L.titulo AS [Titulo del Libro],
    PD.cantidad AS [Cantidad],
    PD.precio_unitario AS [Precio Unitario],

    -- Subtotal de cada renglon
    CAST(
        PD.cantidad * PD.precio_unitario
        AS DECIMAL(18, 2)
    ) AS [Subtotal],

    -- Total de la venta: suma de los subtotales de sus renglones (RN17)
    CAST(
        SUM(PD.cantidad * PD.precio_unitario)
        OVER (PARTITION BY P.pedido_id)
        AS DECIMAL(18, 2)
    ) AS [Total Venta]

FROM dbo.PEDIDO AS P

-- Se une solo con el pago aprobado (filtro en el WHERE): un pedido tiene a lo
-- sumo uno (RN24), así que los intentos rechazados no duplican los renglones.
INNER JOIN dbo.PAGO AS PA
    ON P.pedido_id = PA.pedido_id

INNER JOIN dbo.PAGO_ESTADO AS PS
    ON PA.pago_estado_id = PS.pago_estado_id

INNER JOIN dbo.PAGO_METODO AS PM
    ON PA.pago_metodo_id = PM.pago_metodo_id

INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON P.pedido_id = PD.pedido_id

INNER JOIN dbo.USUARIO AS U
    ON P.usuario_id = U.usuario_id

INNER JOIN dbo.PUBLICACION AS PUB
    ON PD.publicacion_id = PUB.publicacion_id

INNER JOIN dbo.LIBRO AS L
    ON PUB.libro_id = L.libro_id

WHERE P.pedido_id = @pedido_id
    AND PS.nombre = 'Aprobado'

ORDER BY PD.pedido_detalle_id;
