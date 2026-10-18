/* Libros más vendidos: unidades vendidas y monto recaudado por libro en los
   pedidos no cancelados, solo para los libros con al menos 3 unidades vendidas. */

SELECT
    L.libro_id,
    L.titulo,
    SUM(PD.cantidad) AS unidades_vendidas,
    SUM(PD.cantidad * PD.precio_unitario) AS total_recaudado
FROM dbo.LIBRO AS L
INNER JOIN dbo.PUBLICACION AS PUB
    ON L.libro_id = PUB.libro_id
INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON PUB.publicacion_id = PD.publicacion_id
INNER JOIN dbo.PEDIDO AS P
    ON PD.pedido_id = P.pedido_id
INNER JOIN dbo.PEDIDO_ESTADO AS PE
    ON P.pedido_estado_id = PE.pedido_estado_id
WHERE PE.nombre <> 'Cancelado'
GROUP BY L.libro_id, L.titulo
HAVING SUM(PD.cantidad) >= 3 -- mínimo de unidades para considerarlo más vendido
ORDER BY unidades_vendidas DESC, total_recaudado DESC;
