USE [sistema-venta-libros];
GO

-- Quedan registradas en cada objeto. Sin QUOTED_IDENTIFIER, el UPDATE sobre
-- PUBLICACION falla con el error 1934 desde sqlcmd, porque la tabla tiene un
-- índice filtrado.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- dbo.fn_TotalPedido se crea en calcular_descuento_pedido/script.sql.
-- SET NOEXEC ON hace que los lotes siguientes se compilen sin ejecutarse.
IF OBJECT_ID(N'dbo.fn_TotalPedido', N'FN') IS NULL
BEGIN
    RAISERROR(N'Falta dbo.fn_TotalPedido: ejecutar antes calcular_descuento_pedido/script.sql. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Se eliminan antes de crear el tipo porque usp_CrearPedido depende de él.
IF OBJECT_ID(N'dbo.usp_RegistrarVenta', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_RegistrarVenta;
GO

IF OBJECT_ID(N'dbo.usp_IniciarPago', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_IniciarPago;
GO

IF OBJECT_ID(N'dbo.usp_CrearPedido', N'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_CrearPedido;
GO

IF OBJECT_ID(N'dbo.fn_StockLibre', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_StockLibre;
GO

IF OBJECT_ID(N'dbo.fn_VencimientoReserva', N'FN') IS NOT NULL
    DROP FUNCTION dbo.fn_VencimientoReserva;
GO

-- Carrito de un pedido: una fila por publicación. Un parámetro con valores de
-- tabla es la única forma de pasarlo en SQL Server 2012.
IF TYPE_ID(N'dbo.DetalleVentaType') IS NULL
    CREATE TYPE dbo.DetalleVentaType AS TABLE
    (
        publicacion_id INT NOT NULL PRIMARY KEY,
        cantidad INT NOT NULL
    );
GO

-- Devuelve hasta cuándo reserva unidades un pedido. La vigencia se calcula al
-- consultar: un pedido vencido sigue Pendiente, pero deja de reservar.
-- Con un pago Pendiente, el plazo corre desde la creación de ese pago: 48 horas
-- por transferencia y 15 minutos con otro método. Sin pago Pendiente, son 15
-- minutos desde fecha_pedido.
-- Devuelve NULL si el pedido no existe, no está Pendiente o tiene fecha futura.
CREATE FUNCTION dbo.fn_VencimientoReserva
(
    @PedidoId INT
)
RETURNS DATETIME
AS
BEGIN
    DECLARE @FechaPedido DATETIME;
    DECLARE @FechaPago DATETIME;
    DECLARE @Metodo VARCHAR(50);

    SELECT @FechaPedido = P.fecha_pedido
    FROM dbo.PEDIDO AS P
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.pedido_estado_id = P.pedido_estado_id
    WHERE P.pedido_id = @PedidoId
      AND PE.nombre = 'Pendiente';

    IF @FechaPedido IS NULL OR @FechaPedido > GETDATE()
        RETURN NULL;

    SELECT TOP (1)
        @FechaPago = PG.fecha_creacion,
        @Metodo = PM.nombre
    FROM dbo.PAGO AS PG
    INNER JOIN dbo.PAGO_ESTADO AS PGE
        ON PGE.pago_estado_id = PG.pago_estado_id
    INNER JOIN dbo.PAGO_METODO AS PM
        ON PM.pago_metodo_id = PG.pago_metodo_id
    WHERE PG.pedido_id = @PedidoId
      AND PGE.nombre = 'Pendiente'
    ORDER BY PG.pago_id DESC;

    IF @FechaPago IS NULL
        RETURN DATEADD(MINUTE, 15, @FechaPedido);

    IF @Metodo = 'Transferencia'
        RETURN DATEADD(HOUR, 48, @FechaPago);

    RETURN DATEADD(MINUTE, 15, @FechaPago);
END;
GO

-- Devuelve el stock real de una publicación menos las reservas vigentes de otros
-- pedidos. @PedidoExcluido es el pedido que ya es dueño de su reserva; con NULL
-- no se excluye ninguno. Devuelve NULL si la publicación no existe.
-- También la usan ofertas-vigentes-por-libro.sql y buscar-libros-catalogo.sql
-- (sql/consultas/cliente).
CREATE FUNCTION dbo.fn_StockLibre
(
    @PublicacionId INT,
    @PedidoExcluido INT
)
RETURNS INT
AS
BEGIN
    DECLARE @Stock INT;
    DECLARE @Reservado INT;

    SELECT @Stock = stock
    FROM dbo.PUBLICACION
    WHERE publicacion_id = @PublicacionId;

    IF @Stock IS NULL
        RETURN NULL;

    SELECT @Reservado = COALESCE(SUM(PD.cantidad), 0)
    FROM dbo.PEDIDO_DETALLE AS PD
    WHERE PD.publicacion_id = @PublicacionId
      AND (@PedidoExcluido IS NULL OR PD.pedido_id <> @PedidoExcluido)
      AND dbo.fn_VencimientoReserva(PD.pedido_id) > GETDATE();

    RETURN @Stock - @Reservado;
END;
GO

-- Los tres procedimientos usan transacciones breves y bloquean en el mismo orden:
-- PEDIDO, PAGO y PUBLICACION, con las publicaciones en publicacion_id ascendente.
-- Primero bloquean y validan, y recién después escriben: quien escribe en PAGO y
-- luego espera una PUBLICACION se bloquea mutuamente con usp_CrearPedido, que
-- tiene la publicación y lee PAGO. La fila de PEDIDO serializa los pagos de ese
-- pedido, y la de PUBLICACION serializa las reservas.

-- 1. CREAR el pedido
-- Valida al cliente, su dirección y el carrito, y crea el pedido Pendiente con el
-- precio vigente y una copia de la dirección. No descuenta stock: el pedido reserva
-- unidades durante el plazo de dbo.fn_VencimientoReserva. Devuelve un renglón por
-- publicación, con su subtotal y el total del pedido.
CREATE PROCEDURE dbo.usp_CrearPedido
    @UsuarioId INT,
    @DireccionId INT,
    @Carrito dbo.DetalleVentaType READONLY,
    @PedidoId INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Pub INT = 0;
    DECLARE @Bloqueo INT;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.USUARIO AS U
        INNER JOIN dbo.USUARIO_ROL AS UR
            ON UR.usuario_rol_id = U.usuario_rol_id
        WHERE U.usuario_id = @UsuarioId
          AND U.fecha_eliminacion IS NULL
          AND UR.nombre = 'Cliente'
    )
        THROW 50101, 'El usuario no existe, esta eliminado o no es cliente.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.DIRECCION
        WHERE direccion_id = @DireccionId
          AND usuario_id = @UsuarioId
    )
        THROW 50102, 'La direccion no existe o no pertenece al cliente.', 1;

    IF NOT EXISTS (SELECT 1 FROM @Carrito)
        THROW 50103, 'El carrito esta vacio.', 1;

    IF EXISTS (
        SELECT 1
        FROM @Carrito
        WHERE cantidad <= 0
    )
        THROW 50104, 'Las cantidades deben ser mayores que cero.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Una por vez y en orden ascendente: un JOIN con UPDLOCK no garantiza el
        -- orden de los bloqueos.
        WHILE 1 = 1
        BEGIN
            SELECT @Pub = MIN(publicacion_id)
            FROM @Carrito
            WHERE publicacion_id > @Pub;

            IF @Pub IS NULL
                BREAK;

            SELECT @Bloqueo = 1
            FROM dbo.PUBLICACION WITH (UPDLOCK, ROWLOCK)
            WHERE publicacion_id = @Pub;
        END;

        IF EXISTS (
            SELECT 1
            FROM @Carrito AS C
            LEFT JOIN dbo.PUBLICACION AS PUB
                ON PUB.publicacion_id = C.publicacion_id
            WHERE PUB.publicacion_id IS NULL
               OR PUB.disponible = 0
               OR PUB.fecha_eliminacion IS NOT NULL
        )
            THROW 50105,
                  'Hay publicaciones inexistentes, no disponibles o dadas de baja.',
                  1;

        IF EXISTS (
            SELECT 1
            FROM @Carrito AS C
            INNER JOIN dbo.PUBLICACION AS PUB
                ON PUB.publicacion_id = C.publicacion_id
            INNER JOIN dbo.USUARIO AS V
                ON V.usuario_id = PUB.usuario_id
            WHERE V.fecha_eliminacion IS NOT NULL
        )
            THROW 50106, 'Hay publicaciones de un vendedor dado de baja.', 1;

        IF EXISTS (
            SELECT 1
            FROM @Carrito AS C
            WHERE dbo.fn_StockLibre(C.publicacion_id, NULL) < C.cantidad
        )
            THROW 50107, 'No hay stock libre suficiente.', 1;

        INSERT INTO dbo.PEDIDO
        (
            envio_calle,
            envio_altura,
            envio_piso,
            envio_departamento,
            envio_codigo_postal,
            envio_referencia,
            usuario_id,
            pedido_estado_id,
            ciudad_id
        )
        SELECT
            D.calle,
            D.altura,
            D.piso,
            D.departamento,
            D.codigo_postal,
            D.referencia,
            D.usuario_id,
            PE.pedido_estado_id,
            D.ciudad_id
        FROM dbo.DIRECCION AS D
        INNER JOIN dbo.PEDIDO_ESTADO AS PE
            ON PE.nombre = 'Pendiente'
        WHERE D.direccion_id = @DireccionId;

        SET @PedidoId = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO dbo.PEDIDO_DETALLE
        (
            cantidad,
            precio_unitario,
            pedido_id,
            publicacion_id
        )
        SELECT
            C.cantidad,
            PUB.precio,
            @PedidoId,
            C.publicacion_id
        FROM @Carrito AS C
        INNER JOIN dbo.PUBLICACION AS PUB
            ON PUB.publicacion_id = C.publicacion_id;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;

    SELECT
        PD.pedido_id,
        PD.publicacion_id,
        PD.cantidad,
        PD.precio_unitario,
        PD.cantidad * PD.precio_unitario AS subtotal,
        dbo.fn_TotalPedido(PD.pedido_id) AS total
    FROM dbo.PEDIDO_DETALLE AS PD
    WHERE PD.pedido_id = @PedidoId
    ORDER BY PD.publicacion_id;
END;
GO

-- 2. INICIAR el pago
-- Registra un pago Pendiente por el total de un pedido Pendiente con la reserva
-- vigente y sin otro pago Pendiente o Aprobado. El pago amplía la reserva, así que
-- también toma las publicaciones del pedido. Devuelve el ID del pago, su importe y
-- el vencimiento de la reserva.
CREATE PROCEDURE dbo.usp_IniciarPago
    @PedidoId INT,
    @PagoMetodoId INT,
    @PagoId INT = NULL OUTPUT,
    @Vencimiento DATETIME = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoPedido VARCHAR(50);
    DECLARE @Reserva DATETIME;
    DECLARE @Importe DECIMAL(18, 2);
    DECLARE @Pub INT = 0;
    DECLARE @Bloqueo INT;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.PAGO_METODO
        WHERE pago_metodo_id = @PagoMetodoId
    )
        THROW 50111, 'El metodo de pago no existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @EstadoPedido = PE.nombre
        FROM dbo.PEDIDO AS P WITH (UPDLOCK, ROWLOCK)
        INNER JOIN dbo.PEDIDO_ESTADO AS PE
            ON PE.pedido_estado_id = P.pedido_estado_id
        WHERE P.pedido_id = @PedidoId;

        IF @EstadoPedido IS NULL OR @EstadoPedido <> 'Pendiente'
            THROW 50112, 'El pedido no existe o no esta pendiente.', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.PAGO AS PG
            INNER JOIN dbo.PAGO_ESTADO AS PGE
                ON PGE.pago_estado_id = PG.pago_estado_id
            WHERE PG.pedido_id = @PedidoId
              AND PGE.nombre IN ('Pendiente', 'Aprobado')
        )
            THROW 50113, 'El pedido ya tiene un pago pendiente o aprobado.', 1;

        WHILE 1 = 1
        BEGIN
            SELECT @Pub = MIN(publicacion_id)
            FROM dbo.PEDIDO_DETALLE
            WHERE pedido_id = @PedidoId
              AND publicacion_id > @Pub;

            IF @Pub IS NULL
                BREAK;

            SELECT @Bloqueo = 1
            FROM dbo.PUBLICACION WITH (UPDLOCK, ROWLOCK)
            WHERE publicacion_id = @Pub;
        END;

        -- Se comprueba con las publicaciones bloqueadas: antes, la reserva podría
        -- vencer durante la espera y otro pedido podría tomar esas unidades.
        SET @Reserva = dbo.fn_VencimientoReserva(@PedidoId);

        IF @Reserva IS NULL OR @Reserva <= GETDATE()
            THROW 50114, 'La reserva del pedido vencio: debe crear un pedido nuevo.', 1;

        SET @Importe = dbo.fn_TotalPedido(@PedidoId);

        INSERT INTO dbo.PAGO
        (
            importe,
            pago_estado_id,
            pago_metodo_id,
            pedido_id
        )
        SELECT
            @Importe,
            PGE.pago_estado_id,
            @PagoMetodoId,
            @PedidoId
        FROM dbo.PAGO_ESTADO AS PGE
        WHERE PGE.nombre = 'Pendiente';

        SET @PagoId = CAST(SCOPE_IDENTITY() AS INT);
        SET @Vencimiento = dbo.fn_VencimientoReserva(@PedidoId);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;

    SELECT
        @PagoId AS pago_id,
        @PedidoId AS pedido_id,
        @Importe AS importe,
        @Vencimiento AS vencimiento;
END;
GO

-- 3. REGISTRAR el resultado del pago
-- Procesa un pago Pendiente. Un pago Rechazado o Cancelado solo cambia el pago: el
-- pedido sigue Pendiente y el cliente puede reintentar si la reserva sigue vigente.
-- Un pago Aprobado concreta la venta si hay stock libre para todo el pedido, aunque
-- la aprobación llegue tarde: confirma el pedido, descuenta el stock y marca
-- disponible = 0 en las publicaciones que llegan a cero.
-- Un pago Aprobado sin stock libre o con el pedido fuera de Pendiente no es una
-- venta: el pago queda Cancelado con fecha_pago, como rastro del cobro, y un pedido
-- Pendiente pasa a Cancelado. Termina en COMMIT y sin error, porque un ROLLBACK
-- perdería ese rastro. Devuelve los estados finales y un mensaje.
CREATE PROCEDURE dbo.usp_RegistrarVenta
    @PagoId INT,
    @Resultado VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @PedidoId INT;
    DECLARE @EstadoPago VARCHAR(50);
    DECLARE @EstadoPedido VARCHAR(50);
    DECLARE @NuevoEstadoPago VARCHAR(50) = @Resultado;
    DECLARE @NuevoEstadoPedido VARCHAR(50);
    DECLARE @FechaPago DATETIME = NULL;
    DECLARE @Mensaje VARCHAR(200);
    DECLARE @Pub INT = 0;
    DECLARE @Bloqueo INT;

    IF @Resultado IS NULL
       OR @Resultado NOT IN ('Aprobado', 'Rechazado', 'Cancelado')
        THROW 50121, 'El resultado debe ser Aprobado, Rechazado o Cancelado.', 1;

    -- Sin bloqueo: el pedido de un pago no cambia.
    SELECT @PedidoId = pedido_id
    FROM dbo.PAGO
    WHERE pago_id = @PagoId;

    IF @PedidoId IS NULL
        THROW 50122, 'El pago no existe.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @EstadoPedido = PE.nombre
        FROM dbo.PEDIDO AS P WITH (UPDLOCK, ROWLOCK)
        INNER JOIN dbo.PEDIDO_ESTADO AS PE
            ON PE.pedido_estado_id = P.pedido_estado_id
        WHERE P.pedido_id = @PedidoId;

        SELECT @EstadoPago = PGE.nombre
        FROM dbo.PAGO AS PG WITH (UPDLOCK, ROWLOCK)
        INNER JOIN dbo.PAGO_ESTADO AS PGE
            ON PGE.pago_estado_id = PG.pago_estado_id
        WHERE PG.pago_id = @PagoId;

        IF @EstadoPago <> 'Pendiente'
            THROW 50123, 'El pago ya fue procesado.', 1;

        SET @NuevoEstadoPedido = @EstadoPedido;
        SET @Mensaje = 'Pago actualizado: el pedido no cambia';

        IF @Resultado = 'Aprobado'
        BEGIN
            SET @FechaPago = GETDATE();

            IF @EstadoPedido <> 'Pendiente'
            BEGIN
                SET @NuevoEstadoPago = 'Cancelado';
                SET @Mensaje = 'Pago aprobado con el pedido fuera de Pendiente: '
                             + 'no hay venta y la devolucion se resuelve fuera del sistema';
            END
            ELSE
            BEGIN
                WHILE 1 = 1
                BEGIN
                    SELECT @Pub = MIN(publicacion_id)
                    FROM dbo.PEDIDO_DETALLE
                    WHERE pedido_id = @PedidoId
                      AND publicacion_id > @Pub;

                    IF @Pub IS NULL
                        BREAK;

                    SELECT @Bloqueo = 1
                    FROM dbo.PUBLICACION WITH (UPDLOCK, ROWLOCK)
                    WHERE publicacion_id = @Pub;
                END;

                -- El vencimiento de la reserva no se comprueba: una aprobación
                -- tardía es válida si hay stock libre.
                IF EXISTS (
                    SELECT 1
                    FROM dbo.PEDIDO_DETALLE AS PD
                    WHERE PD.pedido_id = @PedidoId
                      AND dbo.fn_StockLibre(PD.publicacion_id, @PedidoId) < PD.cantidad
                )
                BEGIN
                    SET @NuevoEstadoPago = 'Cancelado';
                    SET @NuevoEstadoPedido = 'Cancelado';
                    SET @Mensaje = 'Pago aprobado sin stock libre: '
                                 + 'no hay venta y la devolucion se resuelve fuera del sistema';
                END
                ELSE
                BEGIN
                    SET @NuevoEstadoPedido = 'Confirmado';
                    SET @Mensaje = 'Venta registrada correctamente';
                END;
            END;
        END;

        UPDATE dbo.PAGO
        SET pago_estado_id = (
                SELECT PGE.pago_estado_id
                FROM dbo.PAGO_ESTADO AS PGE
                WHERE PGE.nombre = @NuevoEstadoPago
            ),
            fecha_pago = @FechaPago
        WHERE pago_id = @PagoId;

        IF @NuevoEstadoPedido <> @EstadoPedido
            UPDATE dbo.PEDIDO
            SET pedido_estado_id = (
                    SELECT PE.pedido_estado_id
                    FROM dbo.PEDIDO_ESTADO AS PE
                    WHERE PE.nombre = @NuevoEstadoPedido
                )
            WHERE pedido_id = @PedidoId;

        -- FORCESEEK evita un recorrido de PUBLICACION, que chocaría con las filas
        -- que tienen tomadas otros pedidos.
        IF @NuevoEstadoPago = 'Aprobado'
            UPDATE PUB
            SET PUB.stock = PUB.stock - PD.cantidad,
                PUB.disponible = CASE
                                     WHEN PUB.stock = PD.cantidad THEN 0
                                     ELSE PUB.disponible
                                 END
            FROM dbo.PUBLICACION AS PUB WITH (ROWLOCK, FORCESEEK)
            INNER JOIN dbo.PEDIDO_DETALLE AS PD
                ON PD.publicacion_id = PUB.publicacion_id
            WHERE PD.pedido_id = @PedidoId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;

    SELECT
        PG.pago_id,
        PG.pedido_id,
        PGE.nombre AS estado_pago,
        PE.nombre AS estado_pedido,
        @Mensaje AS mensaje
    FROM dbo.PAGO AS PG
    INNER JOIN dbo.PAGO_ESTADO AS PGE
        ON PGE.pago_estado_id = PG.pago_estado_id
    INNER JOIN dbo.PEDIDO AS P
        ON P.pedido_id = PG.pedido_id
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.pedido_estado_id = P.pedido_estado_id
    WHERE PG.pago_id = @PagoId;
END;
GO

-- Demostración. A diferencia de abm_categorias, no corre dentro de una transacción:
-- los procedimientos confirman las suyas, y su ROLLBACK anularía la externa. Crea
-- sus propios usuarios, publicaciones, pedidos y pagos, y #LimpiarDemoVenta los
-- borra antes y después, así que se puede ejecutar varias veces sin dejar datos en
-- la base. Lo único que no se revierte son los contadores IDENTITY: cada ejecución
-- deja un salto en los ID.
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
CREATE PROCEDURE #LimpiarDemoVenta
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Usuarios TABLE (usuario_id INT PRIMARY KEY);

    INSERT INTO @Usuarios (usuario_id)
    SELECT usuario_id
    FROM dbo.USUARIO
    WHERE email LIKE 'demo.registrar.venta.%@example.com';

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
    -- Datos propios: dos clientes con dirección, un vendedor activo y uno dado de baja
    INSERT INTO dbo.USUARIO
    (
        nombre,
        apellido,
        dni,
        email,
        telefono,
        fecha_nacimiento,
        password_hash,
        fecha_eliminacion,
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
        D.fecha_eliminacion,
        UR.usuario_rol_id
    FROM
    (
        VALUES
            ('Cliente A', '99000001', 'demo.registrar.venta.1@example.com', 'Cliente', NULL),
            ('Cliente B', '99000002', 'demo.registrar.venta.2@example.com', 'Cliente', NULL),
            ('Vendedor', '99000003', 'demo.registrar.venta.3@example.com', 'Vendedor', NULL),
            ('Vendedor baja', '99000004', 'demo.registrar.venta.4@example.com', 'Vendedor', GETDATE())
    ) AS D (nombre, dni, email, rol, fecha_eliminacion)
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

    -- Error 50106: el vendedor de la publicación está dado de baja
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
    VALUES ('10. usp_CrearPedido: vendedor dado de baja', '50106', CAST(@Error AS VARCHAR(10)));

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

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
