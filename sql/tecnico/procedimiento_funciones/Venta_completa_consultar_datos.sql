SELECT TOP (10)
    usuario_id, nombre, apellido
FROM dbo.USUARIO
WHERE fecha_eliminacion IS NULL;

SELECT *
FROM dbo.PEDIDO_ESTADO;

SELECT *
FROM dbo.CIUDAD;

SELECT TOP (20)
    publicacion_id, libro_id, stock, precio, disponible
FROM dbo.PUBLICACION
WHERE disponible = 1
  AND stock > 0
  AND fecha_eliminacion IS NULL;
GO