/* Pedidos de un cliente: historial de sus pedidos, del más reciente al más
   antiguo, con el estado, la cantidad de libros, el total y el resultado de su
   último intento de pago. Le permite ver qué pedidos le falta pagar, cuáles
   esperan la entrega y cuáles ya recibió.

   Incluye los pedidos cancelados y los que todavía no registran ningún pago
   ('Sin pago'). Si el cliente no hizo pedidos, la consulta no devuelve filas. */

DECLARE @cliente_id INT = 347;

SELECT
    P.pedido_id,
    P.fecha_pedido,
    PE.nombre AS estado_pedido,
    SUM(PD.cantidad) AS cantidad_libros,
    SUM(PD.cantidad * PD.precio_unitario) AS total_pedido, -- calculado del detalle (RN17)
    COALESCE(UP.estado_pago, 'Sin pago') AS estado_pago,
    UP.metodo_pago,
    UP.fecha_pago -- solo si el último intento se aprobó (RN25)
FROM dbo.PEDIDO AS P
INNER JOIN dbo.PEDIDO_ESTADO AS PE
    ON P.pedido_estado_id = PE.pedido_estado_id
INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON P.pedido_id = PD.pedido_id
-- Último intento de pago del pedido. Solo se registra un nuevo intento si el
-- anterior fue rechazado o cancelado (RN24), así que, si el pedido tiene un
-- pago aprobado, es el último. OUTER APPLY funciona como un LEFT JOIN que
-- ejecuta la subconsulta por cada pedido: conserva los pedidos sin pagos.
OUTER APPLY (
    SELECT TOP 1
        PS.nombre AS estado_pago,
        PM.nombre AS metodo_pago,
        PA.fecha_pago
    FROM dbo.PAGO AS PA
    INNER JOIN dbo.PAGO_ESTADO AS PS
        ON PA.pago_estado_id = PS.pago_estado_id
    INNER JOIN dbo.PAGO_METODO AS PM
        ON PA.pago_metodo_id = PM.pago_metodo_id
    WHERE PA.pedido_id = P.pedido_id
    ORDER BY PA.fecha_creacion DESC, PA.pago_id DESC
) AS UP
WHERE P.usuario_id = @cliente_id
GROUP BY
    P.pedido_id,
    P.fecha_pedido,
    PE.nombre,
    UP.estado_pago,
    UP.metodo_pago,
    UP.fecha_pago
ORDER BY P.fecha_pedido DESC, P.pedido_id DESC;
