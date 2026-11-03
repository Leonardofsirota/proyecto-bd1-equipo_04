USE [sistema-venta-libros];
GO

IF OBJECT_ID(N'dbo.usp_InsertarCategoria', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_InsertarCategoria;
GO

-- 1. INSERTAR una categoría
-- Da de alta una categoría en la lista de referencia del catálogo (RN09).
-- Recorta los espacios de los extremos del nombre y rechaza uno vacío, de más
-- de 100 caracteres o repetido. Devuelve el ID generado, el nombre guardado y
-- un mensaje de confirmación.
-- @Nombre es VARCHAR(MAX) para recibir el valor completo: con VARCHAR(n),
-- SQL Server truncaría en silencio lo que supere n antes de poder validarlo.
CREATE PROCEDURE dbo.usp_InsertarCategoria
    @Nombre VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    SET @Nombre = LTRIM(RTRIM(@Nombre));

    IF NULLIF(@Nombre, '') IS NULL
        THROW 50001, 'El nombre de la categoria es obligatorio.', 1;

    IF LEN(@Nombre) > 100
        THROW 50008,
              'El nombre de la categoria no puede superar los 100 caracteres.',
              1;

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

IF OBJECT_ID(N'dbo.usp_ModificarCategoria', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_ModificarCategoria;
GO

-- 2. MODIFICAR una categoría
-- Cambia el nombre de una categoría existente (RN09). Recorta los espacios de
-- los extremos y rechaza un nombre vacío, de más de 100 caracteres o que ya use
-- otra categoría, y también un ID inexistente. Devuelve un mensaje de
-- confirmación. Los libros no se tocan: referencian la categoría por su ID.
CREATE PROCEDURE dbo.usp_ModificarCategoria
    @CategoriaId INT,
    @Nombre VARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    SET @Nombre = LTRIM(RTRIM(@Nombre));

    IF NULLIF(@Nombre, '') IS NULL
        THROW 50003, 'El nombre de la categoria es obligatorio.', 1;

    IF LEN(@Nombre) > 100
        THROW 50009,
              'El nombre de la categoria no puede superar los 100 caracteres.',
              1;

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

IF OBJECT_ID(N'dbo.usp_EliminarCategoria', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_EliminarCategoria;
GO

-- 3. ELIMINAR una categoría
-- Borra definitivamente una categoría de la lista de referencia (RN09). Antes
-- comprueba que exista y que ningún libro la use: cada libro debe tener una
-- categoría (RN07), así que en ese caso la rechaza y no borra nada. Devuelve un
-- mensaje de confirmación.
CREATE PROCEDURE dbo.usp_EliminarCategoria
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
