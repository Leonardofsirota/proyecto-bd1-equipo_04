USE [sistema-venta-libros];
GO

-- Demostración de dbo.usp_RegistrarLibroConAutores (script.sql). Requiere la base
-- instalada completa, con los triggers de sql/ddl/triggers-consistencia.sql.
-- AUTOR y PUBLICACION tienen índices filtrados: sin QUOTED_IDENTIFIER, escribir en
-- ellas falla con el error 1934 desde sqlcmd.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- No corre dentro de una transacción: el procedimiento confirma la suya, y su
-- ROLLBACK anularía la externa. Crea sus propios usuarios, libros (ISBN 999...) y
-- autores (apellido Demo ...), y #LimpiarDemoLibro los borra antes y después, así que
-- se puede ejecutar varias veces sin dejar datos en la base. Lo único que no se
-- revierte son los contadores IDENTITY: cada ejecución, y también cada alta revertida,
-- deja un salto en los ID.
IF OBJECT_ID(N'tempdb..#LimpiarDemoLibro', N'P') IS NOT NULL
    DROP PROCEDURE #LimpiarDemoLibro;
GO

IF OBJECT_ID(N'tempdb..#ConteosDemoLibro', N'P') IS NOT NULL
    DROP PROCEDURE #ConteosDemoLibro;
GO

-- Borra los libros de la demostración con sus autorías y publicaciones, y después los
-- autores y los usuarios. trg_AUTOR_LIBRO_UltimoAutor impide que un libro se quede
-- sin autores, así que se deshabilita solo para esta limpieza. DISABLE TRIGGER es
-- transaccional: si algo falla, XACT_ABORT revierte todo y el trigger vuelve a quedar
-- habilitado.
CREATE PROCEDURE #LimpiarDemoLibro
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Libros TABLE (libro_id INT PRIMARY KEY);

    BEGIN TRANSACTION;

    INSERT INTO @Libros (libro_id)
    SELECT libro_id
    FROM dbo.LIBRO
    WHERE isbn LIKE '999%';

    DISABLE TRIGGER dbo.trg_AUTOR_LIBRO_UltimoAutor ON dbo.AUTOR_LIBRO;

    DELETE FROM dbo.PUBLICACION
    WHERE libro_id IN (SELECT libro_id FROM @Libros);

    DELETE FROM dbo.AUTOR_LIBRO
    WHERE libro_id IN (SELECT libro_id FROM @Libros);

    DELETE FROM dbo.LIBRO
    WHERE libro_id IN (SELECT libro_id FROM @Libros);

    DELETE FROM dbo.AUTOR
    WHERE apellido LIKE 'Demo %';

    DELETE FROM dbo.USUARIO
    WHERE email LIKE 'demo.alta.libro.%@example.com';

    ENABLE TRIGGER dbo.trg_AUTOR_LIBRO_UltimoAutor ON dbo.AUTOR_LIBRO;

    COMMIT TRANSACTION;
END;
GO

-- Cuenta las filas de las cuatro tablas que escribe el alta. Recibe el conteo anterior,
-- lo reemplaza por el actual y devuelve en @Cambios cuántas filas sumó cada tabla.
CREATE PROCEDURE #ConteosDemoLibro
    @Libros INT OUTPUT,
    @Autores INT OUTPUT,
    @AutorLibro INT OUTPUT,
    @Publicaciones INT OUTPUT,
    @Cambios VARCHAR(60) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @L INT = (SELECT COUNT(*) FROM dbo.LIBRO);
    DECLARE @A INT = (SELECT COUNT(*) FROM dbo.AUTOR);
    DECLARE @AL INT = (SELECT COUNT(*) FROM dbo.AUTOR_LIBRO);
    DECLARE @P INT = (SELECT COUNT(*) FROM dbo.PUBLICACION);

    SET @Cambios = 'LIBRO ' + FORMAT(@L - @Libros, '+0;-0;+0')
        + ' / AUTOR ' + FORMAT(@A - @Autores, '+0;-0;+0')
        + ' / AUTOR_LIBRO ' + FORMAT(@AL - @AutorLibro, '+0;-0;+0')
        + ' / PUBLICACION ' + FORMAT(@P - @Publicaciones, '+0;-0;+0');

    SET @Libros = @L;
    SET @Autores = @A;
    SET @AutorLibro = @AL;
    SET @Publicaciones = @P;
END;
GO

-- Con XACT_ABORT en OFF, los errores provocados no cortan el lote.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

EXEC #LimpiarDemoLibro;

DECLARE @Resultados TABLE
(
    orden INT IDENTITY(1,1) PRIMARY KEY,
    caso VARCHAR(70) NOT NULL,
    esperado VARCHAR(60) NOT NULL,
    obtenido VARCHAR(60) NULL,
    resultado AS CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END
);

DECLARE @Admin INT;
DECLARE @Vendedor INT;
DECLARE @VendedorBaja INT;
DECLARE @Cliente INT;
DECLARE @TapaBlanda INT;
DECLARE @Novela INT;
DECLARE @Espanol INT;
DECLARE @Planeta INT;
DECLARE @Nuevo INT;
DECLARE @Argentina INT;
DECLARE @Borges INT;
DECLARE @Cortazar INT;
DECLARE @IsniBorges CHAR(16);
DECLARE @AutorInexistente INT;
DECLARE @CategoriaInexistente INT;
DECLARE @Autores dbo.AutorLibroType;
DECLARE @SinAutores dbo.AutorLibroType;
DECLARE @LibroId INT;
DECLARE @PublicacionId INT;
DECLARE @NLibros INT;
DECLARE @NAutores INT;
DECLARE @NAutorLibro INT;
DECLARE @NPublicaciones INT;
DECLARE @Cambios VARCHAR(60);
DECLARE @Estado VARCHAR(60);
DECLARE @Error INT;
-- Suma @@TRANCOUNT después de cada EXEC: tiene que seguir en cero.
DECLARE @Abiertas INT = 0;

BEGIN TRY
    -- Datos propios: un administrador, dos vendedores y un cliente. El segundo vendedor
    -- se da de baja enseguida.
    INSERT INTO dbo.USUARIO
    (
        nombre,
        apellido,
        dni,
        email,
        telefono,
        fecha_nacimiento,
        password_hash,
        usuario_rol_id
    )
    SELECT
        D.nombre,
        'Demo',
        D.dni,
        D.email,
        '3794000000',
        '1990-01-01',
        'hash-demo',
        UR.usuario_rol_id
    FROM
    (
        VALUES
            ('Administrador', '99000101', 'demo.alta.libro.1@example.com', 'Administrador'),
            ('Vendedor', '99000102', 'demo.alta.libro.2@example.com', 'Vendedor'),
            ('Vendedor baja', '99000103', 'demo.alta.libro.3@example.com', 'Vendedor'),
            ('Cliente', '99000104', 'demo.alta.libro.4@example.com', 'Cliente')
    ) AS D (nombre, dni, email, rol)
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.nombre = D.rol;

    SELECT @Admin = usuario_id FROM dbo.USUARIO WHERE dni = '99000101';
    SELECT @Vendedor = usuario_id FROM dbo.USUARIO WHERE dni = '99000102';
    SELECT @VendedorBaja = usuario_id FROM dbo.USUARIO WHERE dni = '99000103';
    SELECT @Cliente = usuario_id FROM dbo.USUARIO WHERE dni = '99000104';

    UPDATE dbo.USUARIO
    SET fecha_eliminacion = GETDATE()
    WHERE usuario_id = @VendedorBaja;

    SELECT @TapaBlanda = encuadernacion_id FROM dbo.ENCUADERNACION WHERE nombre = 'Tapa blanda';
    SELECT @Novela = categoria_id FROM dbo.CATEGORIA WHERE nombre = 'Novela';
    SELECT @Espanol = idioma_id FROM dbo.IDIOMA WHERE nombre = 'Español';
    SELECT @Planeta = editorial_id FROM dbo.EDITORIAL WHERE nombre = 'Planeta';
    SELECT @Nuevo = condicion_id FROM dbo.CONDICION WHERE nombre = 'Nuevo';
    SELECT @Argentina = nacionalidad_id FROM dbo.NACIONALIDAD WHERE nombre = 'Argentina';

    SELECT @Borges = autor_id, @IsniBorges = isni
    FROM dbo.AUTOR
    WHERE nombre = 'Jorge Luis'
      AND apellido = 'Borges';

    SELECT @Cortazar = autor_id
    FROM dbo.AUTOR
    WHERE nombre = 'Julio'
      AND apellido = 'Cortázar';

    EXEC #ConteosDemoLibro @NLibros OUTPUT, @NAutores OUTPUT, @NAutorLibro OUTPUT, @NPublicaciones OUTPUT;

    -- Caso 1: el vendedor registra un libro de un autor existente y uno nuevo, y lo
    -- publica en la misma operación
    PRINT 'Caso 1: alta completa del vendedor con publicacion';

    INSERT INTO @Autores (fila, autor_id, nombre, apellido, isni, nacionalidad_id)
    VALUES
        (1, @Borges, NULL, NULL, NULL, NULL),
        (2, NULL, 'Autora', 'Demo Uno', '9999999900000011', @Argentina);

    EXEC dbo.usp_RegistrarLibroConAutores
        @UsuarioId = @Vendedor,
        @Isbn = '9990000000001',
        @Titulo = 'Demo alta completa',
        @NroPaginas = 320,
        @AnioPublicacion = 2025,
        @EncuadernacionId = @TapaBlanda,
        @CategoriaId = @Novela,
        @IdiomaId = @Espanol,
        @EditorialId = @Planeta,
        @Autores = @Autores,
        @CondicionId = @Nuevo,
        @Precio = 25000.00,
        @Stock = 5,
        @LibroId = @LibroId OUTPUT,
        @PublicacionId = @PublicacionId OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ConteosDemoLibro @NLibros OUTPUT, @NAutores OUTPUT, @NAutorLibro OUTPUT, @NPublicaciones OUTPUT, @Cambios OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('1. Filas nuevas', 'LIBRO +1 / AUTOR +1 / AUTOR_LIBRO +2 / PUBLICACION +1', @Cambios);

    -- Los OUTPUT apuntan al libro de ese ISBN y a su publicación del vendedor.
    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '1. @LibroId y @PublicacionId',
        'coinciden',
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM dbo.LIBRO AS L
                INNER JOIN dbo.PUBLICACION AS PUB
                    ON PUB.libro_id = L.libro_id
                WHERE L.isbn = '9990000000001'
                  AND L.libro_id = @LibroId
                  AND PUB.publicacion_id = @PublicacionId
                  AND PUB.usuario_id = @Vendedor
            ) THEN 'coinciden'
            ELSE 'no coinciden'
        END
    );

    SET @Estado = NULL;

    SELECT @Estado = 'existente ' + CAST(SUM(CASE WHEN AL.autor_id = @Borges THEN 1 ELSE 0 END) AS VARCHAR(10))
        + ' / nuevo ' + CAST(SUM(CASE WHEN A.apellido = 'Demo Uno' THEN 1 ELSE 0 END) AS VARCHAR(10))
    FROM dbo.AUTOR_LIBRO AS AL
    INNER JOIN dbo.AUTOR AS A
        ON A.autor_id = AL.autor_id
    WHERE AL.libro_id = @LibroId;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('1. Autores del libro', 'existente 1 / nuevo 1', @Estado);

    SET @Estado = NULL;

    SELECT @Estado = 'disponible ' + CAST(disponible AS VARCHAR(1))
        + ' / stock ' + CAST(stock AS VARCHAR(10))
        + ' / precio ' + CAST(precio AS VARCHAR(20))
    FROM dbo.PUBLICACION
    WHERE publicacion_id = @PublicacionId;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('1. Publicacion', 'disponible 1 / stock 5 / precio 25000.00', @Estado);

    -- Caso 2: el administrador registra un libro de dos autores existentes, sin
    -- publicarlo. @PublicacionId todavía tiene el ID del caso 1: tiene que volver NULL
    PRINT 'Caso 2: alta del administrador sin publicacion';

    DELETE FROM @Autores;
    INSERT INTO @Autores (fila, autor_id)
    VALUES
        (1, @Borges),
        (2, @Cortazar);

    EXEC dbo.usp_RegistrarLibroConAutores
        @UsuarioId = @Admin,
        @Isbn = '9990000000002',
        @Titulo = 'Demo alta sin publicacion',
        @NroPaginas = 180,
        @AnioPublicacion = 2024,
        @EncuadernacionId = @TapaBlanda,
        @CategoriaId = @Novela,
        @IdiomaId = @Espanol,
        @EditorialId = @Planeta,
        @Autores = @Autores,
        @LibroId = @LibroId OUTPUT,
        @PublicacionId = @PublicacionId OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ConteosDemoLibro @NLibros OUTPUT, @NAutores OUTPUT, @NAutorLibro OUTPUT, @NPublicaciones OUTPUT, @Cambios OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('2. Filas nuevas', 'LIBRO +1 / AUTOR +0 / AUTOR_LIBRO +2 / PUBLICACION +0', @Cambios),
        ('2. @PublicacionId', 'NULL', COALESCE(CAST(@PublicacionId AS VARCHAR(10)), 'NULL'));

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '2. @LibroId',
        'coincide',
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM dbo.LIBRO
                WHERE isbn = '9990000000002'
                  AND libro_id = @LibroId
            ) THEN 'coincide'
            ELSE 'no coincide'
        END
    );

    -- Caso 3: el segundo autor nuevo tiene el ISNI de Borges. Falla en el paso 3,
    -- después de insertar el libro y el primer autor nuevo, y el ROLLBACK deshace los dos
    PRINT 'Caso 3: fallo al insertar el segundo autor nuevo';

    DELETE FROM @Autores;
    INSERT INTO @Autores (fila, autor_id, nombre, apellido, isni, nacionalidad_id)
    VALUES
        (1, NULL, 'Autor', 'Demo Tres A', '9999999900000031', @Argentina),
        (2, NULL, 'Autor', 'Demo Tres B', @IsniBorges, NULL);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000003',
            @Titulo = 'Demo alta revertida',
            @NroPaginas = 200,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ConteosDemoLibro @NLibros OUTPUT, @NAutores OUTPUT, @NAutorLibro OUTPUT, @NPublicaciones OUTPUT, @Cambios OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('3. Error de uq_autor_isni', '2601', CAST(@Error AS VARCHAR(10))),
        ('3. Filas nuevas tras el ROLLBACK', 'LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0', @Cambios);

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT '3. Libros con el ISBN 9990000000003', '0', CAST(COUNT(*) AS VARCHAR(10))
    FROM dbo.LIBRO
    WHERE isbn = '9990000000003';

    -- Caso 4: el precio 0 viola chk_publicacion_precio en el paso 5, el último. El
    -- ROLLBACK deshace el libro, el autor nuevo y sus filas de AUTOR_LIBRO
    PRINT 'Caso 4: fallo al insertar la publicacion';

    DELETE FROM @Autores;
    INSERT INTO @Autores (fila, autor_id, nombre, apellido, isni, nacionalidad_id)
    VALUES
        (1, @Borges, NULL, NULL, NULL, NULL),
        (2, NULL, 'Autora', 'Demo Cuatro', '9999999900000041', @Argentina);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000004',
            @Titulo = 'Demo publicacion rechazada',
            @NroPaginas = 250,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores,
            @CondicionId = @Nuevo,
            @Precio = 0.00,
            @Stock = 3;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ConteosDemoLibro @NLibros OUTPUT, @NAutores OUTPUT, @NAutorLibro OUTPUT, @NPublicaciones OUTPUT, @Cambios OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('4. Error de chk_publicacion_precio', '547', CAST(@Error AS VARCHAR(10))),
        ('4. Filas nuevas tras el ROLLBACK', 'LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0', @Cambios);

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT
        '4. Libro y autor nuevo que quedaron',
        'libro 0 / autor 0',
        'libro ' + CAST((SELECT COUNT(*) FROM dbo.LIBRO WHERE isbn = '9990000000004') AS VARCHAR(10))
            + ' / autor ' + CAST((SELECT COUNT(*) FROM dbo.AUTOR WHERE isni = '9999999900000041') AS VARCHAR(10));

    -- Caso 5: las sentencias del caso 3, sueltas. Sin transacción, cada una se confirma
    -- por su cuenta: el error del segundo autor no deshace el libro ni el primer autor,
    -- y la autoría nunca llega a insertarse
    PRINT 'Caso 5: el alta del caso 3 sin transaccion';

    SET @Error = NULL;
    BEGIN TRY
        INSERT INTO dbo.LIBRO
        (
            isbn,
            titulo,
            nro_paginas,
            encuadernacion_id,
            categoria_id,
            idioma_id,
            editorial_id,
            anio_publicacion
        )
        VALUES
        (
            '9990000000003',
            'Demo alta revertida',
            200,
            @TapaBlanda,
            @Novela,
            @Espanol,
            @Planeta,
            2025
        );

        SET @LibroId = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO dbo.AUTOR (nombre, apellido, isni, nacionalidad_id)
        VALUES ('Autor', 'Demo Tres A', '9999999900000031', @Argentina);

        INSERT INTO dbo.AUTOR (nombre, apellido, isni, nacionalidad_id)
        VALUES ('Autor', 'Demo Tres B', @IsniBorges, NULL);

        -- No se llega: el INSERT anterior falla.
        INSERT INTO dbo.AUTOR_LIBRO (libro_id, autor_id)
        SELECT @LibroId, autor_id
        FROM dbo.AUTOR
        WHERE apellido IN ('Demo Tres A', 'Demo Tres B');
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;

    EXEC #ConteosDemoLibro @NLibros OUTPUT, @NAutores OUTPUT, @NAutorLibro OUTPUT, @NPublicaciones OUTPUT, @Cambios OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('5. Error de uq_autor_isni', '2601', CAST(@Error AS VARCHAR(10))),
        ('5. Filas que quedaron', 'LIBRO +1 / AUTOR +1 / AUTOR_LIBRO +0 / PUBLICACION +0', @Cambios);

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT '5. Libros de la demostracion sin autor (RN08)', '1', CAST(COUNT(*) AS VARCHAR(10))
    FROM dbo.LIBRO AS L
    WHERE L.isbn LIKE '999%'
      AND NOT EXISTS (
              SELECT 1
              FROM dbo.AUTOR_LIBRO AS AL
              WHERE AL.libro_id = L.libro_id
          );

    -- Caso 6: el ISBN del caso 1 ya está registrado (RN06)
    PRINT 'Caso 6: ISBN repetido';

    DELETE FROM @Autores;
    INSERT INTO @Autores (fila, autor_id)
    VALUES (1, @Cortazar);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000001',
            @Titulo = 'Demo ISBN repetido',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('6. ISBN repetido', '50306', CAST(@Error AS VARCHAR(10)));

    -- Caso 7: cada validación previa a la transacción. Salvo el dato indicado, cada
    -- llamada es un alta válida de Cortázar con el ISBN 9990000000007
    PRINT 'Caso 7: validaciones';

    EXEC #ConteosDemoLibro @NLibros OUTPUT, @NAutores OUTPUT, @NAutorLibro OUTPUT, @NPublicaciones OUTPUT;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Cliente,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. Un cliente registra el libro', '50301', CAST(@Error AS VARCHAR(10)));

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @VendedorBaja,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. Un vendedor dado de baja registra el libro', '50301', CAST(@Error AS VARCHAR(10)));

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @SinAutores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. Lista de autores vacia', '50302', CAST(@Error AS VARCHAR(10)));

    DELETE FROM @Autores;
    INSERT INTO @Autores (fila, autor_id, nombre, apellido)
    VALUES (1, @Cortazar, 'Julio', 'Cortázar');

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. Fila con autor_id y nombre a la vez', '50303', CAST(@Error AS VARCHAR(10)));

    -- Se calcula aquí y no al principio: los casos anteriores agregaron autores.
    SELECT @AutorInexistente = MAX(autor_id) + 1 FROM dbo.AUTOR;

    DELETE FROM @Autores;
    INSERT INTO @Autores (fila, autor_id)
    VALUES (1, @AutorInexistente);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. autor_id inexistente', '50304', CAST(@Error AS VARCHAR(10)));

    DELETE FROM @Autores;
    INSERT INTO @Autores (fila, autor_id)
    VALUES
        (1, @Cortazar),
        (2, @Cortazar);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. El mismo autor dos veces', '50305', CAST(@Error AS VARCHAR(10)));

    DELETE FROM @Autores;
    INSERT INTO @Autores (fila, autor_id)
    VALUES (1, @Cortazar);

    SELECT @CategoriaInexistente = MAX(categoria_id) + 1 FROM dbo.CATEGORIA;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @CategoriaInexistente,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. Categoria inexistente', '50307', CAST(@Error AS VARCHAR(10)));

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Vendedor,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores,
            @Precio = 15000.00,
            @Stock = 2;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. Publicacion sin condicion', '50308', CAST(@Error AS VARCHAR(10)));

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarLibroConAutores
            @UsuarioId = @Admin,
            @Isbn = '9990000000007',
            @Titulo = 'Demo validacion',
            @NroPaginas = 100,
            @AnioPublicacion = 2025,
            @EncuadernacionId = @TapaBlanda,
            @CategoriaId = @Novela,
            @IdiomaId = @Espanol,
            @EditorialId = @Planeta,
            @Autores = @Autores,
            @CondicionId = @Nuevo,
            @Precio = 15000.00,
            @Stock = 2;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. El administrador pide publicar', '50309', CAST(@Error AS VARCHAR(10)));

    EXEC #ConteosDemoLibro @NLibros OUTPUT, @NAutores OUTPUT, @NAutorLibro OUTPUT, @NPublicaciones OUTPUT, @Cambios OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. Filas nuevas tras las validaciones', 'LIBRO +0 / AUTOR +0 / AUTOR_LIBRO +0 / PUBLICACION +0', @Cambios);

    -- Caso 8: ninguna llamada dejó una transacción abierta, ni las que fallaron
    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('8. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));
END TRY
BEGIN CATCH
    -- Un error no previsto queda como FALLO: así el lote termina, se muestran los
    -- resultados y el lote siguiente limpia los datos.
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('Error no previsto', 'ninguno', LEFT(ERROR_MESSAGE(), 60));
END CATCH;

SELECT
    caso,
    esperado,
    obtenido,
    resultado
FROM @Resultados
ORDER BY orden;

SELECT
    COUNT(*) AS comprobaciones,
    SUM(CASE WHEN resultado = 'OK' THEN 1 ELSE 0 END) AS correctas,
    SUM(CASE WHEN resultado = 'FALLO' THEN 1 ELSE 0 END) AS fallidas
FROM @Resultados;
GO

-- Lote propio: corre aunque la demostración falle.
EXEC #LimpiarDemoLibro;

SELECT
    (SELECT COUNT(*) FROM dbo.USUARIO WHERE email LIKE 'demo.alta.libro.%@example.com')
  + (SELECT COUNT(*) FROM dbo.LIBRO WHERE isbn LIKE '999%')
  + (SELECT COUNT(*) FROM dbo.AUTOR WHERE apellido LIKE 'Demo %') AS filas_demo;

DROP PROCEDURE #LimpiarDemoLibro;
DROP PROCEDURE #ConteosDemoLibro;
GO
