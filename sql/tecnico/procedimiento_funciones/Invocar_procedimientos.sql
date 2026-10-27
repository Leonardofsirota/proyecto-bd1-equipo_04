-- Inserciones mediante el procedimiento almacenado
EXEC dbo.usp_InsertarCategoria
    @Nombre = 'Demo Procedimiento A';
GO

EXEC dbo.usp_InsertarCategoria
    @Nombre = 'Demo Procedimiento B';
GO

-- Modificación de un registro insertado directamente
DECLARE @IdModificar INT;

SELECT @IdModificar = categoria_id
FROM dbo.CATEGORIA
WHERE nombre = 'Demo Directa A';

IF @IdModificar IS NOT NULL
BEGIN
    EXEC dbo.usp_ModificarCategoria
        @CategoriaId = @IdModificar,
        @Nombre = 'Demo Directa A Modificada';
END;
GO

-- Eliminación de un registro insertado directamente
DECLARE @IdEliminar INT;

SELECT @IdEliminar = categoria_id
FROM dbo.CATEGORIA
WHERE nombre = 'Demo Directa C';

IF @IdEliminar IS NOT NULL
BEGIN
    EXEC dbo.usp_EliminarCategoria
        @CategoriaId = @IdEliminar;
END;
GO

-- Comprobación de los resultados
SELECT *
FROM dbo.CATEGORIA
WHERE nombre LIKE 'Demo %'
ORDER BY categoria_id;
GO