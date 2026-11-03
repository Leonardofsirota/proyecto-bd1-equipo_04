USE [sistema-venta-libros];
GO

-- Quedan registradas en el procedimiento: sqlcmd trae QUOTED_IDENTIFIER en OFF, y
-- escribir en AUTOR o PUBLICACION, que tienen índices filtrados, falla con el error
-- 1934.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Se elimina antes que el tipo, porque depende de él.
IF OBJECT_ID(N'dbo.usp_RegistrarLibroConAutores', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RegistrarLibroConAutores;
GO

IF TYPE_ID(N'dbo.AutorLibroType') IS NOT NULL
    DROP TYPE dbo.AutorLibroType;
GO

-- Autores de un libro: una fila por autor, en el orden de fila. Cada fila indica un
-- autor ya registrado, con autor_id, o los datos de uno nuevo: nombre y apellido,
-- y opcionalmente su ISNI y su nacionalidad.
CREATE TYPE dbo.AutorLibroType AS TABLE
(
    fila INT NOT NULL PRIMARY KEY,
    autor_id INT NULL,
    nombre VARCHAR(100) NULL,
    apellido VARCHAR(100) NULL,
    isni CHAR(16) NULL,
    nacionalidad_id INT NULL
);
GO

-- ALTA de un libro con sus autores
-- Registra un libro, sus autores nuevos, la autoría y, si se pide, la primera
-- publicación del vendedor que lo carga. RN08 (todo libro tiene al menos un autor) no
-- se puede exigir con un trigger en el alta: el libro debe existir antes que sus filas
-- de AUTOR_LIBRO. Si la carga se cortara entre los dos INSERT, quedaría un libro sin
-- autor. Por eso todo ocurre en una sola transacción: se registra el alta completa o
-- no se registra nada.
-- El formato de los datos (ISBN de 13 dígitos, nombres, ISNI, páginas, año, precio y
-- stock) no se repite aquí: lo controlan los CHECK y los índices del DDL. Un error de
-- formato puede aparecer en cualquier paso, y el ROLLBACK deshace los anteriores.
-- @Isbn y @Titulo son VARCHAR(MAX) para recibir el valor completo: con VARCHAR(n),
-- SQL Server truncaría en silencio lo que supere n antes de que lo controle el DDL.
-- Devuelve el ID del libro, su ISBN, la cantidad de autores y de autores nuevos, el ID
-- de la publicación (NULL si no se publicó) y un mensaje.
CREATE PROCEDURE dbo.usp_RegistrarLibroConAutores
    @UsuarioId INT,
    @Isbn VARCHAR(MAX),
    @Titulo VARCHAR(MAX),
    @NroPaginas INT,
    @AnioPublicacion SMALLINT,
    @EncuadernacionId INT,
    @CategoriaId INT,
    @IdiomaId INT,
    @EditorialId INT,
    @Autores dbo.AutorLibroType READONLY,
    @CondicionId INT = NULL,
    @Precio DECIMAL(18, 2) = NULL,
    @Stock INT = NULL,
    @LibroId INT = NULL OUTPUT,
    @PublicacionId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Rol VARCHAR(50);
    DECLARE @Publicar BIT;
    DECLARE @Fila INT;
    DECLARE @AutorId INT;
    DECLARE @Final TABLE
    (
        fila INT NOT NULL PRIMARY KEY,
        autor_id INT NOT NULL
    );

    -- Un parámetro OUTPUT también recibe el valor de la variable del llamador: sin
    -- esto, un alta sin publicación devolvería en @PublicacionId un ID anterior.
    SET @LibroId = NULL;
    SET @PublicacionId = NULL;

    -- Validaciones antes de la transacción. Si otra sesión borrara un autor o un
    -- elemento de catálogo mientras tanto, la clave foránea rechazaría el INSERT y el
    -- ROLLBACK desharía el alta.

    -- RN09: el administrador mantiene el catálogo, y un vendedor puede dar de alta un
    -- libro que todavía no está.
    SELECT @Rol = UR.nombre
    FROM dbo.USUARIO AS U
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.usuario_rol_id = U.usuario_rol_id
    WHERE U.usuario_id = @UsuarioId
      AND U.fecha_eliminacion IS NULL;

    IF @Rol IS NULL OR @Rol NOT IN ('Administrador', 'Vendedor')
        THROW 50301,
              'El usuario no existe, esta dado de baja o no es administrador ni vendedor.',
              1;

    IF NOT EXISTS (SELECT 1 FROM @Autores)
        THROW 50302, 'El libro debe tener al menos un autor.', 1;

    -- Cada fila es un autor existente o uno nuevo, nunca las dos cosas.
    IF EXISTS (
        SELECT 1
        FROM @Autores
        WHERE (autor_id IS NOT NULL
               AND (nombre IS NOT NULL
                    OR apellido IS NOT NULL
                    OR isni IS NOT NULL
                    OR nacionalidad_id IS NOT NULL))
           OR (autor_id IS NULL
               AND (nombre IS NULL OR apellido IS NULL))
    )
        THROW 50303,
              'Cada fila indica un autor existente o el nombre y el apellido de uno nuevo.',
              1;

    IF EXISTS (
        SELECT 1
        FROM @Autores AS A
        WHERE A.autor_id IS NOT NULL
          AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.AUTOR AS AU
                  WHERE AU.autor_id = A.autor_id
              )
    )
        THROW 50304, 'Hay autores que no existen.', 1;

    -- El mismo autor_id, o el mismo ISNI en dos autores nuevos, es el mismo autor.
    IF EXISTS (
        SELECT 1
        FROM @Autores
        WHERE autor_id IS NOT NULL
        GROUP BY autor_id
        HAVING COUNT(*) > 1
    )
    OR EXISTS (
        SELECT 1
        FROM @Autores
        WHERE isni IS NOT NULL
        GROUP BY isni
        HAVING COUNT(*) > 1
    )
        THROW 50305, 'Un autor se repite en la lista.', 1;

    -- RN07. Un valor NULL tampoco existe.
    IF NOT EXISTS (SELECT 1 FROM dbo.ENCUADERNACION WHERE encuadernacion_id = @EncuadernacionId)
       OR NOT EXISTS (SELECT 1 FROM dbo.CATEGORIA WHERE categoria_id = @CategoriaId)
       OR NOT EXISTS (SELECT 1 FROM dbo.IDIOMA WHERE idioma_id = @IdiomaId)
       OR NOT EXISTS (SELECT 1 FROM dbo.EDITORIAL WHERE editorial_id = @EditorialId)
       OR (@CondicionId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM dbo.CONDICION WHERE condicion_id = @CondicionId))
       OR EXISTS (
              SELECT 1
              FROM @Autores AS A
              WHERE A.nacionalidad_id IS NOT NULL
                AND NOT EXISTS (
                        SELECT 1
                        FROM dbo.NACIONALIDAD AS N
                        WHERE N.nacionalidad_id = A.nacionalidad_id
                    )
          )
        THROW 50307,
              'No existe la encuadernacion, categoria, idioma, editorial, condicion o nacionalidad indicada.',
              1;

    -- RN10: la publicación es opcional, pero va completa y solo la hace un vendedor.
    SET @Publicar = CASE
                        WHEN @CondicionId IS NULL AND @Precio IS NULL AND @Stock IS NULL THEN 0
                        ELSE 1
                    END;

    IF @Publicar = 1 AND (@CondicionId IS NULL OR @Precio IS NULL OR @Stock IS NULL)
        THROW 50308, 'Para publicar se indican la condicion, el precio y el stock.', 1;

    IF @Publicar = 1 AND @Rol <> 'Vendedor'
        THROW 50309, 'Solo un vendedor puede publicar el libro.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- RN06. UPDLOCK y HOLDLOCK retienen hasta el COMMIT el rango de esta clave en
        -- uq_libro_isbn, aunque el ISBN todavía no exista: otra alta del mismo ISBN
        -- espera aquí y, cuando esta confirma, recibe 50306 en lugar del error 2627 del
        -- índice. Sin el bloqueo, con READ_COMMITTED_SNAPSHOT la lectura usaría la
        -- última versión confirmada y no vería un alta en curso.
        IF EXISTS (
            SELECT 1
            FROM dbo.LIBRO WITH (UPDLOCK, HOLDLOCK)
            WHERE isbn = @Isbn
        )
            THROW 50306, 'Ya existe un libro con ese ISBN.', 1;

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
            @Isbn,
            @Titulo,
            @NroPaginas,
            @EncuadernacionId,
            @CategoriaId,
            @IdiomaId,
            @EditorialId,
            @AnioPublicacion
        );

        SET @LibroId = CAST(SCOPE_IDENTITY() AS INT);

        -- Los autores nuevos se insertan de a uno, en el orden de fila, para conocer el
        -- ID de cada uno: INSERT ... OUTPUT solo devuelve columnas de la tabla destino,
        -- y no diría a qué fila de @Autores corresponde cada ID.
        SELECT @Fila = MIN(fila)
        FROM @Autores;

        WHILE @Fila IS NOT NULL
        BEGIN
            SELECT @AutorId = autor_id
            FROM @Autores
            WHERE fila = @Fila;

            IF @AutorId IS NULL
            BEGIN
                INSERT INTO dbo.AUTOR
                (
                    nombre,
                    apellido,
                    isni,
                    nacionalidad_id
                )
                SELECT
                    nombre,
                    apellido,
                    isni,
                    nacionalidad_id
                FROM @Autores
                WHERE fila = @Fila;

                SET @AutorId = CAST(SCOPE_IDENTITY() AS INT);
            END;

            INSERT INTO @Final (fila, autor_id)
            VALUES (@Fila, @AutorId);

            SELECT @Fila = MIN(fila)
            FROM @Autores
            WHERE fila > @Fila;
        END;

        INSERT INTO dbo.AUTOR_LIBRO (libro_id, autor_id)
        SELECT @LibroId, autor_id
        FROM @Final
        ORDER BY fila;

        -- Va última: trg_PUBLICACION_Vendedor rechaza un libro sin autor (50272), y
        -- dentro de esta transacción ya ve las filas de AUTOR_LIBRO aunque no estén
        -- confirmadas. También rechaza a quien no es vendedor (50271) y a un vendedor
        -- dado de baja (50273), que las validaciones ya descartaron. Con stock 0,
        -- trg_PUBLICACION_Agotada la deja no disponible.
        IF @Publicar = 1
        BEGIN
            INSERT INTO dbo.PUBLICACION
            (
                usuario_id,
                libro_id,
                condicion_id,
                stock,
                precio
            )
            VALUES
            (
                @UsuarioId,
                @LibroId,
                @CondicionId,
                @Stock,
                @Precio
            );

            SET @PublicacionId = CAST(SCOPE_IDENTITY() AS INT);
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;

    SELECT
        L.libro_id,
        L.isbn,
        (SELECT COUNT(*) FROM @Final) AS autores,
        (SELECT COUNT(*) FROM @Autores WHERE autor_id IS NULL) AS autores_nuevos,
        @PublicacionId AS publicacion_id,
        CASE
            WHEN @PublicacionId IS NULL THEN 'Libro registrado correctamente'
            ELSE 'Libro registrado y publicado correctamente'
        END AS mensaje
    FROM dbo.LIBRO AS L
    WHERE L.libro_id = @LibroId;
END;
GO
