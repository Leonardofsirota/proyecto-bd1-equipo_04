/* Búsqueda en el catálogo: libros cuyo título, ISBN o nombre de alguno de sus
   autores contiene el texto buscado, con su ficha, sus autores, la cantidad de
   ofertas vigentes y el precio más bajo entre ellas. Es el paso previo a
   consultar las ofertas de un libro (ofertas-vigentes-por-libro.sql), que
   necesita su ID.

   También se listan los libros sin ofertas vigentes, al final: el cliente ve
   que no están disponibles y el vendedor comprueba si el libro ya está en el
   catálogo antes de darlo de alta (RN06 y RN09). Si ningún libro coincide con
   el texto, la consulta no devuelve filas.

   Requiere dbo.fn_StockLibre: ejecutar antes
   sql/tecnico/procedimientos_funciones/registrar_venta/script.sql. */

-- Requerido por el método .value() de XML que arma la lista de autores.
-- SSMS lo activa por defecto; sqlcmd no.
SET QUOTED_IDENTIFIER ON;

DECLARE @texto VARCHAR(100) = 'borges';

DECLARE @patron VARCHAR(102) = '%' + @texto + '%';

SELECT
    L.libro_id,
    L.isbn,
    L.titulo,
    -- Todos los autores del libro en una sola columna (RN08). SQL Server 2012
    -- no tiene STRING_AGG: FOR XML PATH concatena las filas y STUFF quita la
    -- coma inicial.
    STUFF((
        SELECT ', ' + A.nombre + ' ' + A.apellido
        FROM dbo.AUTOR_LIBRO AS AL
        INNER JOIN dbo.AUTOR AS A
            ON AL.autor_id = A.autor_id
        WHERE AL.libro_id = L.libro_id
        ORDER BY AL.autor_libro_id
        FOR XML PATH(''), TYPE
    ).value('.', 'VARCHAR(MAX)'), 1, 2, '') AS autores,
    ED.nombre AS editorial,
    L.anio_publicacion,
    C.nombre AS categoria,
    I.nombre AS idioma,
    E.nombre AS encuadernacion,
    COALESCE(OV.cantidad_ofertas, 0) AS ofertas_vigentes,
    OV.precio_minimo AS precio_desde
FROM dbo.LIBRO AS L
INNER JOIN dbo.EDITORIAL AS ED
    ON L.editorial_id = ED.editorial_id
INNER JOIN dbo.CATEGORIA AS C
    ON L.categoria_id = C.categoria_id
INNER JOIN dbo.IDIOMA AS I
    ON L.idioma_id = I.idioma_id
INNER JOIN dbo.ENCUADERNACION AS E
    ON L.encuadernacion_id = E.encuadernacion_id
-- Ofertas que un cliente puede agregar a un pedido (RN12), con el mismo
-- criterio que ofertas-vigentes-por-libro.sql. Es un LEFT JOIN para no perder
-- los libros que no tienen ninguna.
LEFT JOIN (
    SELECT
        PUB.libro_id,
        COUNT(*) AS cantidad_ofertas,
        MIN(PUB.precio) AS precio_minimo
    FROM dbo.PUBLICACION AS PUB
    INNER JOIN dbo.USUARIO AS U
        ON PUB.usuario_id = U.usuario_id
    WHERE PUB.disponible = 1 -- no pausada
        AND PUB.fecha_eliminacion IS NULL -- no dada de baja
        AND dbo.fn_StockLibre(PUB.publicacion_id, NULL) > 0 -- ni agotada ni reservada
        AND U.fecha_eliminacion IS NULL -- vendedor no dado de baja
    GROUP BY PUB.libro_id
) AS OV
    ON L.libro_id = OV.libro_id
-- La intercalación Latin1_General_CI_AI no distingue mayúsculas ni acentos:
-- 'cortazar' encuentra 'Cortázar'.
WHERE L.titulo COLLATE Latin1_General_CI_AI LIKE @patron
    OR L.isbn LIKE @patron
    OR EXISTS (
        SELECT 1
        FROM dbo.AUTOR_LIBRO AS AL
        INNER JOIN dbo.AUTOR AS A
            ON AL.autor_id = A.autor_id
        WHERE AL.libro_id = L.libro_id
            AND (A.nombre + ' ' + A.apellido) COLLATE Latin1_General_CI_AI LIKE @patron
    )
-- Primero los libros que se pueden comprar. A igual título, el número de libro
-- fija un orden estable.
ORDER BY
    CASE WHEN OV.libro_id IS NULL THEN 1 ELSE 0 END,
    L.titulo,
    L.libro_id;
