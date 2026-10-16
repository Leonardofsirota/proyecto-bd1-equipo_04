USE [sistema-venta-libros]
GO

-- PUNTO 2B: Total de ventas por CATEGORIA en un rango de fechas

SELECT 
    C.nombre AS categoria,
    COUNT(PD.pedido_detalle_id) AS cantidad_pedidos,
    SUM(PD.cantidad) AS unidades_vendidas,
    SUM(PD.cantidad * PD.precio_unitario) AS total_por_categoria
FROM CATEGORIA C
JOIN LIBRO L ON C.categoria_id = L.categoria_id
JOIN PUBLICACION PUB ON L.libro_id = PUB.libro_id
JOIN PEDIDO_DETALLE PD ON PUB.publicacion_id = PD.publicacion_id
JOIN PEDIDO P ON PD.pedido_id = P.pedido_id
WHERE P.fecha_pedido BETWEEN '2025-01-01' AND '2026-12-31'
GROUP BY C.nombre
HAVING SUM(PD.cantidad * PD.precio_unitario) > 0 -- solo categorías que vendieron algo
ORDER BY total_por_categoria DESC;