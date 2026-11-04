USE [sistema-venta-libros];
GO

-- Demostración de dbo.trg_PUBLICACION_AuditoriaStock (script.sql). Requiere la base
-- instalada completa, como indica el README, más estructura_auditoria/script.sql y
-- este script.sql.
-- PUBLICACION tiene un índice filtrado: sin QUOTED_IDENTIFIER, escribir en ella falla
-- con el error 1934 desde sqlcmd.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- No corre dentro de una transacción: los procedimientos de la venta confirman las
-- suyas. Crea sus propios usuarios, publicaciones, pedidos y pagos, y
-- #LimpiarDemoStock los borra antes y después, junto con sus eventos de auditoría,
-- así que se puede ejecutar varias veces sin dejar datos en la base. Lo único que no
-- se revierte son los contadores IDENTITY.
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

IF OBJECT_ID(N'tempdb..#LimpiarDemoStock', N'P') IS NOT NULL
    DROP PROCEDURE #LimpiarDemoStock;
GO

IF OBJECT_ID(N'tempdb..#CrearPublicacionStock', N'P') IS NOT NULL
    DROP PROCEDURE #CrearPublicacionStock;
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
CREATE PROCEDURE #LimpiarDemoStock
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Usuarios TABLE (usuario_id INT PRIMARY KEY);

    BEGIN TRANSACTION;

    INSERT INTO @Usuarios (usuario_id)
    SELECT usuario_id
    FROM dbo.USUARIO
    WHERE email LIKE 'demo.auditoria.auditar[_]stock[_]publicacion.%@example.com';

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
END;
GO

-- Crea una publicación con un libro que tenga autor (trg_PUBLICACION_Vendedor) y que
-- el vendedor todavía no publicó, porque uq_publicacion_usuario_libro_condicion no
-- admite repetirlo.
-- La anota enseguida en #FilasDemoAuditoria: el caso 6 la borra, y la limpieza ya no
-- la encontraría entre las publicaciones de los usuarios de demostración.
CREATE PROCEDURE #CrearPublicacionStock
    @Vendedor INT,
    @Stock INT,
    @Precio DECIMAL(18, 2),
    @Disponible BIT,
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
        precio,
        disponible
    )
    SELECT TOP (1)
        @Vendedor,
        L.libro_id,
        C.condicion_id,
        @Stock,
        @Precio,
        @Disponible
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

    INSERT INTO #FilasDemoAuditoria (tabla, registro_id)
    VALUES ('PUBLICACION', @PublicacionId);
END;
GO

-- Resume en un texto comparable los eventos de una fila posteriores a @Desde, en
-- orden. Solo toma las columnas de @Columnas (separadas por comas), así la
-- comprobación no cambia si hay otros triggers de auditoría instalados. Ejemplo:
-- U stock: 5 a 8; usuario 503; origen -
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
-- Las comprobaciones de un UPDATE solo miran las columnas de este trigger (stock,
-- disponible y fecha_eliminacion): el precio es de trg_PUBLICACION_AuditoriaPrecio.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

EXEC #LimpiarDemoStock;

DECLARE @Resultados TABLE
(
    orden INT IDENTITY(1,1) PRIMARY KEY,
    caso VARCHAR(70) NOT NULL,
    esperado VARCHAR(400) NOT NULL,
    obtenido VARCHAR(400) NULL,
    resultado AS CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END
);

DECLARE @Columnas VARCHAR(400) = 'stock,disponible,fecha_eliminacion';
DECLARE @Todas VARCHAR(400) = 'stock,disponible,fecha_eliminacion,usuario_id,libro_id,condicion,precio,fecha_creacion';
DECLARE @Administrador INT;
DECLARE @VendedorA INT;
DECLARE @VendedorB INT;
DECLARE @Cliente INT;
DECLARE @Direccion INT;
DECLARE @Tarjeta INT;
DECLARE @Carrito dbo.DetalleVentaType;
DECLARE @PubRepone INT;
DECLARE @PubAgota INT;
DECLARE @PubBorrar INT;
DECLARE @PubVigente INT;
DECLARE @PubPausada INT;
DECLARE @Pedido INT;
DECLARE @Pago INT;
DECLARE @Desde INT;
DECLARE @Inicio DATETIME;
DECLARE @FechaBaja DATETIME;
DECLARE @LibroBorrado INT;
DECLARE @CreacionBorrada DATETIME;
DECLARE @IdentAntes NUMERIC(38, 0);
DECLARE @Resumen VARCHAR(1000);
DECLARE @Resumen2 VARCHAR(1000);
DECLARE @Control VARCHAR(100);
DECLARE @Error INT;
-- Suma @@TRANCOUNT después de cada EXEC y de cada sentencia que falla: tiene que
-- seguir en cero.
DECLARE @Abiertas INT = 0;

BEGIN TRY
    -- Datos propios: un administrador, dos vendedores y un cliente con dirección,
    -- cargados por un script sin usuario de sesión.
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
            ('Administrador', '99103101', 'demo.auditoria.auditar_stock_publicacion.1@example.com', 'Administrador'),
            ('Vendedor A', '99103102', 'demo.auditoria.auditar_stock_publicacion.2@example.com', 'Vendedor'),
            ('Vendedor B', '99103103', 'demo.auditoria.auditar_stock_publicacion.3@example.com', 'Vendedor'),
            ('Cliente', '99103104', 'demo.auditoria.auditar_stock_publicacion.4@example.com', 'Cliente')
    ) AS D (nombre, dni, email, rol)
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.nombre = D.rol;

    SELECT @Administrador = usuario_id FROM dbo.USUARIO WHERE dni = '99103101';
    SELECT @VendedorA = usuario_id FROM dbo.USUARIO WHERE dni = '99103102';
    SELECT @VendedorB = usuario_id FROM dbo.USUARIO WHERE dni = '99103103';
    SELECT @Cliente = usuario_id FROM dbo.USUARIO WHERE dni = '99103104';

    INSERT INTO dbo.DIRECCION
    (
        calle,
        altura,
        codigo_postal,
        usuario_id,
        ciudad_id
    )
    VALUES ('Calle Demo', 100, '3400', @Cliente, (SELECT MIN(ciudad_id) FROM dbo.CIUDAD));

    SET @Direccion = CAST(SCOPE_IDENTITY() AS INT);

    SELECT @Tarjeta = pago_metodo_id FROM dbo.PAGO_METODO WHERE nombre = 'Tarjeta de crédito';

    -- El vendedor A publica con stock 5, con stock 2 y una tercera que no se vende.
    -- El vendedor B tiene dos publicaciones vigentes, una de ellas pausada.
    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @VendedorA;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #CrearPublicacionStock @Vendedor = @VendedorA, @Stock = 5, @Precio = 10000.00, @Disponible = 1, @PublicacionId = @PubRepone OUTPUT;
    EXEC #CrearPublicacionStock @Vendedor = @VendedorA, @Stock = 2, @Precio = 7000.00, @Disponible = 1, @PublicacionId = @PubAgota OUTPUT;
    EXEC #CrearPublicacionStock @Vendedor = @VendedorA, @Stock = 3, @Precio = 9900.00, @Disponible = 1, @PublicacionId = @PubBorrar OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @VendedorB;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #CrearPublicacionStock @Vendedor = @VendedorB, @Stock = 4, @Precio = 5000.00, @Disponible = 1, @PublicacionId = @PubVigente OUTPUT;
    EXEC #CrearPublicacionStock @Vendedor = @VendedorB, @Stock = 4, @Precio = 6000.00, @Disponible = 0, @PublicacionId = @PubPausada OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    -- Caso 1: un ajuste manual queda con quién lo hizo, cuándo y sin origen
    PRINT 'Caso 1: el vendedor repone stock';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @VendedorA;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Inicio = GETDATE();

    UPDATE dbo.PUBLICACION
    SET stock = 8
    WHERE publicacion_id = @PubRepone;

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
      AND registro_id = @PubRepone
    ORDER BY
        auditoria_id,
        columna;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubRepone,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubRepone,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('1. Evento de la reposición', 'U stock: 5 a 8; usuario ' + CAST(@VendedorA AS VARCHAR(10)) + '; origen -', @Resumen),
        ('1. Login y fecha', '1 evento; login real; fecha del paso', @Control);

    -- Caso 2: pausar y reanudar son dos sentencias, y dejan dos eventos (RN12)
    PRINT 'Caso 2: el vendedor pausa y reanuda una publicación';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PUBLICACION
    SET disponible = 0
    WHERE publicacion_id = @PubRepone;

    UPDATE dbo.PUBLICACION
    SET disponible = 1
    WHERE publicacion_id = @PubRepone;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubRepone,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '2. Pausa y reanudación, en orden',
        'U disponible: 1 a 0; usuario ' + CAST(@VendedorA AS VARCHAR(10)) + '; origen -'
        + ' / U disponible: 0 a 1; usuario ' + CAST(@VendedorA AS VARCHAR(10)) + '; origen -',
        @Resumen
    );

    -- Caso 3: la venta descuenta el stock en trg_PEDIDO_DescontarStock, y el stock en
    -- cero dispara trg_PUBLICACION_Agotada, que la oculta: dos sentencias, dos
    -- eventos, cada uno con su origen (RN14). La pasarela no declara usuario. El
    -- orden de los dos eventos depende del orden de los triggers, que no está
    -- fijado: se comprueba cada columna por separado.
    PRINT 'Caso 3: venta que agota la publicación';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Cliente;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@PubAgota, 2);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @Cliente,
        @DireccionId = @Direccion,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Inicio = GETDATE();
    SET @Error = NULL;

    BEGIN TRY
        EXEC dbo.usp_RegistrarVenta
            @PagoId = @Pago,
            @Resultado = 'Aprobado';
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubAgota,
        @Columnas = 'stock',
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubAgota,
        @Columnas = 'disponible',
        @Desde = @Desde,
        @Resumen = @Resumen2 OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubAgota,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('3. Error de la venta', 'sin error', ISNULL(CAST(@Error AS VARCHAR(10)), 'sin error')),
        ('3. Evento del stock', 'U stock: 2 a 0; usuario -; origen trg_PEDIDO_DescontarStock', @Resumen),
        ('3. Evento de la disponibilidad', 'U disponible: 1 a 0; usuario -; origen trg_PUBLICACION_Agotada', @Resumen2),
        ('3. Login y fecha', '2 eventos; login real; fecha del paso', @Control);

    -- Caso 4: el cambio de precio es de trg_PUBLICACION_AuditoriaPrecio. El SET no
    -- menciona las columnas de este trigger, que sale enseguida.
    PRINT 'Caso 4: solo cambia el precio';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @VendedorA;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PUBLICACION
    SET precio = 11000.00
    WHERE publicacion_id = @PubRepone;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubRepone,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('4. Eventos de stock, disponible o baja', 'sin eventos', @Resumen);

    -- Caso 5: la baja del vendedor da de baja sus publicaciones vigentes en
    -- trg_USUARIO_Baja (RN12, RN28). La pausada ya tenía disponible en 0: solo
    -- cambia su fecha de baja. El usuario es quien hizo la baja.
    PRINT 'Caso 5: el administrador da de baja al vendedor B';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Administrador;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Inicio = GETDATE();
    SET @FechaBaja = GETDATE();

    UPDATE dbo.USUARIO
    SET fecha_eliminacion = @FechaBaja
    WHERE usuario_id = @VendedorB;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubVigente,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubPausada,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen2 OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubVigente,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '5. Publicación vigente',
        'U disponible: 1 a 0, fecha_eliminacion: NULL a ' + CONVERT(VARCHAR(23), @FechaBaja, 121)
        + '; usuario ' + CAST(@Administrador AS VARCHAR(10)) + '; origen trg_USUARIO_Baja',
        @Resumen
    ),
    (
        '5. Publicación pausada',
        'U fecha_eliminacion: NULL a ' + CONVERT(VARCHAR(23), @FechaBaja, 121)
        + '; usuario ' + CAST(@Administrador AS VARCHAR(10)) + '; origen trg_USUARIO_Baja',
        @Resumen2
    ),
    ('5. Login y fecha', '1 evento; login real; fecha del paso', @Control);

    -- Caso 6: el DELETE guarda la última versión de la fila, con todas sus columnas
    -- y sin valores nuevos. fecha_eliminacion valía NULL y no se registra.
    PRINT 'Caso 6: el vendedor borra una publicación sin renglones';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @VendedorA;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT
        @LibroBorrado = libro_id,
        @CreacionBorrada = fecha_creacion
    FROM dbo.PUBLICACION
    WHERE publicacion_id = @PubBorrar;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    DELETE FROM dbo.PUBLICACION
    WHERE publicacion_id = @PubBorrar;

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubBorrar,
        @Columnas = @Todas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '6. Evento del borrado',
        'D condicion: Nuevo a NULL, disponible: 1 a NULL'
        + ', fecha_creacion: ' + CONVERT(VARCHAR(23), @CreacionBorrada, 121) + ' a NULL'
        + ', libro_id: ' + CAST(@LibroBorrado AS VARCHAR(10)) + ' a NULL'
        + ', precio: 9900.00 a NULL, stock: 3 a NULL'
        + ', usuario_id: ' + CAST(@VendedorA AS VARCHAR(10)) + ' a NULL'
        + '; usuario ' + CAST(@VendedorA AS VARCHAR(10)) + '; origen -',
        @Resumen
    ),
    (
        '6. Valores nuevos del evento',
        '0',
        (
            SELECT CAST(COUNT(*) AS VARCHAR(10))
            FROM dbo.AUDITORIA AS A
            INNER JOIN dbo.AUDITORIA_DETALLE AS AD
                ON AD.auditoria_id = A.auditoria_id
            WHERE A.tabla = 'PUBLICACION'
              AND A.registro_id = @PubBorrar
              AND A.auditoria_id > @Desde
              AND AD.valor_nuevo IS NOT NULL
        )
    );

    -- Caso 7: trg_PUBLICACION_Historial rechaza la sentencia (RN28). Si la auditoría
    -- corrió antes, su evento se revierte con ella. El orden de los triggers no está
    -- fijado: la línea impresa muestra si se consumió un valor IDENTITY, es decir,
    -- si la auditoría llegó a correr.
    PRINT 'Caso 7: revertir la baja de una publicación';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Administrador;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @IdentAntes = IDENT_CURRENT('dbo.AUDITORIA');
    SET @Error = NULL;

    BEGIN TRY
        UPDATE dbo.PUBLICACION
        SET fecha_eliminacion = NULL
        WHERE publicacion_id = @PubVigente;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    PRINT 'Caso 7: IDENT_CURRENT de AUDITORIA antes ' + CAST(@IdentAntes AS VARCHAR(20))
        + ', después ' + CAST(IDENT_CURRENT('dbo.AUDITORIA') AS VARCHAR(20));

    EXEC #ResumenAuditoria
        @Tabla = 'PUBLICACION',
        @RegistroId = @PubVigente,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('7. Error', '50275', CAST(@Error AS VARCHAR(10))),
        ('7. Eventos', 'sin eventos', @Resumen),
        (
            '7. Fecha de baja sin cambios',
            CONVERT(VARCHAR(23), @FechaBaja, 121),
            (SELECT CONVERT(VARCHAR(23), fecha_eliminacion, 121) FROM dbo.PUBLICACION WHERE publicacion_id = @PubVigente)
        );

    -- Caso 8: ninguna sentencia deja una transacción abierta, tampoco las que fallaron
    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('8. Transacciones abiertas', '0', CAST(@Abiertas AS VARCHAR(10)));
END TRY
BEGIN CATCH
    -- Un error no previsto queda como FALLO: así el lote termina, se muestran los
    -- resultados y el lote siguiente limpia los datos.
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('Error no previsto', 'ninguno', LEFT(ERROR_MESSAGE(), 400));
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
-- eventos sí, porque AUDITORIA no tiene claves foráneas, y por eso se cuentan aparte.
EXEC #LimpiarDemoStock;
EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;

SELECT
    (
        SELECT COUNT(*)
        FROM dbo.USUARIO
        WHERE email LIKE 'demo.auditoria.auditar[_]stock[_]publicacion.%@example.com'
    )
    + (
        SELECT COUNT(*)
        FROM dbo.AUDITORIA AS A
        INNER JOIN #FilasDemoAuditoria AS F
            ON F.tabla = A.tabla
           AND F.registro_id = A.registro_id
    ) AS filas_demo;

DROP PROCEDURE #LimpiarDemoStock;
DROP PROCEDURE #CrearPublicacionStock;
DROP PROCEDURE #ResumenAuditoria;
DROP PROCEDURE #ControlAuditoria;
DROP TABLE #FilasDemoAuditoria;
GO
