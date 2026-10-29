USE [sistema-venta-libros];
GO

-- 1. INSERTAR una categoría
CREATE OR ALTER PROCEDURE dbo.usp_InsertarCategoria
    @Nombre VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF NULLIF(LTRIM(RTRIM(@Nombre)), '') IS NULL
        THROW 50001, 'El nombre de la categoria es obligatorio.', 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.CATEGORIA
        WHERE nombre = @Nombre
    )
        THROW 50002, 'La categoria ya existe.', 1;

    INSERT INTO dbo.CATEGORIA (nombre)
    VALUES (@Nombre);

    SELECT
        CAST(SCOPE_IDENTITY() AS INT) AS categoria_id,
        @Nombre AS nombre,
        'Categoria insertada correctamente' AS mensaje;
END;
GO

-- 2. MODIFICAR una categoría
CREATE OR ALTER PROCEDURE dbo.usp_ModificarCategoria
    @CategoriaId INT,
    @Nombre VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF NULLIF(LTRIM(RTRIM(@Nombre)), '') IS NULL
        THROW 50003, 'El nombre de la categoria es obligatorio.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.CATEGORIA
        WHERE categoria_id = @CategoriaId
    )
        THROW 50004, 'La categoria indicada no existe.', 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.CATEGORIA
        WHERE nombre = @Nombre
          AND categoria_id <> @CategoriaId
    )
        THROW 50005, 'Ya existe otra categoria con ese nombre.', 1;

    UPDATE dbo.CATEGORIA
    SET nombre = @Nombre
    WHERE categoria_id = @CategoriaId;

    SELECT 'Categoria modificada correctamente' AS mensaje;
END;
GO

-- 3. ELIMINAR una categoría
CREATE OR ALTER PROCEDURE dbo.usp_EliminarCategoria
    @CategoriaId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.CATEGORIA
        WHERE categoria_id = @CategoriaId
    )
        THROW 50006, 'La categoria indicada no existe.', 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.LIBRO
        WHERE categoria_id = @CategoriaId
    )
        THROW 50007,
              'No se puede eliminar: la categoria tiene libros asociados.',
              1;

    DELETE FROM dbo.CATEGORIA
    WHERE categoria_id = @CategoriaId;

    SELECT 'Categoria eliminada correctamente' AS mensaje;
END;
GO

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
