USE [sistema-venta-libros];
GO

-- Demostración de dbo.trg_PEDIDO_Auditoria (script.sql). Requiere la base instalada
-- completa, como indica el README, más estructura_auditoria/script.sql y este
-- script.sql.
-- PUBLICACION tiene un índice filtrado: sin QUOTED_IDENTIFIER, escribir en ella falla
-- con el error 1934 desde sqlcmd.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- No corre dentro de una transacción: los procedimientos de la venta confirman las
-- suyas. Crea sus propios usuarios, publicaciones, pedidos y pagos, y
-- #LimpiarDemoPedidos los borra antes y después, junto con sus eventos de
-- auditoría, así que se puede ejecutar varias veces sin dejar datos en la base. Lo
-- único que no se revierte son los contadores IDENTITY.
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

IF OBJECT_ID(N'tempdb..#LimpiarDemoPedidos', N'P') IS NOT NULL
    DROP PROCEDURE #LimpiarDemoPedidos;
GO

IF OBJECT_ID(N'tempdb..#CrearPublicacionPedidos', N'P') IS NOT NULL
    DROP PROCEDURE #CrearPublicacionPedidos;
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
CREATE PROCEDURE #LimpiarDemoPedidos
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Usuarios TABLE (usuario_id INT PRIMARY KEY);

    BEGIN TRANSACTION;

    INSERT INTO @Usuarios (usuario_id)
    SELECT usuario_id
    FROM dbo.USUARIO
    WHERE email LIKE 'demo.auditoria.auditar[_]pedidos.%@example.com';

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
CREATE PROCEDURE #CrearPublicacionPedidos
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
-- U estado: Pendiente a Confirmado; usuario -; origen trg_PAGO_ConfirmarPedido
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
-- posteriores. La pasarela de pago no declara usuario.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

EXEC #LimpiarDemoPedidos;

DECLARE @Resultados TABLE
(
    orden INT IDENTITY(1,1) PRIMARY KEY,
    caso VARCHAR(70) NOT NULL,
    esperado VARCHAR(300) NOT NULL,
    obtenido VARCHAR(300) NULL,
    resultado AS CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END
);

DECLARE @Columnas VARCHAR(400) = 'estado,fecha_pedido';
DECLARE @Vendedor INT;
DECLARE @Cliente INT;
DECLARE @Direccion INT;
DECLARE @Tarjeta INT;
DECLARE @Carrito dbo.DetalleVentaType;
DECLARE @PubAlta INT;
DECLARE @PubEscasa INT;
DECLARE @PedidoVenta INT;
DECLARE @PedidoCancelado INT;
DECLARE @PedidoSinVenta INT;
DECLARE @PedidoFecha INT;
DECLARE @Pago INT;
DECLARE @Desde INT;
DECLARE @Inicio DATETIME;
DECLARE @FechaAntes DATETIME;
DECLARE @IdentAntes NUMERIC(38, 0);
DECLARE @Resumen VARCHAR(1000);
DECLARE @Control VARCHAR(100);
DECLARE @Error INT;
-- Suma @@TRANCOUNT después de cada EXEC y de cada sentencia que falla: tiene que
-- seguir en cero.
DECLARE @Abiertas INT = 0;

BEGIN TRY
    -- Datos propios: un vendedor y un cliente con dirección, cargados por un script
    -- sin usuario de sesión. El vendedor publica con stock alto y con stock 2.
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
            ('Vendedor', '99104101', 'demo.auditoria.auditar_pedidos.1@example.com', 'Vendedor'),
            ('Cliente', '99104102', 'demo.auditoria.auditar_pedidos.2@example.com', 'Cliente')
    ) AS D (nombre, dni, email, rol)
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.nombre = D.rol;

    SELECT @Vendedor = usuario_id FROM dbo.USUARIO WHERE dni = '99104101';
    SELECT @Cliente = usuario_id FROM dbo.USUARIO WHERE dni = '99104102';

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

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Vendedor;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #CrearPublicacionPedidos @Vendedor = @Vendedor, @Stock = 50, @Precio = 8000.00, @PublicacionId = @PubAlta OUTPUT;
    EXEC #CrearPublicacionPedidos @Vendedor = @Vendedor, @Stock = 2, @Precio = 6000.00, @PublicacionId = @PubEscasa OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    -- Caso 1: la aprobación del pago confirma el pedido en trg_PAGO_ConfirmarPedido,
    -- que queda como origen (RN19)
    PRINT 'Caso 1: la pasarela aprueba el pago de un pedido';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Cliente;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@PubAlta, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @Cliente,
        @DireccionId = @Direccion,
        @Carrito = @Carrito,
        @PedidoId = @PedidoVenta OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @PedidoVenta,
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
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoVenta,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoVenta,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('1. Error de la venta', 'sin error', ISNULL(CAST(@Error AS VARCHAR(10)), 'sin error')),
        ('1. Evento de la confirmación', 'U estado: Pendiente a Confirmado; usuario -; origen trg_PAGO_ConfirmarPedido', @Resumen),
        ('1. Login y fecha', '1 evento; login real; fecha del paso', @Control);

    -- Caso 2: la entrega no tiene fecha ni autor en PEDIDO: los guarda el evento (RN20)
    PRINT 'Caso 2: el vendedor marca entregado el pedido';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Vendedor;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @Inicio = GETDATE();

    UPDATE dbo.PEDIDO
    SET pedido_estado_id = (SELECT pedido_estado_id FROM dbo.PEDIDO_ESTADO WHERE nombre = 'Entregado')
    WHERE pedido_id = @PedidoVenta;

    -- El historial del pedido, como lo consultaría un administrador.
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
    WHERE tabla = 'PEDIDO'
      AND registro_id = @PedidoVenta
    ORDER BY
        auditoria_id,
        columna;

    EXEC #ResumenAuditoria
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoVenta,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    EXEC #ControlAuditoria
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoVenta,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Inicio = @Inicio,
        @Control = @Control OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('2. Evento de la entrega', 'U estado: Confirmado a Entregado; usuario ' + CAST(@Vendedor AS VARCHAR(10)) + '; origen -', @Resumen),
        ('2. Login y fecha', '1 evento; login real; fecha del paso', @Control);

    -- Caso 3: una cancelación directa queda con el cliente como autor
    PRINT 'Caso 3: el cliente cancela un pedido pendiente';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Cliente;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@PubAlta, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @Cliente,
        @DireccionId = @Direccion,
        @Carrito = @Carrito,
        @PedidoId = @PedidoCancelado OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PEDIDO
    SET pedido_estado_id = (SELECT pedido_estado_id FROM dbo.PEDIDO_ESTADO WHERE nombre = 'Cancelado')
    WHERE pedido_id = @PedidoCancelado;

    EXEC #ResumenAuditoria
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoCancelado,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('3. Evento de la cancelación', 'U estado: Pendiente a Cancelado; usuario ' + CAST(@Cliente AS VARCHAR(10)) + '; origen -', @Resumen);

    -- Caso 4: cobro sin venta (RN37). Con el pago Pendiente, el vendedor baja el
    -- stock por debajo de lo pedido. Al aprobarse el pago, usp_RegistrarVenta ve que
    -- no hay stock libre y cancela el pedido con su propio UPDATE: el pedido nunca
    -- pasa por Confirmado y el origen queda en NULL.
    PRINT 'Caso 4: cobro sin venta';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Cliente;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@PubEscasa, 2);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @Cliente,
        @DireccionId = @Direccion,
        @Carrito = @Carrito,
        @PedidoId = @PedidoSinVenta OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @PedidoSinVenta,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Vendedor;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    UPDATE dbo.PUBLICACION
    SET stock = 1
    WHERE publicacion_id = @PubEscasa;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '4. Stock libre para el pedido antes de aprobar',
        '1',
        CAST(dbo.fn_StockLibre(@PubEscasa, @PedidoSinVenta) AS VARCHAR(10))
    );

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
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
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoSinVenta,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('4. Error de la aprobación', 'sin error', ISNULL(CAST(@Error AS VARCHAR(10)), 'sin error')),
        ('4. Evento de la cancelación', 'U estado: Pendiente a Cancelado; usuario -; origen -', @Resumen),
        (
            '4. Eventos que confirman el pedido',
            '0',
            (
                SELECT CAST(COUNT(*) AS VARCHAR(10))
                FROM dbo.AUDITORIA AS A
                INNER JOIN dbo.AUDITORIA_DETALLE AS AD
                    ON AD.auditoria_id = A.auditoria_id
                WHERE A.tabla = 'PEDIDO'
                  AND A.registro_id = @PedidoSinVenta
                  AND AD.columna = 'estado'
                  AND AD.valor_nuevo = 'Confirmado'
            )
        );

    -- Caso 5: mover fecha_pedido, como hacen las demostraciones para simular el
    -- tiempo, cambia el plazo de la reserva (RN34). El resumen exacto también
    -- comprueba que el evento no tiene detalle de estado.
    PRINT 'Caso 5: fecha_pedido 10 minutos hacia el pasado';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Cliente;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@PubAlta, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @Cliente,
        @DireccionId = @Direccion,
        @Carrito = @Carrito,
        @PedidoId = @PedidoFecha OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @FechaAntes = fecha_pedido
    FROM dbo.PEDIDO
    WHERE pedido_id = @PedidoFecha;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PEDIDO
    SET fecha_pedido = DATEADD(MINUTE, -10, fecha_pedido)
    WHERE pedido_id = @PedidoFecha;

    EXEC #ResumenAuditoria
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoFecha,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '5. Evento del cambio de fecha',
        'U fecha_pedido: ' + CONVERT(VARCHAR(23), @FechaAntes, 121)
        + ' a ' + CONVERT(VARCHAR(23), DATEADD(MINUTE, -10, @FechaAntes), 121)
        + '; usuario -; origen -',
        @Resumen
    );

    -- Caso 6: trg_PEDIDO_Transicion rechaza la sentencia (RN19, RN20). Es el primero
    -- de los triggers de UPDATE de PEDIDO (sp_settriggerorder), así que la auditoría
    -- no llega a correr y no consume un valor IDENTITY.
    PRINT 'Caso 6: pasar a Pendiente el pedido entregado';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Vendedor;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;
    SET @IdentAntes = IDENT_CURRENT('dbo.AUDITORIA');
    SET @Error = NULL;

    BEGIN TRY
        UPDATE dbo.PEDIDO
        SET pedido_estado_id = (SELECT pedido_estado_id FROM dbo.PEDIDO_ESTADO WHERE nombre = 'Pendiente')
        WHERE pedido_id = @PedidoVenta;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #ResumenAuditoria
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoVenta,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('6. Error', '50215', CAST(@Error AS VARCHAR(10))),
        ('6. Eventos', 'sin eventos', @Resumen),
        (
            '6. IDENTITY de AUDITORIA',
            'no avanzó',
            CASE WHEN IDENT_CURRENT('dbo.AUDITORIA') > @IdentAntes THEN 'avanzó' ELSE 'no avanzó' END
        ),
        (
            '6. Estado sin cambios',
            'Entregado',
            (
                SELECT PE.nombre
                FROM dbo.PEDIDO AS P
                INNER JOIN dbo.PEDIDO_ESTADO AS PE
                    ON PE.pedido_estado_id = P.pedido_estado_id
                WHERE P.pedido_id = @PedidoVenta
            )
        );

    -- Caso 7: las dos sentencias pasan el control de UPDATE(), y el filtro EXCEPT
    -- descarta los valores que no cambiaron
    PRINT 'Caso 7: UPDATE sin cambios';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PEDIDO
    SET fecha_pedido = fecha_pedido
    WHERE pedido_id = @PedidoFecha;

    EXEC #ResumenAuditoria
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoFecha,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. fecha_pedido = fecha_pedido', 'sin eventos', @Resumen);

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    UPDATE dbo.PEDIDO
    SET pedido_estado_id = pedido_estado_id
    WHERE pedido_id = @PedidoFecha;

    EXEC #ResumenAuditoria
        @Tabla = 'PEDIDO',
        @RegistroId = @PedidoFecha,
        @Columnas = @Columnas,
        @Desde = @Desde,
        @Resumen = @Resumen OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('7. pedido_estado_id = pedido_estado_id', 'sin eventos', @Resumen);

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
EXEC #LimpiarDemoPedidos;
EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;

SELECT
    (
        SELECT COUNT(*)
        FROM dbo.USUARIO
        WHERE email LIKE 'demo.auditoria.auditar[_]pedidos.%@example.com'
    )
    + (
        SELECT COUNT(*)
        FROM dbo.AUDITORIA AS A
        INNER JOIN #FilasDemoAuditoria AS F
            ON F.tabla = A.tabla
           AND F.registro_id = A.registro_id
    ) AS filas_demo;

DROP PROCEDURE #LimpiarDemoPedidos;
DROP PROCEDURE #CrearPublicacionPedidos;
DROP PROCEDURE #ResumenAuditoria;
DROP PROCEDURE #ControlAuditoria;
DROP TABLE #FilasDemoAuditoria;
GO
