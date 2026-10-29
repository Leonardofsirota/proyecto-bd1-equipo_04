/* Ventas por mes en un rango de fechas: cantidad de ventas, unidades vendidas,
   monto recaudado y monto promedio por venta en cada mes, según la fecha en
   que se aprobó el pago, del mes más antiguo al más reciente. Los meses sin
   ventas no aparecen. */

-- Con DATETIME, el formato 'AAAA-MM-DD' depende del idioma de la sesión (en
-- español se lee como 'AAAA-DD-MM'); DATEFORMAT ymd fija su interpretación.
SET DATEFORMAT ymd;

DECLARE @fecha_desde DATETIME = '2026-01-01';
DECLARE @fecha_hasta DATETIME = '2026-12-31';

SELECT
    YEAR(PA.fecha_pago) AS anio,
    MONTH(PA.fecha_pago) AS mes,
    COUNT(DISTINCT PD.pedido_id) AS cantidad_ventas,
    SUM(PD.cantidad) AS unidades_vendidas,
    SUM(PD.cantidad * PD.precio_unitario) AS total_recaudado,
    CAST(
        SUM(PD.cantidad * PD.precio_unitario) / COUNT(DISTINCT PD.pedido_id)
        AS DECIMAL(18, 2)
    ) AS promedio_por_venta
FROM dbo.PEDIDO_DETALLE AS PD
-- Se agrupa por la fecha del pago, así que se une con él en lugar de usar
-- EXISTS. Se une solo con el pago aprobado (filtro en el WHERE): un pedido
-- tiene a lo sumo uno (RN24), así que los intentos rechazados no duplican los
-- renglones.
INNER JOIN dbo.PAGO AS PA
    ON PD.pedido_id = PA.pedido_id
INNER JOIN dbo.PAGO_ESTADO AS PS
    ON PA.pago_estado_id = PS.pago_estado_id
WHERE PS.nombre = 'Aprobado'
    AND PA.fecha_pago >= @fecha_desde
    AND PA.fecha_pago < DATEADD(DAY, 1, @fecha_hasta) -- incluye todo el último día
GROUP BY YEAR(PA.fecha_pago), MONTH(PA.fecha_pago)
ORDER BY anio, mes;
