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

-- Demostración. Corre en una transacción que termina en ROLLBACK, así que se
-- puede ejecutar varias veces sin dejar datos en la base. Lo único que no se
-- revierte es el contador IDENTITY: cada ejecución deja un salto en categoria_id.
-- Con XACT_ABORT en OFF, los errores provocados no anulan la transacción.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

DECLARE @Errores TABLE
(
    esperado INT PRIMARY KEY,
    caso VARCHAR(60) NOT NULL,
    obtenido INT NULL,
    mensaje NVARCHAR(4000) NULL
);

INSERT INTO @Errores (esperado, caso)
VALUES
    (50001, 'Insertar: nombre solo con espacios'),
    (50002, 'Insertar: nombre repetido'),
    (50003, 'Modificar: nombre NULL'),
    (50004, 'Modificar: categoría inexistente'),
    (50005, 'Modificar: nombre de otra categoría'),
    (50006, 'Eliminar: categoría inexistente'),
    (50007, 'Eliminar: categoría con libros asociados'),
    (50008, 'Insertar: nombre de 150 caracteres'),
    (50009, 'Modificar: nombre de 101 caracteres');

DECLARE @IdHistorica INT;
DECLARE @IdTeatro INT;
DECLARE @IdConLibros INT;
DECLARE @Nombre100 VARCHAR(150) = '  Demo ABM ' + REPLICATE('x', 91) + '  ';
DECLARE @Nombre101 VARCHAR(150) = 'Demo ABM ' + REPLICATE('x', 92);
DECLARE @Nombre150 VARCHAR(150) = 'Demo ABM ' + REPLICATE('x', 141);

BEGIN TRY
    BEGIN TRANSACTION;

    -- Inserciones correctas
    EXEC dbo.usp_InsertarCategoria
        @Nombre = 'Demo ABM Narrativa Histórica';

    EXEC dbo.usp_InsertarCategoria
        @Nombre = 'Demo ABM Teatro Clásico';

    -- Los espacios de los extremos se recortan antes de validar y de guardar
    EXEC dbo.usp_InsertarCategoria
        @Nombre = '   Demo ABM Poesía Española   ';

    -- Sin los espacios tiene 100 caracteres, el máximo permitido
    EXEC dbo.usp_InsertarCategoria
        @Nombre = @Nombre100;

    SELECT @IdHistorica = categoria_id
    FROM dbo.CATEGORIA
    WHERE nombre = 'Demo ABM Narrativa Histórica';

    SELECT @IdTeatro = categoria_id
    FROM dbo.CATEGORIA
    WHERE nombre = 'Demo ABM Teatro Clásico';

    -- Modificación correcta
    EXEC dbo.usp_ModificarCategoria
        @CategoriaId = @IdHistorica,
        @Nombre = '  Demo ABM Narrativa Épica  ';

    -- Eliminación correcta
    EXEC dbo.usp_EliminarCategoria
        @CategoriaId = @IdTeatro;

    -- Error 50001: el nombre solo tiene espacios
    BEGIN TRY
        EXEC dbo.usp_InsertarCategoria
            @Nombre = '   ';
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50001;
    END CATCH;

    -- Error 50002: repetido, aunque llegue con espacios en los extremos
    BEGIN TRY
        EXEC dbo.usp_InsertarCategoria
            @Nombre = '  Demo ABM Narrativa Épica  ';
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50002;
    END CATCH;

    -- Error 50003: el nombre es NULL
    BEGIN TRY
        EXEC dbo.usp_ModificarCategoria
            @CategoriaId = @IdHistorica,
            @Nombre = NULL;
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50003;
    END CATCH;

    -- Error 50004: la categoría no existe
    BEGIN TRY
        EXEC dbo.usp_ModificarCategoria
            @CategoriaId = 0,
            @Nombre = 'Demo ABM Sin Categoría';
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50004;
    END CATCH;

    -- Error 50005: el nombre ya lo usa otra categoría
    BEGIN TRY
        EXEC dbo.usp_ModificarCategoria
            @CategoriaId = @IdHistorica,
            @Nombre = 'Demo ABM Poesía Española';
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50005;
    END CATCH;

    -- Error 50006: la categoría no existe
    BEGIN TRY
        EXEC dbo.usp_EliminarCategoria
            @CategoriaId = 0;
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50006;
    END CATCH;

    -- Error 50007: la categoría tiene libros asociados
    SELECT TOP (1) @IdConLibros = categoria_id
    FROM dbo.LIBRO
    ORDER BY categoria_id;

    BEGIN TRY
        EXEC dbo.usp_EliminarCategoria
            @CategoriaId = @IdConLibros;
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50007;
    END CATCH;

    -- Error 50008: nombre demasiado largo al insertar
    BEGIN TRY
        EXEC dbo.usp_InsertarCategoria
            @Nombre = @Nombre150;
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50008;
    END CATCH;

    -- Error 50009: nombre demasiado largo al modificar
    BEGIN TRY
        EXEC dbo.usp_ModificarCategoria
            @CategoriaId = @IdHistorica,
            @Nombre = @Nombre101;
    END TRY
    BEGIN CATCH
        UPDATE @Errores
        SET obtenido = ERROR_NUMBER(), mensaje = ERROR_MESSAGE()
        WHERE esperado = 50009;
    END CATCH;

    -- Estado antes del ROLLBACK: los casos correctos aplicados y los errores sin
    -- efecto
    SELECT categoria_id, nombre, LEN(nombre) AS longitud
    FROM dbo.CATEGORIA
    WHERE nombre LIKE 'Demo ABM %'
    ORDER BY categoria_id;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

-- @Errores es una variable de tabla: conserva sus filas después del ROLLBACK
SELECT
    esperado,
    obtenido,
    CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END AS resultado,
    caso,
    mensaje
FROM @Errores
ORDER BY esperado;

-- Comprobación de los resultados: el ROLLBACK no dejó ninguna fila de demostración
SELECT COUNT(*) AS filas_demo
FROM dbo.CATEGORIA
WHERE nombre LIKE 'Demo ABM %';
GO
