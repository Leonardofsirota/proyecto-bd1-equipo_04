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

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
