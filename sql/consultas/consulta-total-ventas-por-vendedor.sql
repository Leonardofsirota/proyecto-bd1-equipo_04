/* Total de ventas por vendedor en un rango de fechas: libros vendidos y monto
   recaudado por cada usuario que publicó los libros, de menor a mayor monto. */

SELECT
    U.usuario_id,
    U.nombre + ' ' + U.apellido AS vendedor,
    COUNT(P.pedido_id) AS cantidad_ventas,
    SUM(PD.cantidad) AS total_libros_vendidos,
    SUM(PD.cantidad * PD.precio_unitario) AS total_recaudado
FROM USUARIO U
JOIN PUBLICACION PUB ON U.usuario_id = PUB.usuario_id
JOIN PEDIDO_DETALLE PD ON PUB.publicacion_id = PD.publicacion_id
JOIN PEDIDO P ON PD.pedido_id = P.pedido_id
WHERE P.fecha_pedido BETWEEN '2026-01-01' AND '2026-12-30' -- rango de fechas
GROUP BY U.usuario_id, U.nombre, U.apellido
ORDER BY total_recaudado ASC;
