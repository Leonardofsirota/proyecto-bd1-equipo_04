/* Pagos por método en un rango de fechas: intentos de pago iniciados con cada
   método, cuántos se aprobaron, rechazaron, cancelaron o siguen pendientes, el
   porcentaje de aprobados y el importe aprobado, para detectar un método que
   concentre los rechazos (RN21, RN23 y RN29).

   El rango se aplica a la fecha de inicio del intento, porque los rechazados y
   cancelados sin cobro no tienen fecha de acreditación (RN25). Por eso el
   importe aprobado puede diferir del total de los reportes de ventas, que usan
   la fecha de aprobación: un pago iniciado al final del rango puede aprobarse
   en el período siguiente. */

-- Con DATETIME, el formato 'AAAA-MM-DD' depende del idioma de la sesión (en
-- español se lee como 'AAAA-DD-MM'); DATEFORMAT ymd fija su interpretación.
SET DATEFORMAT ymd;

DECLARE @fecha_desde DATETIME = '2026-01-01';
DECLARE @fecha_hasta DATETIME = '2026-12-31';

SELECT
    PM.nombre AS metodo_pago,
    COUNT(PA.pago_id) AS intentos,
    SUM(CASE WHEN PS.nombre = 'Aprobado' THEN 1 ELSE 0 END) AS aprobados,
    SUM(CASE WHEN PS.nombre = 'Rechazado' THEN 1 ELSE 0 END) AS rechazados,
    SUM(CASE WHEN PS.nombre = 'Cancelado' THEN 1 ELSE 0 END) AS cancelados,
    SUM(CASE WHEN PS.nombre = 'Pendiente' THEN 1 ELSE 0 END) AS pendientes,
    -- NULLIF evita dividir por cero si el método no tuvo intentos en el rango.
    CAST(
        100.0 * SUM(CASE WHEN PS.nombre = 'Aprobado' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(PA.pago_id), 0)
        AS DECIMAL(5, 2)
    ) AS porcentaje_aprobados,
    SUM(CASE WHEN PS.nombre = 'Aprobado' THEN PA.importe ELSE 0 END) AS importe_aprobado
FROM dbo.PAGO_METODO AS PM
-- LEFT JOIN con el filtro de fechas en el ON: así los métodos sin intentos en
-- el rango aparecen con cero en lugar de desaparecer.
LEFT JOIN dbo.PAGO AS PA
    ON PM.pago_metodo_id = PA.pago_metodo_id
    AND PA.fecha_creacion >= @fecha_desde
    AND PA.fecha_creacion < DATEADD(DAY, 1, @fecha_hasta) -- incluye todo el último día
LEFT JOIN dbo.PAGO_ESTADO AS PS
    ON PA.pago_estado_id = PS.pago_estado_id
GROUP BY PM.nombre
ORDER BY intentos DESC, PM.nombre;
