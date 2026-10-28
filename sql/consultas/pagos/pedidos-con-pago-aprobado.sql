/* Pedidos con pago aprobado: lista cada pedido cuyo pago fue aprobado,
   con el cliente, el estado del pedido, el importe pagado y el método de pago
   utilizado. Como un pedido tiene a lo sumo un pago aprobado (RN24), cada
   pedido aparece una sola vez. */

SELECT
    U.usuario_id,
    U.nombre,
    U.apellido,
    P.pedido_id,
    PE.nombre AS estado_pedido,
    PA.importe,
    PS.nombre AS estado_pago,
    PM.nombre AS metodo_pago
FROM dbo.USUARIO AS U
INNER JOIN dbo.PEDIDO AS P
    ON U.usuario_id = P.usuario_id
INNER JOIN dbo.PEDIDO_ESTADO AS PE
    ON P.pedido_estado_id = PE.pedido_estado_id
INNER JOIN dbo.PAGO AS PA
    ON P.pedido_id = PA.pedido_id
INNER JOIN dbo.PAGO_ESTADO AS PS
    ON PA.pago_estado_id = PS.pago_estado_id
INNER JOIN dbo.PAGO_METODO AS PM
    ON PA.pago_metodo_id = PM.pago_metodo_id
WHERE PS.nombre = 'Aprobado'
ORDER BY P.pedido_id;
