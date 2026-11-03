USE [sistema-venta-libros];
GO

-- Demostración de dbo.trg_PUBLICACION_AuditoriaPrecio (script.sql). Requiere la base
-- instalada completa, como indica el README, más estructura_auditoria/script.sql y
-- este script.sql.
-- PUBLICACION tiene un índice filtrado: sin QUOTED_IDENTIFIER, escribir en ella falla
-- con el error 1934 desde sqlcmd.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- No corre dentro de una transacción, salvo el caso 7, que prueba un ROLLBACK. Crea
-- sus propios usuarios y publicaciones, y #LimpiarDemoPrecio los borra antes y
-- después, junto con sus eventos de auditoría y el usuario sin login del caso 6, así
-- que se puede ejecutar varias veces sin dejar datos en la base. Lo único que no se
-- revierte son los contadores IDENTITY.
-- #FilasDemoAuditoria dura toda la sesión: guarda las filas de la demostración para
-- que filas_demo cuente al final los eventos que hubieran quedado.
IF OBJECT_ID(N'tempdb..#FilasDemoAuditoria', N'U') IS NOT NULL
    DROP TABLE #FilasDemoAuditoria;
GO

CREATE TABLE #FilasDemoAuditoria
(
    tabla VARCHAR(128) NOT NULL,
    registro_id INT NOT NULL,
    PRIMARY KEY (tabla, registro_id)
);
GO

IF OBJECT_ID(N'tempdb..#LimpiarDemoPrecio', N'P') IS NOT NULL
    DROP PROCEDURE #LimpiarDemoPrecio;
GO

IF OBJECT_ID(N'tempdb..#CrearPublicacionPrecio', N'P') IS NOT NULL
    DROP PROCEDURE #CrearPublicacionPrecio;
GO

IF OBJECT_ID(N'tempdb..#ResumenAuditoria', N'P') IS NOT NULL
    DROP PROCEDURE #ResumenAuditoria;
GO

IF OBJECT_ID(N'tempdb..#ControlAuditoria', N'P') IS NOT NULL
    DROP PROCEDURE #ControlAuditoria;
GO

-- Borra las filas de la demostración y después sus eventos de auditoría.
-- Recoge las filas de las cuatro tablas auditadas (USUARIO, PUBLICACION, PEDIDO y
-- PAGO), aunque su trigger todavía no exista: así también se borran los eventos que
-- generen los triggers que se instalen después, incluidos los del propio DELETE.
-- Pagos y renglones no se borran en la operación normal, así que sus triggers se
-- deshabilitan solo para esta limpieza. DISABLE TRIGGER es transaccional: si algo
-- falla, XACT_ABORT revierte todo y los triggers vuelven a quedar habilitados.
CREATE PROCEDURE #LimpiarDemoPrecio
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Usuarios TABLE (usuario_id INT PRIMARY KEY);

    BEGIN TRANSACTION;

    INSERT INTO @Usuarios (usuario_id)
    SELECT usuario_id
    FROM dbo.USUARIO
    WHERE email LIKE 'demo.auditoria.auditar[_]precio[_]publicacion.%@example.com';

    INSERT INTO #FilasDemoAuditoria (tabla, registro_id)
    SELECT F.tabla, F.registro_id
    FROM
    (
        SELECT 'USUARIO', U.usuario_id
        FROM @Usuarios AS U

        UNION ALL

        SELECT 'PUBLICACION', PUB.publicacion_id
        FROM dbo.PUBLICACION AS PUB
        INNER JOIN @Usuarios AS U
            ON U.usuario_id = PUB.usuario_id

        UNION ALL

        SELECT 'PEDIDO', P.pedido_id
        FROM dbo.PEDIDO AS P
        INNER JOIN @Usuarios AS U
            ON U.usuario_id = P.usuario_id

        UNION ALL

        SELECT 'PAGO', PG.pago_id
        FROM dbo.PAGO AS PG
        INNER JOIN dbo.PEDIDO AS P
            ON P.pedido_id = PG.pedido_id
        INNER JOIN @Usuarios AS U
            ON U.usuario_id = P.usuario_id
    ) AS F (tabla, registro_id)
    WHERE NOT EXISTS (
        SELECT 1
        FROM #FilasDemoAuditoria AS X
        WHERE X.tabla = F.tabla
          AND X.registro_id = F.registro_id
    );

    DISABLE TRIGGER dbo.trg_PAGO_SinBorrado ON dbo.PAGO;
    DISABLE TRIGGER dbo.trg_DETALLE_Congelado ON dbo.PEDIDO_DETALLE;

    DELETE PG
    FROM dbo.PAGO AS PG
    INNER JOIN dbo.PEDIDO AS P
        ON P.pedido_id = PG.pedido_id
    WHERE P.usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE PD
    FROM dbo.PEDIDO_DETALLE AS PD
    INNER JOIN dbo.PEDIDO AS P
        ON P.pedido_id = PD.pedido_id
    WHERE P.usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE FROM dbo.PEDIDO
    WHERE usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE FROM dbo.PUBLICACION
    WHERE usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE FROM dbo.DIRECCION
    WHERE usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE FROM dbo.USUARIO
    WHERE usuario_id IN (SELECT usuario_id FROM @Usuarios);

    ENABLE TRIGGER dbo.trg_DETALLE_Congelado ON dbo.PEDIDO_DETALLE;
    ENABLE TRIGGER dbo.trg_PAGO_SinBorrado ON dbo.PAGO;

    DELETE AD
    FROM dbo.AUDITORIA_DETALLE AS AD
    INNER JOIN dbo.AUDITORIA AS A
        ON A.auditoria_id = AD.auditoria_id
    INNER JOIN #FilasDemoAuditoria AS F
        ON F.tabla = A.tabla
       AND F.registro_id = A.registro_id;

    DELETE A
    FROM dbo.AUDITORIA AS A
    INNER JOIN #FilasDemoAuditoria AS F
        ON F.tabla = A.tabla
       AND F.registro_id = A.registro_id;

    COMMIT TRANSACTION;

    -- El usuario de base de datos del caso 6, si quedó por un error.
    IF USER_ID(N'demo_auditoria_sin_login') IS NOT NULL
        DROP USER demo_auditoria_sin_login;
END;
GO

-- Crea una publicación con un libro que tenga autor (trg_PUBLICACION_Vendedor) y que
-- el vendedor todavía no publicó, porque uq_publicacion_usuario_libro_condicion no
-- admite repetirlo.
CREATE PROCEDURE #CrearPublicacionPrecio
    @Vendedor INT,
    @Precio DECIMAL(18, 2),
    @PublicacionId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.PUBLICACION
    (
        usuario_id,
        libro_id,
        condicion_id,
        stock,
        precio
    )
    SELECT TOP (1)
        @Vendedor,
        L.libro_id,
        C.condicion_id,
        5,
        @Precio
    FROM dbo.LIBRO AS L
    INNER JOIN dbo.CONDICION AS C
        ON C.nombre = 'Nuevo'
    WHERE EXISTS (
              SELECT 1
              FROM dbo.AUTOR_LIBRO AS AL
              WHERE AL.libro_id = L.libro_id
          )
      AND NOT EXISTS (
              SELECT 1
              FROM dbo.PUBLICACION AS PUB
              WHERE PUB.usuario_id = @Vendedor
                AND PUB.libro_id = L.libro_id
          )
    ORDER BY L.libro_id;

    SET @PublicacionId = CAST(SCOPE_IDENTITY() AS INT);
END;
GO

-- Resume en un texto comparable los eventos de una fila posteriores a @Desde, en
-- orden. Solo toma las columnas de @Columnas (separadas por comas), así la
-- comprobación no cambia si hay otros triggers de auditoría instalados. Ejemplo:
-- U precio: 15000.00 a 16500.00; usuario 503; origen -
-- Los eventos se separan con " / ", y un valor NULL se muestra como NULL.
CREATE PROCEDURE #ResumenAuditoria
    @Tabla VARCHAR(128),
    @RegistroId INT,
    @Columnas VARCHAR(400),
    @Desde INT,
    @Resumen VARCHAR(1000) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Resumen = STUFF((
        SELECT
            ' / ' + A.operacion + ' '
            + STUFF((
                  SELECT
                      ', ' + AD.columna + ': '
                      + ISNULL(AD.valor_anterior, 'NULL') + ' a '
                      + ISNULL(AD.valor_nuevo, 'NULL')
                  FROM dbo.AUDITORIA_DETALLE AS AD
                  WHERE AD.auditoria_id = A.auditoria_id
                    AND CHARINDEX(',' + AD.columna + ',', ',' + @Columnas + ',') > 0
                  ORDER BY AD.columna
                  FOR XML PATH(''), TYPE
              ).value('.', 'VARCHAR(MAX)'), 1, 2, '')
            + '; usuario ' + ISNULL(CAST(A.usuario_id AS VARCHAR(10)), '-')
            + '; origen ' + ISNULL(A.origen, '-')
        FROM dbo.AUDITORIA AS A
        WHERE A.tabla = @Tabla
          AND A.registro_id = @RegistroId
          AND A.auditoria_id > @Desde
          AND EXISTS (
                  SELECT 1
                  FROM dbo.AUDITORIA_DETALLE AS AD
                  WHERE AD.auditoria_id = A.auditoria_id
                    AND CHARINDEX(',' + AD.columna + ',', ',' + @Columnas + ',') > 0
              )
        ORDER BY A.auditoria_id
        FOR XML PATH(''), TYPE
    ).value('.', 'VARCHAR(MAX)'), 1, 3, '');

    SET @Resumen = ISNULL(@Resumen, 'sin eventos');
END;
GO

-- Comprueba quién y cuándo en los mismos eventos que #ResumenAuditoria: si todos
-- tienen el login real de la sesión (ORIGINAL_LOGIN()) y una fecha entre @Inicio y
-- el momento de la comprobación.
CREATE PROCEDURE #ControlAuditoria
    @Tabla VARCHAR(128),
    @RegistroId INT,
    @Columnas VARCHAR(400),
    @Desde INT,
    @Inicio DATETIME,
    @Control VARCHAR(100) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Fin DATETIME = GETDATE();

    SELECT @Control =
        CAST(COUNT(*) AS VARCHAR(10))
        + CASE WHEN COUNT(*) = 1 THEN ' evento' ELSE ' eventos' END
        + '; login '
        + CASE WHEN COUNT(*) = SUM(CASE WHEN A.login_bd = ORIGINAL_LOGIN() THEN 1 ELSE 0 END) THEN 'real' ELSE 'distinto' END
        + '; fecha '
        + CASE WHEN COUNT(*) = SUM(CASE WHEN A.fecha BETWEEN @Inicio AND @Fin THEN 1 ELSE 0 END) THEN 'del paso' ELSE 'fuera del paso' END
    FROM dbo.AUDITORIA AS A
    WHERE A.tabla = @Tabla
      AND A.registro_id = @RegistroId
      AND A.auditoria_id > @Desde
      AND EXISTS (
              SELECT 1
              FROM dbo.AUDITORIA_DETALLE AS AD
              WHERE AD.auditoria_id = A.auditoria_id
                AND CHARINDEX(',' + AD.columna + ',', ',' + @Columnas + ',') > 0
          );
END;
GO

-- Con XACT_ABORT en OFF, los errores provocados no cortan el lote. Antes de cada
-- paso se declara quién actúa con dbo.usp_EstablecerUsuarioSesion y se guarda el
-- último evento (@Desde) y la hora (@Inicio): el paso se comprueba con los eventos
-- posteriores.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

EXEC #LimpiarDemoPrecio;

DECLARE @Resultados TABLE
(
    orden INT IDENTITY(1,1) PRIMARY KEY,
    caso VARCHAR(70) NOT NULL,
    esperado VARCHAR(300) NOT NULL,
    obtenido VARCHAR(300) NULL,
    resultado AS CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END
);

DECLARE @Administrador INT;
DECLARE @Vendedor INT;
DECLARE @Cliente INT;
DECLARE @Pub1 INT;
DECLARE @Pub2 INT;
DECLARE @Pub3 INT;
DECLARE @Desde INT;
DECLARE @DesdeHistorial INT;
DECLARE @Inicio DATETIME;
DECLARE @IdentAntes NUMERIC(38, 0);
DECLARE @Resumen VARCHAR(1000);
DECLARE @Resumen2 VARCHAR(1000);
DECLARE @Resumen3 VARCHAR(1000);
DECLARE @Control VARCHAR(100);
DECLARE @Permisos VARCHAR(200);
DECLARE @LoginSuplantado NVARCHAR(128);
DECLARE @Estado VARCHAR(100);
DECLARE @Error INT;
DECLARE @Mensaje NVARCHAR(4000);
-- Suma @@TRANCOUNT después de cada EXEC y de cada sentencia que falla: tiene que
-- seguir en cero.
DECLARE @Abiertas INT = 0;

BEGIN TRY
    -- Datos propios: un administrador, un vendedor y un cliente, cargados por un
    -- script sin usuario de sesión. El vendedor crea tres publicaciones.
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
            ('Administrador', '99102101', 'demo.auditoria.auditar_precio_publicacion.1@example.com', 'Administrador'),
            ('Vendedor', '99102102', 'demo.auditoria.auditar_precio_publicacion.2@example.com', 'Vendedor'),
            ('Cliente', '99102103', 'demo.auditoria.auditar_precio_publicacion.3@example.com', 'Cliente')
    ) AS D (nombre, dni, email, rol)
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.nombre = D.rol;

    SELECT @Administrador = usuario_id FROM dbo.USUARIO WHERE dni = '99102101';
    SELECT @Vendedor = usuario_id FROM dbo.USUARIO WHERE dni = '99102102';
    SELECT @Cliente = usuario_id FROM dbo.USUARIO WHERE dni = '99102103';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Vendedor;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #CrearPublicacionPrecio @Vendedor = @Vendedor, @Precio = 15000.00, @PublicacionId = @Pub1 OUTPUT;
    EXEC #CrearPublicacionPrecio @Vendedor = @Vendedor, @Precio = 8000.00, @PublicacionId = @Pub2 OUTPUT;
    EXEC #CrearPublicacionPrecio @Vendedor = @Vendedor, @Precio = 12500.00, @PublicacionId = @Pub3 OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    -- Caso 1: un evento con el valor anterior, el nuevo, quién y cuándo
    PRINT 'Caso 1: el vendedor cambia un precio';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @DesdeHistorial = @Desde;
    SET @Inicio = GETDATE();

    UPDATE dbo.PUBLICACION
    SET precio = 16500.00
    WHERE publicacion_id = @Pub1;

    -- El historial de la publicación, como lo consultaría un administrador.
    SELECT
        auditoria_id,
        fecha,
        tabla,
        operacion,
        registro_id,
        columna,
        valor_anterior,
        valor_nuevo,
        login_bd,
        usuario_id,
        usuario_email,
        origen
    FROM dbo.vw_Auditoria
    WHERE tabla = 'PUBLICACION'
      AND registro_id = @Pub1
    ORDER BY
        auditoria_id,
        columna;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('1. Evento del cambio', 'U precio: 15000.00 a 16500.00; usuario ' + CAST(@Vendedor AS VARCHAR(10)) + '; origen -', @Resumen),
        ('1. Login y fecha', '1 evento; login real; fecha del paso', @Control);

    -- Caso 2: el historial encadena los valores y registra quién hizo cada cambio
    PRINT 'Caso 2: el administrador cambia el mismo precio';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Administrador;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    UPDATE dbo.PUBLICACION
    SET precio = 16000.00
    WHERE publicacion_id = @Pub1;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @DesdeHistorial,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '2. Historial de los casos 1 y 2, en orden',
        'U precio: 15000.00 a 16500.00; usuario ' + CAST(@Vendedor AS VARCHAR(10)) + '; origen -'
        + ' / U precio: 16500.00 a 16000.00; usuario ' + CAST(@Administrador AS VARCHAR(10)) + '; origen -',
        @Resumen
    );

    -- Caso 3: sin el precio en el SET, el trigger sale enseguida. Con precio = precio,
    -- UPDATE(precio) es verdadero y el filtro EXCEPT descarta la fila.
    PRINT 'Caso 3: UPDATE que no cambia el precio';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Vendedor;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PUBLICACION
    SET stock = stock + 1
    WHERE publicacion_id = @Pub1;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('3. Solo cambia el stock', 'sin eventos', @Resumen);

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PUBLICACION
    SET precio = precio
    WHERE publicacion_id = @Pub1;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('3. precio = precio', 'sin eventos', @Resumen);

    -- Caso 4: una sentencia que cambia varias filas deja un evento por fila
    PRINT 'Caso 4: el vendedor sube un 10 % todas sus publicaciones';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PUBLICACION
    SET precio = ROUND(precio * 1.10, 2)
    WHERE usuario_id = @Vendedor;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub2,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen2 OUTPUT;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub3,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen3 OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '4. Eventos de precio de la sentencia',
        '3',
        (
            SELECT CAST(COUNT(*) AS VARCHAR(10))
            FROM dbo.AUDITORIA AS A
            WHERE A.tabla = 'PUBLICACION'
              AND A.auditoria_id > @Desde
              AND EXISTS (
                      SELECT 1
                      FROM dbo.AUDITORIA_DETALLE AS AD
                      WHERE AD.auditoria_id = A.auditoria_id
                        AND AD.columna = 'precio'
                  )
        )
    ),
    ('4. Publicación 1', 'U precio: 16000.00 a 17600.00; usuario ' + CAST(@Vendedor AS VARCHAR(10)) + '; origen -', @Resumen),
    ('4. Publicación 2', 'U precio: 8000.00 a 8800.00; usuario ' + CAST(@Vendedor AS VARCHAR(10)) + '; origen -', @Resumen2),
    ('4. Publicación 3', 'U precio: 12500.00 a 13750.00; usuario ' + CAST(@Vendedor AS VARCHAR(10)) + '; origen -', @Resumen3);

    -- Caso 5: un script de mantenimiento no declara usuario. El login identifica igual
    -- quién se conectó.
    PRINT 'Caso 5: cambio sin usuario de sesión';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Inicio = GETDATE();

    UPDATE dbo.PUBLICACION
    SET precio = 9000.00
    WHERE publicacion_id = @Pub2;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub2,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub2,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('5. Evento sin usuario del sistema', 'U precio: 8800.00 a 9000.00; usuario -; origen -', @Resumen),
        ('5. Login y fecha', '1 evento; login real; fecha del paso', @Control);

    -- Caso 6: bajo EXECUTE AS, SUSER_SNAME() devuelve el usuario suplantado, y
    -- ORIGINAL_LOGIN() sigue devolviendo el login que se conectó. El usuario solo puede
    -- leer y modificar PUBLICACION: el trigger y dbo.usp_RegistrarAuditoria son de dbo,
    -- igual que AUDITORIA, y el encadenamiento de propiedad evita revisar sus permisos.
    PRINT 'Caso 6: cambio bajo EXECUTE AS USER de un usuario sin login';

    CREATE USER demo_auditoria_sin_login WITHOUT LOGIN;
    GRANT SELECT, UPDATE ON dbo.PUBLICACION TO demo_auditoria_sin_login;

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Vendedor;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Inicio = GETDATE();
    SET @Error = NULL;

    EXECUTE AS USER = 'demo_auditoria_sin_login';

    -- REVERT queda fuera del TRY: corre aunque el UPDATE falle.
    BEGIN TRY
        SET @Permisos =
            'UPDATE en PUBLICACION ' + CAST(HAS_PERMS_BY_NAME('dbo.PUBLICACION', 'OBJECT', 'UPDATE') AS VARCHAR(1))
            + '; SELECT en AUDITORIA ' + CAST(HAS_PERMS_BY_NAME('dbo.AUDITORIA', 'OBJECT', 'SELECT') AS VARCHAR(1))
            + '; INSERT en AUDITORIA ' + CAST(HAS_PERMS_BY_NAME('dbo.AUDITORIA', 'OBJECT', 'INSERT') AS VARCHAR(1))
            + '; EXECUTE en usp_RegistrarAuditoria ' + CAST(HAS_PERMS_BY_NAME('dbo.usp_RegistrarAuditoria', 'OBJECT', 'EXECUTE') AS VARCHAR(1));
        SET @LoginSuplantado = SUSER_SNAME();

        UPDATE dbo.PUBLICACION
        SET precio = 13000.00
        WHERE publicacion_id = @Pub3;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;

    REVERT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    DROP USER demo_auditoria_sin_login;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub3,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub3,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '6. Permisos del usuario sin login',
        'UPDATE en PUBLICACION 1; SELECT en AUDITORIA 0; INSERT en AUDITORIA 0; EXECUTE en usp_RegistrarAuditoria 0',
        @Permisos
    ),
    ('6. Error del cambio de precio', 'sin error', ISNULL(CAST(@Error AS VARCHAR(10)), 'sin error')),
    (
        '6. SUSER_SNAME() bajo EXECUTE AS',
        'distinto del login real',
        CASE WHEN @LoginSuplantado = ORIGINAL_LOGIN() THEN 'igual al login real' ELSE 'distinto del login real' END
    ),
    ('6. Evento', 'U precio: 13750.00 a 13000.00; usuario ' + CAST(@Vendedor AS VARCHAR(10)) + '; origen -', @Resumen),
    ('6. Login y fecha', '1 evento; login real; fecha del paso', @Control);

    -- Caso 7: el evento se escribe dentro de la transacción de la sentencia, y el
    -- ROLLBACK lo deshace junto con el cambio. El valor IDENTITY que usó no vuelve.
    PRINT 'Caso 7: cambio de precio revertido';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @IdentAntes = IDENT_CURRENT('dbo.AUDITORIA');

    BEGIN TRANSACTION;

    UPDATE dbo.PUBLICACION
    SET precio = 18000.00
    WHERE publicacion_id = @Pub1;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    ROLLBACK TRANSACTION;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen2 OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('7. Dentro de la transacción', 'U precio: 17600.00 a 18000.00; usuario ' + CAST(@Vendedor AS VARCHAR(10)) + '; origen -', @Resumen),
        ('7. Después del ROLLBACK', 'sin eventos', @Resumen2),
        ('7. Precio después del ROLLBACK', '17600.00', (SELECT CONVERT(VARCHAR(20), precio) FROM dbo.PUBLICACION WHERE publicacion_id = @Pub1)),
        (
            '7. IDENTITY de AUDITORIA',
            'avanzó sin filas nuevas',
            CASE WHEN IDENT_CURRENT('dbo.AUDITORIA') > @IdentAntes THEN 'avanzó' ELSE 'no avanzó' END
            + CASE WHEN EXISTS (SELECT 1 FROM dbo.AUDITORIA WHERE auditoria_id > @Desde) THEN ' con filas nuevas' ELSE ' sin filas nuevas' END
        );

    -- Caso 8: el CHECK rechaza la sentencia antes de que corran los triggers
    PRINT 'Caso 8: precio 0';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Error = NULL;
    SET @Mensaje = NULL;

    BEGIN TRY
        UPDATE dbo.PUBLICACION
        SET precio = 0
        WHERE publicacion_id = @Pub1;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
        SET @Mensaje = ERROR_MESSAGE();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '8. Error',
        '547 chk_publicacion_precio',
        CAST(@Error AS VARCHAR(10))
        + CASE WHEN CHARINDEX('chk_publicacion_precio', @Mensaje) > 0 THEN ' chk_publicacion_precio' ELSE '' END
    ),
    ('8. Eventos', 'sin eventos', @Resumen);

    -- Caso 9: trg_PUBLICACION_Vendedor rechaza la sentencia. Si el trigger de
    -- auditoría corrió antes, su evento se revierte con ella. El orden de los
    -- triggers no está fijado: la línea impresa muestra si se consumió un valor
    -- IDENTITY, es decir, si la auditoría llegó a correr.
    PRINT 'Caso 9: cambio de precio y de vendedor a un cliente';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @IdentAntes = IDENT_CURRENT('dbo.AUDITORIA');
    SET @Error = NULL;

    BEGIN TRY
        UPDATE dbo.PUBLICACION
        SET precio = 20000.00,
            usuario_id = @Cliente
        WHERE publicacion_id = @Pub1;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    PRINT 'Caso 9: IDENT_CURRENT de AUDITORIA antes ' + CAST(@IdentAntes AS VARCHAR(20))
        + ', después ' + CAST(IDENT_CURRENT('dbo.AUDITORIA') AS VARCHAR(20));

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @Pub1,
        @Columnas = 'precio',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    SELECT @Estado = CONVERT(VARCHAR(20), precio) + '; usuario ' + CAST(usuario_id AS VARCHAR(10))
    FROM dbo.PUBLICACION
    WHERE publicacion_id = @Pub1;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('9. Error', '50271', CAST(@Error AS VARCHAR(10))),
        ('9. Eventos', 'sin eventos', @Resumen),
        ('9. Precio y vendedor sin cambios', '17600.00; usuario ' + CAST(@Vendedor AS VARCHAR(10)), @Estado);

    -- Caso 10: ninguna sentencia deja una transacción abierta, tampoco las que fallaron
    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. Transacciones abiertas', '0', CAST(@Abiertas AS VARCHAR(10)));
END TRY
BEGIN CATCH
    -- Un error no previsto queda como FALLO: así el lote termina, se muestran los
    -- resultados y el lote siguiente limpia los datos.
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('Error no previsto', 'ninguno', LEFT(ERROR_MESSAGE(), 300));
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

-- Lote propio: corre aunque la demostración falle. Sin los usuarios no puede quedar
-- ninguna otra fila de demostración, porque las claves foráneas lo impedirían; los
-- eventos sí, porque AUDITORIA no tiene claves foráneas, y por eso se cuentan aparte,
-- igual que el usuario sin login.
EXEC #LimpiarDemoPrecio;
EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;

SELECT
    (
        SELECT COUNT(*)
        FROM dbo.USUARIO
        WHERE email LIKE 'demo.auditoria.auditar[_]precio[_]publicacion.%@example.com'
    )
    + (
        SELECT COUNT(*)
        FROM dbo.AUDITORIA AS A
        INNER JOIN #FilasDemoAuditoria AS F
            ON F.tabla = A.tabla
           AND F.registro_id = A.registro_id
    )
    + CASE WHEN USER_ID(N'demo_auditoria_sin_login') IS NULL THEN 0 ELSE 1 END AS filas_demo;

DROP PROCEDURE #LimpiarDemoPrecio;
DROP PROCEDURE #CrearPublicacionPrecio;
DROP PROCEDURE #ResumenAuditoria;
DROP PROCEDURE #ControlAuditoria;
DROP TABLE #FilasDemoAuditoria;
GO
