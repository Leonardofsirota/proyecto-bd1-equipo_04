
SELECT
    U.usuario_id,
    U.nombre,
    U.apellido,
    L.titulo,
    E.nombre AS encuadernacion
FROM Usuario AS U
INNER JOIN Publicacion AS P
    ON U.usuario_id = P.usuario_id
INNER JOIN Libro AS L
    ON P.libro_id = L.libro_id
INNER JOIN Encuadernacion AS E
    ON L.encuadernacion_id = E.encuadernacion_id
WHERE E.nombre IN ('Tapa blanda', 'Tapa dura');