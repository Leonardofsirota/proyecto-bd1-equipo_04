USE [sistema-venta-libros];
GO

INSERT INTO dbo.CATEGORIA (nombre)
SELECT V.nombre
FROM (VALUES
    ('Demo Directa A'),
    ('Demo Directa B'),
    ('Demo Directa C')
) AS V(nombre)
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.CATEGORIA AS C
    WHERE C.nombre = V.nombre
);
GO

SELECT *
FROM dbo.CATEGORIA
WHERE nombre LIKE 'Demo Directa %'
ORDER BY categoria_id;
GO