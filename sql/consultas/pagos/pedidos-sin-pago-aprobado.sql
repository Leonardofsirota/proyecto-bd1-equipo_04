/* Pedidos sin pago aprobado: lista los pedidos que no tienen ningún pago
   aprobado, con el cliente, el estado del pedido, el total y el estado de su
   último intento de pago ('Sin pago' si todavía no registra ninguno). */

SELECT
    P.pedido_id,
    P.fecha_pedido,
    U.nombre + ' ' + U.apellido AS cliente,
    PE.nombre AS estado_pedido,
    SUM(PD.cantidad * PD.precio_unitario) AS total_pedido,
    -- Un pedido puede tener varios intentos rechazados o cancelados (RN24);
    -- se muestra solo el último para no repetir el pedido ni su total.
    COALESCE((
        SELECT TOP 1 PS.nombre
        FROM dbo.PAGO AS PA
        INNER JOIN dbo.PAGO_ESTADO AS PS
            ON PA.pago_estado_id = PS.pago_estado_id
        WHERE PA.pedido_id = P.pedido_id
        ORDER BY PA.fecha_creacion DESC, PA.pago_id DESC
    ), 'Sin pago') AS estado_pago
FROM dbo.PEDIDO AS P
INNER JOIN dbo.USUARIO AS U
    ON P.usuario_id = U.usuario_id
INNER JOIN dbo.PEDIDO_ESTADO AS PE
    ON P.pedido_estado_id = PE.pedido_estado_id
INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON P.pedido_id = PD.pedido_id
-- Se filtra por pedido y no por pago: los intentos fallidos de un pedido que
-- después se aprobó no deben aparecer.
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.PAGO AS PA
    INNER JOIN dbo.PAGO_ESTADO AS PS
        ON PA.pago_estado_id = PS.pago_estado_id
    WHERE PA.pedido_id = P.pedido_id
        AND PS.nombre = 'Aprobado'
)
GROUP BY P.pedido_id, P.fecha_pedido, U.nombre, U.apellido, PE.nombre
ORDER BY P.fecha_pedido;
