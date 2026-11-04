/* Publicaciones de un vendedor y su stock: lista todas sus publicaciones con el
   libro, la condición, el precio, el stock y el estado, de menor a mayor stock,
   para saber qué reponer y qué publicaciones no ven los clientes.

   Solo las publicaciones activas pueden agregarse a un pedido (RN12). Las dadas
   de baja se conservan (RN28) y aparecen al final. Si el vendedor no tiene
   publicaciones, la consulta no devuelve filas. */

DECLARE @vendedor_id INT = 25;

SELECT
    PUB.publicacion_id,
    L.titulo,
    CO.nombre AS condicion,
    PUB.precio,
    PUB.stock,
    -- Una publicación sin stock se informa como agotada aunque además esté
    -- pausada: para volver a venderla, primero hay que reponer stock.
    CASE
        WHEN PUB.fecha_eliminacion IS NOT NULL THEN 'Dada de baja'
        WHEN PUB.stock = 0 THEN 'Agotada'
        WHEN PUB.disponible = 0 THEN 'Pausada'
        ELSE 'Activa'
    END AS estado
FROM dbo.PUBLICACION AS PUB
INNER JOIN dbo.LIBRO AS L
    ON PUB.libro_id = L.libro_id
INNER JOIN dbo.CONDICION AS CO
    ON PUB.condicion_id = CO.condicion_id
WHERE PUB.usuario_id = @vendedor_id
-- Las dadas de baja van al final; el resto, de menor a mayor stock, así las
-- agotadas y las que están por agotarse quedan primero.
ORDER BY
    CASE WHEN PUB.fecha_eliminacion IS NULL THEN 0 ELSE 1 END,
    PUB.stock,
    PUB.publicacion_id;
