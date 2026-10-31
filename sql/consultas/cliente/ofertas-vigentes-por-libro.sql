/* Ofertas vigentes de un libro: compara las publicaciones de un mismo libro
   entre vendedores, con la condición del ejemplar, el precio y el stock
   libre, de menor a mayor precio.

   Solo se listan las ofertas que un cliente puede agregar a un pedido (RN12):
   publicaciones activas y con stock libre, de vendedores que no fueron dados de
   baja (RN28). El stock libre descuenta las reservas vigentes (RN33) y es el
   mismo que valida usp_CrearPedido (RN13), así que una oferta con todas sus
   unidades reservadas no se lista. Si el libro indicado no tiene ofertas
   vigentes, la consulta no devuelve filas.

   Requiere dbo.fn_StockLibre: ejecutar antes
   sql/tecnico/procedimientos_funciones/registrar_venta/script.sql. */

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
    dbo.fn_StockLibre(PUB.publicacion_id, NULL) AS stock_disponible
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
    AND dbo.fn_StockLibre(PUB.publicacion_id, NULL) > 0 -- ni agotada ni reservada
    AND U.fecha_eliminacion IS NULL -- vendedor no dado de baja
-- A igual precio, el número de publicación fija un orden estable.
ORDER BY PUB.precio ASC, PUB.publicacion_id;
