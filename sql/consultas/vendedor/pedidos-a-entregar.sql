/* Pedidos a entregar de un vendedor: lista los renglones que el vendedor
   todavía debe entregar, es decir, sus libros en pedidos con pago aprobado que
   siguen confirmados, con el cliente, la dirección de envío y el total que le
   corresponde en cada pedido, del pago más antiguo al más reciente.

   Un pedido puede incluir libros de varios vendedores (RN16): solo se muestran
   los renglones del vendedor indicado, y el total suma solo esos renglones. Si
   el vendedor no tiene pedidos para entregar, la consulta no devuelve filas. */

DECLARE @vendedor_id INT = 22;

SELECT
    -- Datos del pedido, iguales en todos sus renglones
    P.pedido_id,
    PA.fecha_pago AS fecha_venta, -- aprobación del pago (RN19 y RN25)
    U.nombre + ' ' + U.apellido AS cliente,

    -- Dirección de envío copiada en el pedido (RN27). Si no tiene piso o
    -- departamento, la suma con NULL da NULL y CONCAT omite esa parte.
    CONCAT(
        P.envio_calle, ' ', P.envio_altura,
        ', piso ' + P.envio_piso,
        ', depto. ' + P.envio_departamento
    ) AS direccion_envio,
    P.envio_codigo_postal AS codigo_postal,
    CI.nombre AS ciudad,
    PR.nombre AS provincia,
    P.envio_referencia AS referencia,

    -- Renglones del vendedor
    PUB.publicacion_id,
    L.titulo,
    CO.nombre AS condicion,
    PD.cantidad,
    PD.precio_unitario,
    PD.cantidad * PD.precio_unitario AS subtotal,

    -- La función de ventana se calcula después del WHERE, así que suma solo
    -- los renglones del vendedor y no el total del pedido.
    SUM(PD.cantidad * PD.precio_unitario)
        OVER (PARTITION BY P.pedido_id) AS total_vendedor
FROM dbo.PEDIDO AS P
INNER JOIN dbo.PEDIDO_ESTADO AS PE
    ON P.pedido_estado_id = PE.pedido_estado_id
-- Se une solo con el pago aprobado (filtro en el WHERE): un pedido tiene a lo
-- sumo uno (RN24), así que los intentos rechazados no duplican los renglones.
INNER JOIN dbo.PAGO AS PA
    ON P.pedido_id = PA.pedido_id
INNER JOIN dbo.PAGO_ESTADO AS PS
    ON PA.pago_estado_id = PS.pago_estado_id
INNER JOIN dbo.USUARIO AS U
    ON P.usuario_id = U.usuario_id
INNER JOIN dbo.CIUDAD AS CI
    ON P.ciudad_id = CI.ciudad_id
INNER JOIN dbo.PROVINCIA AS PR
    ON CI.provincia_id = PR.provincia_id
INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON P.pedido_id = PD.pedido_id
INNER JOIN dbo.PUBLICACION AS PUB
    ON PD.publicacion_id = PUB.publicacion_id
INNER JOIN dbo.LIBRO AS L
    ON PUB.libro_id = L.libro_id
INNER JOIN dbo.CONDICION AS CO
    ON PUB.condicion_id = CO.condicion_id
WHERE PUB.usuario_id = @vendedor_id
    AND PS.nombre = 'Aprobado' -- el pedido ya se cobró
    AND PE.nombre = 'Confirmado' -- y todavía no se entregó (RN19)
ORDER BY PA.fecha_pago, P.pedido_id, PD.pedido_detalle_id;
