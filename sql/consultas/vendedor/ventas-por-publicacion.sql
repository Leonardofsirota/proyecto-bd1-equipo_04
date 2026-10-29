/* Ventas de un vendedor por publicación en un rango de fechas: cantidad de
   ventas, unidades vendidas y monto recaudado por cada una de sus
   publicaciones, en los pedidos cuyo pago se aprobó dentro del rango, de mayor
   a menor monto. Si el vendedor no tiene ventas en el período, la consulta no
   devuelve filas. */

-- Con DATETIME, el formato 'AAAA-MM-DD' depende del idioma de la sesión (en
-- español se lee como 'AAAA-DD-MM'); DATEFORMAT ymd fija su interpretación.
SET DATEFORMAT ymd;

DECLARE @vendedor_id INT = 22;
DECLARE @fecha_desde DATETIME = '2026-01-01';
DECLARE @fecha_hasta DATETIME = '2026-12-31';

SELECT
    PUB.publicacion_id,
    L.titulo,
    CO.nombre AS condicion,
    -- Una publicación aparece una sola vez por pedido (RN16), así que cada
    -- renglón es una venta distinta.
    COUNT(*) AS cantidad_ventas,
    SUM(PD.cantidad) AS unidades_vendidas,
    -- Precio del renglón, no el actual de la publicación (RN26).
    SUM(PD.cantidad * PD.precio_unitario) AS total_recaudado
FROM dbo.PUBLICACION AS PUB
INNER JOIN dbo.LIBRO AS L
    ON PUB.libro_id = L.libro_id
INNER JOIN dbo.CONDICION AS CO
    ON PUB.condicion_id = CO.condicion_id
INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON PUB.publicacion_id = PD.publicacion_id
-- No se filtra por disponible ni por fecha_eliminacion: las ventas de una
-- publicación pausada o dada de baja siguen contando (RN28).
WHERE PUB.usuario_id = @vendedor_id
    -- La venta se cuenta en la fecha en que se aprobó su pago, no en la del
    -- pedido: un pedido puede quedar pendiente varios días antes de pagarse.
    AND EXISTS (
        SELECT 1
        FROM dbo.PAGO AS PA
        INNER JOIN dbo.PAGO_ESTADO AS PS
            ON PA.pago_estado_id = PS.pago_estado_id
        WHERE PA.pedido_id = PD.pedido_id
            AND PS.nombre = 'Aprobado'
            AND PA.fecha_pago >= @fecha_desde
            AND PA.fecha_pago < DATEADD(DAY, 1, @fecha_hasta) -- incluye todo el último día
    )
GROUP BY PUB.publicacion_id, L.titulo, CO.nombre
-- A igual monto, el número de publicación fija un orden estable.
ORDER BY total_recaudado DESC, PUB.publicacion_id;
