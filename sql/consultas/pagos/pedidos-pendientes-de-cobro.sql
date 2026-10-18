/* Pedidos pendientes de cobro: lista los pedidos no cancelados que todavía
   no tienen un pago aprobado, con el cliente, el estado y el total a cobrar. */

SELECT
    P.pedido_id,
    P.fecha_pedido,
    U.nombre + ' ' + U.apellido AS cliente,
    PE.nombre AS estado_pedido,
    SUM(PD.cantidad * PD.precio_unitario) AS total_pedido
FROM dbo.PEDIDO AS P
INNER JOIN dbo.USUARIO AS U
    ON P.usuario_id = U.usuario_id
INNER JOIN dbo.PEDIDO_ESTADO AS PE
    ON P.pedido_estado_id = PE.pedido_estado_id
INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON P.pedido_id = PD.pedido_id
WHERE PE.nombre <> 'Cancelado'
    AND NOT EXISTS (
        SELECT 1
        FROM dbo.PAGO AS PA
        INNER JOIN dbo.PAGO_ESTADO AS PS
            ON PA.pago_estado_id = PS.pago_estado_id
        WHERE PA.pedido_id = P.pedido_id
            AND PS.nombre = 'Aprobado'
    )
GROUP BY P.pedido_id, P.fecha_pedido, U.nombre, U.apellido, PE.nombre
ORDER BY P.fecha_pedido;
