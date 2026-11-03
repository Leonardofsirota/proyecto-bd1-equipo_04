/* Libros más vendidos: unidades vendidas y monto recaudado por libro en los
   pedidos con pago aprobado, solo para los libros con al menos 3 unidades vendidas.

   El monto recaudado es lo cobrado, con el descuento del pedido (RN32): a cada
   renglón se le resta su parte, calculada por dbo.fn_DescuentoRenglon
   (calcular_descuento_pedido/script.sql, Etapa 5). */

SELECT
    L.libro_id,
    L.titulo,
    SUM(PD.cantidad) AS unidades_vendidas,
    -- Subtotal del renglón menos su parte del descuento del pedido.
    SUM(
        PD.cantidad * PD.precio_unitario
        - dbo.fn_DescuentoRenglon(PD.pedido_detalle_id)
    ) AS total_recaudado
FROM dbo.LIBRO AS L
INNER JOIN dbo.PUBLICACION AS PUB
    ON L.libro_id = PUB.libro_id
INNER JOIN dbo.PEDIDO_DETALLE AS PD
    ON PUB.publicacion_id = PD.publicacion_id
-- EXISTS en lugar de JOIN con PAGO: un pedido puede tener varios intentos de pago
-- y así cada renglón se cuenta una sola vez.
WHERE EXISTS (
    SELECT 1
    FROM dbo.PAGO AS PA
    INNER JOIN dbo.PAGO_ESTADO AS PS
        ON PA.pago_estado_id = PS.pago_estado_id
    WHERE PA.pedido_id = PD.pedido_id
        AND PS.nombre = 'Aprobado'
)
GROUP BY L.libro_id, L.titulo
HAVING SUM(PD.cantidad) >= 3 -- mínimo de unidades para considerarlo más vendido
ORDER BY unidades_vendidas DESC, total_recaudado DESC;
