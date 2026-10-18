/* Ofertas vigentes de un libro: compara las publicaciones de un mismo libro
   entre vendedores, con la condición del ejemplar, el precio y el stock
   disponible, de menor a mayor precio.

   Solo se listan las ofertas que un cliente puede agregar a un pedido (RN12):
   publicaciones activas y con stock, de vendedores que no fueron dados de baja
   (RN28). Si el libro indicado no tiene ofertas vigentes, la consulta no
   devuelve filas. */

DECLARE @libro_id INT = 277;

SELECT
    -- Datos del libro, iguales en todas las ofertas
    L.libro_id,
    L.isbn,
    L.titulo,
    E.nombre AS encuadernacion,

    -- Datos de cada oferta
    PUB.publicacion_id,
    U.usuario_id,
    U.nombre + ' ' + U.apellido AS vendedor,
    CO.nombre AS condicion,
    PUB.precio,
    PUB.stock AS stock_disponible
FROM dbo.LIBRO AS L
INNER JOIN dbo.ENCUADERNACION AS E
    ON L.encuadernacion_id = E.encuadernacion_id
INNER JOIN dbo.PUBLICACION AS PUB
    ON L.libro_id = PUB.libro_id
INNER JOIN dbo.USUARIO AS U
    ON PUB.usuario_id = U.usuario_id
INNER JOIN dbo.CONDICION AS CO
    ON PUB.condicion_id = CO.condicion_id
WHERE L.libro_id = @libro_id
    AND PUB.disponible = 1 -- no pausada
    AND PUB.fecha_eliminacion IS NULL -- no dada de baja
    AND PUB.stock > 0 -- no agotada
    AND U.fecha_eliminacion IS NULL -- vendedor no dado de baja
-- A igual precio, el número de publicación fija un orden estable.
ORDER BY PUB.precio ASC, PUB.publicacion_id;
