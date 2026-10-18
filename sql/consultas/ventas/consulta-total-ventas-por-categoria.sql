/* Total de ventas por categoría de libro en un rango de fechas: pedidos,
   unidades vendidas y monto recaudado por categoría en los pedidos con pago
   aprobado, de mayor a menor monto. */

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
WHERE P.fecha_pedido >= @fecha_desde
    AND P.fecha_pedido < DATEADD(DAY, 1, @fecha_hasta) -- incluye todo el último día
    AND EXISTS (
        SELECT 1
        FROM PAGO PA
        JOIN PAGO_ESTADO PS ON PA.pago_estado_id = PS.pago_estado_id
        WHERE PA.pedido_id = P.pedido_id
            AND PS.nombre = 'Aprobado'
    )
GROUP BY C.nombre
ORDER BY total_por_categoria DESC;
