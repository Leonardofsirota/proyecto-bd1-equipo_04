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