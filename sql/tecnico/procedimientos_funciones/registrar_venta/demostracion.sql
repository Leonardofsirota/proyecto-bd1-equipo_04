USE [sistema-venta-libros];
GO

-- Demostración de las funciones y los procedimientos de script.sql. Requiere la base
-- instalada completa, con los triggers de sql/ddl/triggers-consistencia.sql.
-- PUBLICACION tiene un índice filtrado: sin QUOTED_IDENTIFIER, escribir en ella falla
-- con el error 1934 desde sqlcmd.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- A diferencia de la demostración de abm_categorias, no corre dentro de una
-- transacción: los procedimientos confirman las suyas, y su ROLLBACK anularía la
-- externa. Crea sus propios usuarios, publicaciones, pedidos y pagos, y
-- #LimpiarDemoVenta los borra antes y después, así que se puede ejecutar varias
-- veces sin dejar datos en la base. Lo único que no se revierte son los contadores
-- IDENTITY: cada ejecución deja un salto en los ID.
IF OBJECT_ID(N'tempdb..#LimpiarDemoVenta', N'P') IS NOT NULL
    DROP PROCEDURE #LimpiarDemoVenta;
GO

IF OBJECT_ID(N'tempdb..#CrearPublicacionDemo', N'P') IS NOT NULL
    DROP PROCEDURE #CrearPublicacionDemo;
GO

IF OBJECT_ID(N'tempdb..#EstadoDemoVenta', N'P') IS NOT NULL
    DROP PROCEDURE #EstadoDemoVenta;
GO

-- Borra lo que cuelga de los usuarios de demostración, en orden de dependencia.
-- Pagos y renglones no se borran en la operación normal, así que sus triggers se
-- deshabilitan solo para esta limpieza. DISABLE TRIGGER es transaccional: si algo
-- falla, XACT_ABORT revierte todo y los triggers vuelven a quedar habilitados.
CREATE PROCEDURE #LimpiarDemoVenta
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Usuarios TABLE (usuario_id INT PRIMARY KEY);

    BEGIN TRANSACTION;

    INSERT INTO @Usuarios (usuario_id)
    SELECT usuario_id
    FROM dbo.USUARIO
    WHERE email LIKE 'demo.registrar.venta.%@example.com';

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

    COMMIT TRANSACTION;
END;
GO

-- Crea una publicación con un libro que el vendedor todavía no publicó, porque
-- uq_publicacion_usuario_libro_condicion no admite repetirlo.
CREATE PROCEDURE #CrearPublicacionDemo
    @Vendedor INT,
    @Stock INT,
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
        1000.00
    FROM dbo.LIBRO AS L
    INNER JOIN dbo.CONDICION AS C
        ON C.nombre = 'Nuevo'
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.PUBLICACION AS PUB
        WHERE PUB.usuario_id = @Vendedor
          AND PUB.libro_id = L.libro_id
    )
    ORDER BY L.libro_id;

    SET @PublicacionId = CAST(SCOPE_IDENTITY() AS INT);
END;
GO

-- Resume un pago, su pedido y su publicación en un texto comparable. Los pedidos
-- de la demostración tienen un solo renglón.
CREATE PROCEDURE #EstadoDemoVenta
    @PagoId INT,
    @Estado VARCHAR(60) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Estado = NULL;

    SELECT @Estado = PGE.nombre
        + CASE WHEN PG.fecha_pago IS NULL THEN ' sin fecha' ELSE ' con fecha' END
        + ' / ' + PE.nombre
        + ' / stock ' + CAST(PUB.stock AS VARCHAR(10))
        + ' / disponible ' + CAST(PUB.disponible AS VARCHAR(1))
    FROM dbo.PAGO AS PG
    INNER JOIN dbo.PAGO_ESTADO AS PGE
        ON PGE.pago_estado_id = PG.pago_estado_id
    INNER JOIN dbo.PEDIDO AS P
        ON P.pedido_id = PG.pedido_id
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.pedido_estado_id = P.pedido_estado_id
    INNER JOIN dbo.PEDIDO_DETALLE AS PD
        ON PD.pedido_id = P.pedido_id
    INNER JOIN dbo.PUBLICACION AS PUB
        ON PUB.publicacion_id = PD.publicacion_id
    WHERE PG.pago_id = @PagoId;
END;
GO

-- Con XACT_ABORT en OFF, los errores provocados no cortan el lote. El paso del
-- tiempo se simula moviendo las fechas de los pedidos y pagos de la demostración.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

EXEC #LimpiarDemoVenta;

DECLARE @Resultados TABLE
(
    orden INT IDENTITY(1,1) PRIMARY KEY,
    caso VARCHAR(70) NOT NULL,
    esperado VARCHAR(60) NOT NULL,
    obtenido VARCHAR(60) NULL,
    resultado AS CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END
);

DECLARE @ClienteA INT;
DECLARE @ClienteB INT;
DECLARE @DireccionA INT;
DECLARE @DireccionB INT;
DECLARE @Vendedor INT;
DECLARE @VendedorBaja INT;
DECLARE @Tarjeta INT;
DECLARE @Transferencia INT;
DECLARE @Carrito dbo.DetalleVentaType;
DECLARE @CarritoVacio dbo.DetalleVentaType;
DECLARE @Pub INT;
DECLARE @PubAgotada INT;
DECLARE @PubBaja INT;
DECLARE @Pedido INT;
DECLARE @PedidoB INT;
DECLARE @PedidoConfirmado INT;
DECLARE @PedidoVencido INT;
DECLARE @PedidoConPago INT;
DECLARE @Pago INT;
DECLARE @PagoAprobado INT;
DECLARE @Vencimiento DATETIME;
DECLARE @Estado VARCHAR(60);
DECLARE @Error INT;
-- Suma @@TRANCOUNT después de cada EXEC: tiene que seguir en cero.
DECLARE @Abiertas INT = 0;

BEGIN TRY
    -- Datos propios: dos clientes con dirección y dos vendedores. El segundo se da de
    -- baja en el caso 10, después de publicar: un vendedor dado de baja no puede hacerlo
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
            ('Cliente A', '99000001', 'demo.registrar.venta.1@example.com', 'Cliente'),
            ('Cliente B', '99000002', 'demo.registrar.venta.2@example.com', 'Cliente'),
            ('Vendedor', '99000003', 'demo.registrar.venta.3@example.com', 'Vendedor'),
            ('Vendedor baja', '99000004', 'demo.registrar.venta.4@example.com', 'Vendedor')
    ) AS D (nombre, dni, email, rol)
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.nombre = D.rol;

    SELECT @ClienteA = usuario_id FROM dbo.USUARIO WHERE dni = '99000001';
    SELECT @ClienteB = usuario_id FROM dbo.USUARIO WHERE dni = '99000002';
    SELECT @Vendedor = usuario_id FROM dbo.USUARIO WHERE dni = '99000003';
    SELECT @VendedorBaja = usuario_id FROM dbo.USUARIO WHERE dni = '99000004';

    INSERT INTO dbo.DIRECCION
    (
        calle,
        altura,
        codigo_postal,
        usuario_id,
        ciudad_id
    )
    SELECT
        'Calle Demo',
        100,
        '3400',
        U.usuario_id,
        (SELECT MIN(ciudad_id) FROM dbo.CIUDAD)
    FROM dbo.USUARIO AS U
    WHERE U.usuario_id IN (@ClienteA, @ClienteB);

    SELECT @DireccionA = direccion_id FROM dbo.DIRECCION WHERE usuario_id = @ClienteA;
    SELECT @DireccionB = direccion_id FROM dbo.DIRECCION WHERE usuario_id = @ClienteB;

    SELECT @Tarjeta = pago_metodo_id FROM dbo.PAGO_METODO WHERE nombre = 'Tarjeta de crédito';
    SELECT @Transferencia = pago_metodo_id FROM dbo.PAGO_METODO WHERE nombre = 'Transferencia';

    -- Caso 1: la venta confirma el pedido, agota el stock y baja la publicación
    PRINT 'Caso 1: venta exitosa con tarjeta que agota el stock';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 2, @PublicacionId = @PubAgotada OUTPUT;

    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@PubAgotada, 2);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @PedidoConfirmado OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @PedidoConfirmado,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @PagoAprobado OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_RegistrarVenta
        @PagoId = @PagoAprobado,
        @Resultado = 'Aprobado';
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoVenta @PagoId = @PagoAprobado, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('1. Venta exitosa', 'Aprobado con fecha / Confirmado / stock 0 / disponible 0', @Estado),
        ('1. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 2: un rechazo no toca el pedido ni el stock, y a los 10 minutos la
    -- reserva sigue vigente para reintentar con otro método
    PRINT 'Caso 2: rechazo con reintento dentro de los 15 minutos';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 3, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_RegistrarVenta
        @PagoId = @Pago,
        @Resultado = 'Rechazado';
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoVenta @PagoId = @Pago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('2. Tras el rechazo', 'Rechazado sin fecha / Pendiente / stock 3 / disponible 1', @Estado);

    UPDATE dbo.PEDIDO
    SET fecha_pedido = DATEADD(MINUTE, -10, fecha_pedido)
    WHERE pedido_id = @Pedido;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Transferencia,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_RegistrarVenta
        @PagoId = @Pago,
        @Resultado = 'Aprobado';
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoVenta @PagoId = @Pago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('2. Tras el reintento', 'Aprobado con fecha / Confirmado / stock 2 / disponible 1', @Estado);

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT '2. Pagos en el historial del pedido', '2', COUNT(*)
    FROM dbo.PAGO
    WHERE pedido_id = @Pedido;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('2. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 3: pasados los 15 minutos no se puede reintentar. El pedido vencido deja
    -- de reservar y el cliente crea uno nuevo
    PRINT 'Caso 3: reintento con la reserva vencida';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 3, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_RegistrarVenta
        @PagoId = @Pago,
        @Resultado = 'Rechazado';
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    UPDATE dbo.PEDIDO
    SET fecha_pedido = DATEADD(MINUTE, -16, fecha_pedido)
    WHERE pedido_id = @Pedido;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_IniciarPago
            @PedidoId = @Pedido,
            @PagoMetodoId = @Tarjeta;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('3. Reintento con la reserva vencida', '50114', CAST(@Error AS VARCHAR(10))),
        ('3. Stock libre: solo reserva el pedido nuevo', '2', CAST(dbo.fn_StockLibre(@Pub, NULL) AS VARCHAR(10))),
        ('3. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 4: el cliente A reserva la última unidad y el B no puede comprarla hasta
    -- que esa reserva vence, aunque el stock real siga en 1
    PRINT 'Caso 4: competencia por la última unidad';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 1, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @PedidoVencido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CrearPedido
            @UsuarioId = @ClienteB,
            @DireccionId = @DireccionB,
            @Carrito = @Carrito,
            @PedidoId = @PedidoB OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('4. Cliente B con la unidad reservada por A', '50107', CAST(@Error AS VARCHAR(10)));

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT
        '4. Stock con la reserva de A vigente',
        'real 1 / libre 0',
        'real ' + CAST(stock AS VARCHAR(10))
            + ' / libre ' + CAST(dbo.fn_StockLibre(publicacion_id, NULL) AS VARCHAR(10))
    FROM dbo.PUBLICACION
    WHERE publicacion_id = @Pub;

    UPDATE dbo.PEDIDO
    SET fecha_pedido = DATEADD(MINUTE, -16, fecha_pedido)
    WHERE pedido_id = @PedidoVencido;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT
        '4. Stock con la reserva de A vencida',
        'real 1 / libre 1',
        'real ' + CAST(stock AS VARCHAR(10))
            + ' / libre ' + CAST(dbo.fn_StockLibre(publicacion_id, NULL) AS VARCHAR(10))
    FROM dbo.PUBLICACION
    WHERE publicacion_id = @Pub;

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteB,
        @DireccionId = @DireccionB,
        @Carrito = @Carrito,
        @PedidoId = @PedidoB OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT
        '4. Stock con la reserva de B',
        'real 1 / libre 0',
        'real ' + CAST(stock AS VARCHAR(10))
            + ' / libre ' + CAST(dbo.fn_StockLibre(publicacion_id, NULL) AS VARCHAR(10))
    FROM dbo.PUBLICACION
    WHERE publicacion_id = @Pub;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('4. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 5: el pago del caso 1 ya no está Pendiente y no se vuelve a procesar
    PRINT 'Caso 5: pago ya procesado';

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarVenta
            @PagoId = @PagoAprobado,
            @Resultado = 'Aprobado';
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoVenta @PagoId = @PagoAprobado, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('5. Segunda llamada sobre el pago del caso 1', '50123', CAST(@Error AS VARCHAR(10))),
        ('5. Estado sin cambios', 'Aprobado con fecha / Confirmado / stock 0 / disponible 0', @Estado),
        ('5. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 6: la aprobación llega con la reserva vencida, pero nadie tomó la unidad
    PRINT 'Caso 6: aprobación tardía con stock libre';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 1, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    UPDATE dbo.PEDIDO
    SET fecha_pedido = DATEADD(MINUTE, -20, fecha_pedido)
    WHERE pedido_id = @Pedido;

    UPDATE dbo.PAGO
    SET fecha_creacion = DATEADD(MINUTE, -20, fecha_creacion)
    WHERE pago_id = @Pago;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '6. Reserva antes de la aprobación',
        'vencida',
        CASE WHEN dbo.fn_VencimientoReserva(@Pedido) <= GETDATE() THEN 'vencida' ELSE 'vigente' END
    );

    EXEC dbo.usp_RegistrarVenta
        @PagoId = @Pago,
        @Resultado = 'Aprobado';
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoVenta @PagoId = @Pago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('6. Venta registrada', 'Aprobado con fecha / Confirmado / stock 0 / disponible 0', @Estado),
        ('6. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 7: mientras estaba vencida, otro pedido reservó la unidad. No hay venta,
    -- y el mensaje de devolución aparece en el resultado de usp_RegistrarVenta
    PRINT 'Caso 7: aprobación tardía sin stock libre';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 1, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    UPDATE dbo.PEDIDO
    SET fecha_pedido = DATEADD(MINUTE, -20, fecha_pedido)
    WHERE pedido_id = @Pedido;

    UPDATE dbo.PAGO
    SET fecha_creacion = DATEADD(MINUTE, -20, fecha_creacion)
    WHERE pago_id = @Pago;

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteB,
        @DireccionId = @DireccionB,
        @Carrito = @Carrito,
        @PedidoId = @PedidoB OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

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

    EXEC #EstadoDemoVenta @PagoId = @Pago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('7. Error de la aprobación tardía', 'sin error', COALESCE(CAST(@Error AS VARCHAR(10)), 'sin error')),
        ('7. Sin venta y con rastro del cobro', 'Cancelado con fecha / Cancelado / stock 1 / disponible 1', @Estado),
        ('7. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 8: el pedido se canceló mientras el pago estaba pendiente
    PRINT 'Caso 8: aprobación con el pedido fuera de Pendiente';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 1, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    UPDATE P
    SET P.pedido_estado_id = PE.pedido_estado_id
    FROM dbo.PEDIDO AS P
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.nombre = 'Cancelado'
    WHERE P.pedido_id = @Pedido;

    EXEC dbo.usp_RegistrarVenta
        @PagoId = @Pago,
        @Resultado = 'Aprobado';
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoVenta @PagoId = @Pago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('8. Sin venta y con rastro del cobro', 'Cancelado con fecha / Cancelado / stock 1 / disponible 1', @Estado),
        ('8. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 9: el plazo depende del método de pago, y un pedido con fecha futura no
    -- reserva. Las reservas no descuentan el stock: solo reducen el stock libre
    PRINT 'Caso 9: plazos de reserva';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 10, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @PedidoConPago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT
        '9. Sin pago: minutos desde fecha_pedido',
        '15',
        DATEDIFF(MINUTE, fecha_pedido, dbo.fn_VencimientoReserva(pedido_id))
    FROM dbo.PEDIDO
    WHERE pedido_id = @PedidoConPago;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @PedidoConPago,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT,
        @Vencimiento = @Vencimiento OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT
        '9. Tarjeta: minutos desde la creación del pago',
        '15',
        DATEDIFF(MINUTE, fecha_creacion, @Vencimiento)
    FROM dbo.PAGO
    WHERE pago_id = @Pago;

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Transferencia,
        @PagoId = @Pago OUTPUT,
        @Vencimiento = @Vencimiento OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    SELECT
        '9. Transferencia: horas desde la creación del pago',
        '48',
        DATEDIFF(HOUR, fecha_creacion, @Vencimiento)
    FROM dbo.PAGO
    WHERE pago_id = @Pago;

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteB,
        @DireccionId = @DireccionB,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('9. Stock libre con tres reservas vigentes', '7', CAST(dbo.fn_StockLibre(@Pub, NULL) AS VARCHAR(10)));

    UPDATE dbo.PEDIDO
    SET fecha_pedido = DATEADD(DAY, 1, GETDATE())
    WHERE pedido_id = @Pedido;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        (
            '9. Fecha futura: vencimiento de la reserva',
            'NULL',
            COALESCE(CONVERT(VARCHAR(23), dbo.fn_VencimientoReserva(@Pedido), 121), 'NULL')
        ),
        ('9. Fecha futura: no resta del stock libre', '8', CAST(dbo.fn_StockLibre(@Pub, NULL) AS VARCHAR(10))),
        ('9. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 10: cada error de los procedimientos, con datos que solo incumplen esa
    -- validación. @Pub es la publicación del caso 9, que sigue con stock libre
    PRINT 'Caso 10: validaciones';

    EXEC #CrearPublicacionDemo @Vendedor = @VendedorBaja, @Stock = 1, @PublicacionId = @PubBaja OUTPUT;

    UPDATE dbo.USUARIO
    SET fecha_eliminacion = GETDATE()
    WHERE usuario_id = @VendedorBaja;

    -- Error 50101: el usuario no es cliente
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CrearPedido
            @UsuarioId = @Vendedor,
            @DireccionId = @DireccionA,
            @Carrito = @Carrito;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_CrearPedido: el usuario no es cliente', '50101', CAST(@Error AS VARCHAR(10)));

    -- Error 50102: la dirección es de otro cliente
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CrearPedido
            @UsuarioId = @ClienteA,
            @DireccionId = @DireccionB,
            @Carrito = @Carrito;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_CrearPedido: dirección de otro cliente', '50102', CAST(@Error AS VARCHAR(10)));

    -- Error 50103: el carrito no tiene filas
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CrearPedido
            @UsuarioId = @ClienteA,
            @DireccionId = @DireccionA,
            @Carrito = @CarritoVacio;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_CrearPedido: carrito vacío', '50103', CAST(@Error AS VARCHAR(10)));

    -- Error 50104: la cantidad no es mayor que cero
    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 0);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CrearPedido
            @UsuarioId = @ClienteA,
            @DireccionId = @DireccionA,
            @Carrito = @Carrito;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_CrearPedido: cantidad cero', '50104', CAST(@Error AS VARCHAR(10)));

    -- Error 50105: la publicación del caso 1 quedó sin stock y no disponible
    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@PubAgotada, 1);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CrearPedido
            @UsuarioId = @ClienteA,
            @DireccionId = @DireccionA,
            @Carrito = @Carrito;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_CrearPedido: publicación no disponible', '50105', CAST(@Error AS VARCHAR(10)));

    -- Error 50105: la baja del vendedor dio de baja su publicación
    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@PubBaja, 1);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CrearPedido
            @UsuarioId = @ClienteA,
            @DireccionId = @DireccionA,
            @Carrito = @Carrito;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_CrearPedido: vendedor dado de baja', '50105', CAST(@Error AS VARCHAR(10)));

    -- Error 50107: pide más unidades que el stock libre
    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 9);

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CrearPedido
            @UsuarioId = @ClienteA,
            @DireccionId = @DireccionA,
            @Carrito = @Carrito;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_CrearPedido: más unidades que el stock libre', '50107', CAST(@Error AS VARCHAR(10)));

    -- Error 50111: el método de pago no existe
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_IniciarPago
            @PedidoId = @PedidoConPago,
            @PagoMetodoId = 0;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_IniciarPago: método inexistente', '50111', CAST(@Error AS VARCHAR(10)));

    -- Error 50112: el pedido del caso 1 ya está Confirmado
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_IniciarPago
            @PedidoId = @PedidoConfirmado,
            @PagoMetodoId = @Tarjeta;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_IniciarPago: pedido no pendiente', '50112', CAST(@Error AS VARCHAR(10)));

    -- Error 50113: el pedido del caso 9 ya tiene un pago Pendiente
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_IniciarPago
            @PedidoId = @PedidoConPago,
            @PagoMetodoId = @Tarjeta;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_IniciarPago: pedido con pago pendiente', '50113', CAST(@Error AS VARCHAR(10)));

    -- Error 50114: venció la reserva del pedido del cliente A en el caso 4
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_IniciarPago
            @PedidoId = @PedidoVencido,
            @PagoMetodoId = @Tarjeta;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_IniciarPago: reserva vencida', '50114', CAST(@Error AS VARCHAR(10)));

    -- Error 50121: el resultado no es válido
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarVenta
            @PagoId = @PagoAprobado,
            @Resultado = 'Demorado';
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_RegistrarVenta: resultado no válido', '50121', CAST(@Error AS VARCHAR(10)));

    -- Error 50122: el pago no existe
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarVenta
            @PagoId = 0,
            @Resultado = 'Aprobado';
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. usp_RegistrarVenta: pago inexistente', '50122', CAST(@Error AS VARCHAR(10)));

    -- Error 50123: el pago del caso 1 ya fue procesado
    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarVenta
            @PagoId = @PagoAprobado,
            @Resultado = 'Rechazado';
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('10. usp_RegistrarVenta: pago ya procesado', '50123', CAST(@Error AS VARCHAR(10))),
        ('10. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));

    SET @Abiertas = 0;

    -- Caso 11: el pago cobra el total menos el descuento. Con precio 1000, 100 unidades
    -- suman 100.000, el límite del tramo del 0 %, y 150 suman 150.000, en el del 5 %
    PRINT 'Caso 11: descuento en el importe del pago';

    EXEC #CrearPublicacionDemo @Vendedor = @Vendedor, @Stock = 250, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 100);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Estado = 'total ' + CAST(dbo.fn_TotalPedido(pedido_id) AS VARCHAR(20))
        + ' / ' + CAST(dbo.fn_PorcentajeDescuentoPedido(pedido_id) AS VARCHAR(10)) + ' %'
        + ' / importe ' + CAST(importe AS VARCHAR(20))
    FROM dbo.PAGO
    WHERE pago_id = @Pago;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('11. Sin descuento: total, porcentaje e importe', 'total 100000.00 / 0.00 % / importe 100000.00', @Estado);

    EXEC dbo.usp_RegistrarVenta
        @PagoId = @Pago,
        @Resultado = 'Aprobado';
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoVenta @PagoId = @Pago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('11. Sin descuento: venta registrada', 'Aprobado con fecha / Confirmado / stock 150 / disponible 1', @Estado);

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 150);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @Pedido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    -- Un pago por el total sin descuento, cargado fuera de usp_IniciarPago. El error
    -- del trigger deja la transacción de la sentencia sin confirmar: hay que revertirla.
    SET @Error = NULL;
    BEGIN TRY
        INSERT INTO dbo.PAGO (importe, pago_estado_id, pago_metodo_id, pedido_id)
        SELECT dbo.fn_TotalPedido(@Pedido), PGE.pago_estado_id, @Tarjeta, @Pedido
        FROM dbo.PAGO_ESTADO AS PGE
        WHERE PGE.nombre = 'Pendiente';
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('11. Pago directo por el total sin descuento', '50234', CAST(@Error AS VARCHAR(10)));

    EXEC dbo.usp_IniciarPago
        @PedidoId = @Pedido,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @Pago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SELECT @Estado = 'total ' + CAST(dbo.fn_TotalPedido(pedido_id) AS VARCHAR(20))
        + ' / ' + CAST(dbo.fn_PorcentajeDescuentoPedido(pedido_id) AS VARCHAR(10)) + ' %'
        + ' / importe ' + CAST(importe AS VARCHAR(20))
    FROM dbo.PAGO
    WHERE pago_id = @Pago;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('11. Con descuento: total, porcentaje e importe', 'total 150000.00 / 5.00 % / importe 142500.00', @Estado);

    EXEC dbo.usp_RegistrarVenta
        @PagoId = @Pago,
        @Resultado = 'Aprobado';
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoVenta @PagoId = @Pago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('11. Con descuento: venta registrada', 'Aprobado con fecha / Confirmado / stock 0 / disponible 0', @Estado),
        ('11. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));
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

-- Lote propio: corre aunque la demostración falle. Sin los usuarios no puede quedar
-- ninguna otra fila de demostración, porque las claves foráneas lo impedirían.
EXEC #LimpiarDemoVenta;

SELECT COUNT(*) AS filas_demo
FROM dbo.USUARIO
WHERE email LIKE 'demo.registrar.venta.%@example.com';

DROP PROCEDURE #LimpiarDemoVenta;
DROP PROCEDURE #CrearPublicacionDemo;
DROP PROCEDURE #EstadoDemoVenta;
GO
