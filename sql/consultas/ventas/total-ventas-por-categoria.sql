/* Total de ventas por categoría de libro en un rango de fechas: pedidos,
   unidades vendidas y monto recaudado por categoría en los pedidos cuyo pago
   se aprobó dentro del rango, de mayor a menor monto. */

-- Con DATETIME, el formato 'AAAA-MM-DD' depende del idioma de la sesión (en
-- español se lee como 'AAAA-DD-MM'); DATEFORMAT ymd fija su interpretación.
SET DATEFORMAT ymd;

DECLARE @fecha_desde DATETIME = '2026-01-01';
DECLARE @fecha_hasta DATETIME = '2026-12-31';

SELECT
    C.nombre AS categoria,
    COUNT(DISTINCT P.pedido_id) AS cantidad_pedidos,
    SUM(PD.cantidad) AS unidades_vendidas,
    SUM(PD.cantidad * PD.precio_unitario) AS total_por_categoria
FROM CATEGORIA C
JOIN LIBRO L ON C.categoria_id = L.categoria_id
JOIN PUBLICACION PUB ON L.libro_id = PUB.libro_id
JOIN PEDIDO_DETALLE PD ON PUB.publicacion_id = PD.publicacion_id
JOIN PEDIDO P ON PD.pedido_id = P.pedido_id
-- La venta se cuenta en la fecha en que se aprobó su pago, no en la del pedido:
-- un pedido puede quedar pendiente varios días antes de pagarse.
WHERE EXISTS (
    SELECT 1
    FROM PAGO PA
    JOIN PAGO_ESTADO PS ON PA.pago_estado_id = PS.pago_estado_id
    WHERE PA.pedido_id = P.pedido_id
        AND PS.nombre = 'Aprobado'
        AND PA.fecha_pago >= @fecha_desde
        AND PA.fecha_pago < DATEADD(DAY, 1, @fecha_hasta) -- incluye todo el último día
)
GROUP BY C.nombre
ORDER BY total_por_categoria DESC;
