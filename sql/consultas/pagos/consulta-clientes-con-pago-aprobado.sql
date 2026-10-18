/* Clientes con pagos aprobados: lista cada pedido cuyo pago fue aprobado,
   con el cliente, el importe pagado y el método de pago utilizado. */

SELECT DISTINCT
    U.usuario_id,
    U.nombre,
    U.apellido,
    P.pedido_id,
    PA.importe,
    PE.nombre AS estado_pago,
    PM.nombre AS metodo_pago
FROM Usuario AS U
INNER JOIN Pedido AS P
    ON U.usuario_id = P.usuario_id
INNER JOIN Pedido_detalle AS PD
    ON P.pedido_id = PD.pedido_id
INNER JOIN Publicacion AS PUB
    ON PD.publicacion_id = PUB.publicacion_id
INNER JOIN Pago AS PA
    ON P.pedido_id = PA.pedido_id
INNER JOIN Pago_estado AS PE
    ON PA.pago_estado_id = PE.pago_estado_id
INNER JOIN Pago_metodo AS PM
    ON PA.pago_metodo_id = PM.pago_metodo_id
WHERE PE.nombre = 'Aprobado';
