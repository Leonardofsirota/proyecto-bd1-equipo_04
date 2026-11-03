USE [sistema-venta-libros];
GO

-- Demostración de los procedimientos de script.sql. Corre en una transacción que
-- termina en ROLLBACK, así que se puede ejecutar varias veces sin dejar datos en
-- la base. Lo único que no se revierte es el contador IDENTITY: cada ejecución
-- deja un salto en categoria_id. Con XACT_ABORT en OFF, los errores provocados no
-- anulan la transacción.
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
