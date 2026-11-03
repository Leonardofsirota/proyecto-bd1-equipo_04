USE [sistema-venta-libros];
GO

-- Demostración de dbo.trg_USUARIO_Auditoria (script.sql). Requiere la base instalada
-- completa, como indica el README, más estructura_auditoria/script.sql y este
-- script.sql.
-- PUBLICACION tiene un índice filtrado: sin QUOTED_IDENTIFIER, escribir en ella falla
-- con el error 1934 desde sqlcmd.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- No corre dentro de una transacción: solo el caso 8 abre una, para revertirla. Crea
-- sus propios usuarios, publicación y pedido, y #LimpiarDemoUsuarios los borra antes
-- y después, junto con sus eventos de auditoría, así que se puede ejecutar varias
-- veces sin dejar datos en la base. Lo único que no se revierte son los contadores
-- IDENTITY.
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

IF OBJECT_ID(N'tempdb..#LimpiarDemoUsuarios', N'P') IS NOT NULL
    DROP PROCEDURE #LimpiarDemoUsuarios;
GO

IF OBJECT_ID(N'tempdb..#CrearPublicacionUsuarios', N'P') IS NOT NULL
    DROP PROCEDURE #CrearPublicacionUsuarios;
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
CREATE PROCEDURE #LimpiarDemoUsuarios
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Usuarios TABLE (usuario_id INT PRIMARY KEY);

    BEGIN TRANSACTION;

    INSERT INTO @Usuarios (usuario_id)
    SELECT usuario_id
    FROM dbo.USUARIO
    WHERE email LIKE 'demo.auditoria.auditar[_]usuarios.%@example.com';

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
CREATE PROCEDURE #CrearPublicacionUsuarios
    @Vendedor INT,
    @Stock INT,
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
        @Stock,
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
-- U rol: Cliente a Vendedor; usuario 501; origen -
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

EXEC #LimpiarDemoUsuarios;

DECLARE @Resultados TABLE
(
    orden INT IDENTITY(1,1) PRIMARY KEY,
    caso VARCHAR(70) NOT NULL,
    esperado VARCHAR(400) NOT NULL,
    obtenido VARCHAR(400) NULL,
    resultado AS CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END
);

DECLARE @Columnas VARCHAR(400) = 'apellido,dni,email,fecha_eliminacion,fecha_nacimiento,nombre,password_hash,rol,telefono';
-- Contraseñas de ejemplo del caso 3. Ninguna de las dos puede aparecer en la
-- auditoría.
DECLARE @HashAnterior VARCHAR(255) = 'hash-demo-auditoria-anterior';
DECLARE @HashNuevo VARCHAR(255) = 'hash-demo-auditoria-nuevo';
DECLARE @Administrador INT;
DECLARE @Vendedor INT;
DECLARE @ConPedido INT;
DECLARE @SinRelaciones INT;
DECLARE @Nuevo INT;
DECLARE @RolVendedor INT;
DECLARE @Direccion INT;
DECLARE @Carrito dbo.DetalleVentaType;
DECLARE @Pub INT;
DECLARE @Pedido INT;
DECLARE @Baja DATETIME;
DECLARE @Desde INT;
DECLARE @Inicio DATETIME;
DECLARE @IdentAntes NUMERIC(38, 0);
DECLARE @Resumen VARCHAR(1000);
DECLARE @Resumen2 VARCHAR(1000);
DECLARE @Control VARCHAR(100);
DECLARE @Error INT;
-- Suma @@TRANCOUNT después de cada EXEC y de cada sentencia que falla: tiene que
-- seguir en cero.
DECLARE @Abiertas INT = 0;

BEGIN TRY
    -- Datos propios: un administrador, un vendedor y dos clientes, cargados por un
    -- script sin usuario de sesión. Cada uno tiene un teléfono distinto. El tercer
    -- cliente se registra en el caso 1.
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
        '3794' + RIGHT(D.dni, 6),
        '1990-01-01',
        'hash-demo',
        UR.usuario_rol_id
    FROM
    (
        VALUES
            ('Administrador', '99106101', 'demo.auditoria.auditar_usuarios.1@example.com', 'Administrador'),
            ('Vendedor', '99106102', 'demo.auditoria.auditar_usuarios.2@example.com', 'Vendedor'),
            ('Comprador', '99106103', 'demo.auditoria.auditar_usuarios.3@example.com', 'Cliente'),
            ('Visitante', '99106104', 'demo.auditoria.auditar_usuarios.4@example.com', 'Cliente')
    ) AS D (nombre, dni, email, rol)
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.nombre = D.rol;

    SELECT @Administrador = usuario_id FROM dbo.USUARIO WHERE dni = '99106101';
    SELECT @Vendedor = usuario_id FROM dbo.USUARIO WHERE dni = '99106102';
    SELECT @ConPedido = usuario_id FROM dbo.USUARIO WHERE dni = '99106103';
    SELECT @SinRelaciones = usuario_id FROM dbo.USUARIO WHERE dni = '99106104';
    SELECT @RolVendedor = usuario_rol_id FROM dbo.USUARIO_ROL WHERE nombre = 'Vendedor';

    -- El caso 9 borra este cliente: cuando corra la limpieza ya no estará, y sus
    -- eventos quedarían sueltos. Por eso se anota al crearlo.
    INSERT INTO #FilasDemoAuditoria (tabla, registro_id)
    VALUES ('USUARIO', @SinRelaciones);

    -- El comprador tiene una dirección y un pedido del vendedor: no puede cambiar de
    -- rol (caso 5).
    INSERT INTO dbo.DIRECCION
    (
        calle,
        altura,
        codigo_postal,
        usuario_id,
        ciudad_id
    )
    VALUES ('Calle Demo', 100, '3400', @ConPedido, (SELECT MIN(ciudad_id) FROM dbo.CIUDAD));

    SET @Direccion = CAST(SCOPE_IDENTITY() AS INT);

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Vendedor;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #CrearPublicacionUsuarios @Vendedor = @Vendedor, @Stock = 10, @Precio = 15000.00, @PublicacionId = @Pub OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @ConPedido;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ConPedido,
        @DireccionId = @Direccion,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    -- Caso 1: USUARIO no tiene fecha de alta: el evento I registra cuándo se registró
    -- el cliente (RN03). Sin usuario de sesión, porque todavía no existe
    PRINT 'Caso 1: alta de un cliente sin usuario de sesión';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Inicio = GETDATE();

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
        'Nuevo',
        'Demo',
        '99106105',
        'demo.auditoria.auditar_usuarios.5@example.com',
        '3794106105',
        '1995-05-20',
        @HashAnterior,
        UR.usuario_rol_id
    FROM dbo.USUARIO_ROL AS UR
    WHERE UR.nombre = 'Cliente';

    SET @Nuevo = CAST(SCOPE_IDENTITY() AS INT);

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @Nuevo,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @Nuevo,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        (
            '1. Evento del alta',
            'I apellido: NULL a Demo, dni: NULL a 99106105, email: NULL a demo.auditoria.auditar_usuarios.5@example.com, '
            + 'fecha_nacimiento: NULL a 1995-05-20, nombre: NULL a Nuevo, rol: NULL a Cliente, telefono: NULL a 3794106105; '
            + 'usuario -; origen -',
            @Resumen
        ),
        ('1. Login y fecha', '1 evento; login real; fecha del paso', @Control),
        (
            '1. Detalles de password_hash',
            '0',
            (
                SELECT CAST(COUNT(*) AS VARCHAR(10))
                FROM dbo.AUDITORIA AS A
                INNER JOIN dbo.AUDITORIA_DETALLE AS AD
                    ON AD.auditoria_id = A.auditoria_id
                WHERE A.tabla = 'USUARIO'
                  AND A.registro_id = @Nuevo
                  AND AD.columna = 'password_hash'
            )
        );

    -- Caso 2: tres columnas en una sentencia, un evento. El apellido solo cambia de
    -- mayúsculas: la intercalación de la base no lo distingue, BIN2 sí
    PRINT 'Caso 2: el cliente cambia su email, su teléfono y su apellido';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Nuevo;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.USUARIO
    SET email = 'demo.auditoria.auditar_usuarios.5.nuevo@example.com',
        telefono = '3794999105',
        apellido = 'DEMO'
    WHERE usuario_id = @Nuevo;

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @Nuevo,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '2. Evento del cambio de datos',
        'U apellido: Demo a DEMO, email: demo.auditoria.auditar_usuarios.5@example.com a '
        + 'demo.auditoria.auditar_usuarios.5.nuevo@example.com, telefono: 3794106105 a 3794999105; '
        + 'usuario ' + CAST(@Nuevo AS VARCHAR(10)) + '; origen -',
        @Resumen
    );

    -- Caso 3: la contraseña solo deja constancia de que cambió, sin ningún valor
    PRINT 'Caso 3: el cliente cambia su contraseña';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.USUARIO
    SET password_hash = @HashNuevo
    WHERE usuario_id = @Nuevo;

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @Nuevo,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('3. Evento del cambio de contraseña', 'U password_hash: (oculto) a (cambiado); usuario ' + CAST(@Nuevo AS VARCHAR(10)) + '; origen -', @Resumen),
        (
            '3. Hashes en AUDITORIA_DETALLE',
            '0',
            (
                SELECT CAST(COUNT(*) AS VARCHAR(10))
                FROM dbo.AUDITORIA_DETALLE
                WHERE valor_anterior IN (@HashAnterior, @HashNuevo)
                   OR valor_nuevo IN (@HashAnterior, @HashNuevo)
            )
        );

    -- Caso 4: el cambio de rol queda con el administrador como autor (RN02)
    PRINT 'Caso 4: el administrador cambia a Vendedor el rol del cliente nuevo';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Administrador;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.USUARIO
    SET usuario_rol_id = @RolVendedor
    WHERE usuario_id = @Nuevo;

    -- El historial del usuario, como lo consultaría un administrador.
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
    WHERE tabla = 'USUARIO'
      AND registro_id = @Nuevo
    ORDER BY
        auditoria_id,
        columna;

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @Nuevo,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('4. Evento del cambio de rol', 'U rol: Cliente a Vendedor; usuario ' + CAST(@Administrador AS VARCHAR(10)) + '; origen -', @Resumen);

    -- Caso 5: trg_USUARIO_CambioRol rechaza la sentencia (RN04, RN10). Si la
    -- auditoría corrió antes, su evento se revierte con ella. El orden de los
    -- triggers no está fijado: la línea impresa muestra si se consumió un valor
    -- IDENTITY, es decir, si la auditoría llegó a correr.
    PRINT 'Caso 5: cambiar el rol del cliente que tiene un pedido';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @IdentAntes = IDENT_CURRENT('dbo.AUDITORIA');
    SET @Error = NULL;

    BEGIN TRY
        UPDATE dbo.USUARIO
        SET usuario_rol_id = @RolVendedor
        WHERE usuario_id = @ConPedido;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    PRINT 'Caso 5: IDENT_CURRENT de AUDITORIA antes ' + CAST(@IdentAntes AS VARCHAR(20))
        + ', después ' + CAST(IDENT_CURRENT('dbo.AUDITORIA') AS VARCHAR(20));

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @ConPedido,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('5. Error', '50281', CAST(@Error AS VARCHAR(10))),
        ('5. Eventos', 'sin eventos', @Resumen),
        (
            '5. Rol sin cambios',
            'Cliente',
            (
                SELECT UR.nombre
                FROM dbo.USUARIO AS U
                INNER JOIN dbo.USUARIO_ROL AS UR
                    ON UR.usuario_rol_id = U.usuario_rol_id
                WHERE U.usuario_id = @ConPedido
            )
        );

    -- Caso 6: la baja y la reactivación son dos sentencias, y dejan dos eventos
    -- (RN28). La fecha de baja no queda en USUARIO después de reactivar: solo en el
    -- historial
    PRINT 'Caso 6: el administrador da de baja a un cliente y lo reactiva';

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Baja = GETDATE();

    UPDATE dbo.USUARIO
    SET fecha_eliminacion = @Baja
    WHERE usuario_id = @ConPedido;

    UPDATE dbo.USUARIO
    SET fecha_eliminacion = NULL
    WHERE usuario_id = @ConPedido;

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @ConPedido,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '6. Eventos de la baja y la reactivación',
        'U fecha_eliminacion: NULL a ' + CONVERT(VARCHAR(23), @Baja, 121)
        + '; usuario ' + CAST(@Administrador AS VARCHAR(10)) + '; origen -'
        + ' / U fecha_eliminacion: ' + CONVERT(VARCHAR(23), @Baja, 121)
        + ' a NULL; usuario ' + CAST(@Administrador AS VARCHAR(10)) + '; origen -',
        @Resumen
    );

    -- Caso 7: un evento por fila, cada uno con sus valores. Lo ejecuta un script de
    -- mantenimiento, sin usuario de sesión
    PRINT 'Caso 7: una sentencia cambia el teléfono de dos clientes';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.USUARIO
    SET telefono = '3795' + RIGHT(dni, 6)
    WHERE usuario_id IN (@ConPedido, @SinRelaciones);

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '7. Eventos de la sentencia',
        '2',
        (
            SELECT CAST(COUNT(*) AS VARCHAR(10))
            FROM dbo.AUDITORIA
            WHERE tabla = 'USUARIO'
              AND auditoria_id > @Desde
        )
    );

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @ConPedido,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @SinRelaciones,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen2 OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('7. Evento del comprador', 'U telefono: 3794106103 a 3795106103; usuario -; origen -', @Resumen),
        ('7. Evento del visitante', 'U telefono: 3794106104 a 3795106104; usuario -; origen -', @Resumen2);

    -- Caso 8: el evento se escribe dentro de la transacción de la sentencia, y el
    -- ROLLBACK lo deshace junto con el cambio. El valor IDENTITY que usó no vuelve.
    PRINT 'Caso 8: cambio de email revertido';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @SinRelaciones;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @IdentAntes = IDENT_CURRENT('dbo.AUDITORIA');

    BEGIN TRANSACTION;

    UPDATE dbo.USUARIO
    SET email = 'demo.auditoria.auditar_usuarios.4.nuevo@example.com'
    WHERE usuario_id = @SinRelaciones;

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @SinRelaciones,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    ROLLBACK TRANSACTION;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @SinRelaciones,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen2 OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        (
            '8. Dentro de la transacción',
            'U email: demo.auditoria.auditar_usuarios.4@example.com a demo.auditoria.auditar_usuarios.4.nuevo@example.com; '
            + 'usuario ' + CAST(@SinRelaciones AS VARCHAR(10)) + '; origen -',
            @Resumen
        ),
        ('8. Después del ROLLBACK', 'sin eventos', @Resumen2),
        (
            '8. Email después del ROLLBACK',
            'demo.auditoria.auditar_usuarios.4@example.com',
            (SELECT email FROM dbo.USUARIO WHERE usuario_id = @SinRelaciones)
        ),
        (
            '8. IDENTITY de AUDITORIA',
            'avanzó sin filas nuevas',
            CASE WHEN IDENT_CURRENT('dbo.AUDITORIA') > @IdentAntes THEN 'avanzó' ELSE 'no avanzó' END
            + CASE WHEN EXISTS (SELECT 1 FROM dbo.AUDITORIA WHERE auditoria_id > @Desde) THEN ' con filas nuevas' ELSE ' sin filas nuevas' END
        );

    -- Caso 9: el DELETE guarda la última versión de la fila, con el teléfono del caso
    -- 7, salvo la contraseña. fecha_eliminacion es NULL y no tiene detalle
    PRINT 'Caso 9: borrado físico del cliente sin relaciones';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Administrador;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Inicio = GETDATE();

    DELETE FROM dbo.USUARIO
    WHERE usuario_id = @SinRelaciones;

    EXEC #ResumenAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @SinRelaciones,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'USUARIO',
        @RegistroId = @SinRelaciones,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        (
            '9. Evento del borrado',
            'D apellido: Demo a NULL, dni: 99106104 a NULL, email: demo.auditoria.auditar_usuarios.4@example.com a NULL, '
            + 'fecha_nacimiento: 1990-01-01 a NULL, nombre: Visitante a NULL, rol: Cliente a NULL, telefono: 3795106104 a NULL; '
            + 'usuario ' + CAST(@Administrador AS VARCHAR(10)) + '; origen -',
            @Resumen
        ),
        ('9. Login y fecha', '1 evento; login real; fecha del paso', @Control),
        (
            '9. El usuario ya no existe',
            '0',
            (SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM dbo.USUARIO WHERE usuario_id = @SinRelaciones)
        );

    -- Caso 10: ninguna sentencia deja una transacción abierta, tampoco las que
    -- fallaron
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
-- eventos sí, porque AUDITORIA no tiene claves foráneas, y por eso se cuentan aparte.
EXEC #LimpiarDemoUsuarios;
EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;

SELECT
    (
        SELECT COUNT(*)
        FROM dbo.USUARIO
        WHERE email LIKE 'demo.auditoria.auditar[_]usuarios.%@example.com'
    )
    + (
        SELECT COUNT(*)
        FROM dbo.AUDITORIA AS A
        INNER JOIN #FilasDemoAuditoria AS F
            ON F.tabla = A.tabla
           AND F.registro_id = A.registro_id
    ) AS filas_demo;

DROP PROCEDURE #LimpiarDemoUsuarios;
DROP PROCEDURE #CrearPublicacionUsuarios;
DROP PROCEDURE #ResumenAuditoria;
DROP PROCEDURE #ControlAuditoria;
DROP TABLE #FilasDemoAuditoria;
GO
