USE [sistema-venta-libros];
GO

-- Demostración de dbo.usp_CancelarPedido (script.sql). Requiere la base instalada
-- completa, con los triggers de sql/ddl/triggers-consistencia.sql y
-- procedimientos_funciones/registrar_venta/script.sql.
-- PUBLICACION tiene un índice filtrado: sin QUOTED_IDENTIFIER, escribir en ella falla
-- con el error 1934 desde sqlcmd.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- No corre dentro de una transacción: los procedimientos confirman las suyas, y su
-- ROLLBACK anularía la externa. Crea sus propios usuarios, publicaciones, pedidos y
-- pagos, y #LimpiarDemoCancelar los borra antes y después, así que se puede ejecutar
-- varias veces sin dejar datos en la base. Lo único que no se revierte son los
-- contadores IDENTITY: cada ejecución deja un salto en los ID.
IF OBJECT_ID(N'tempdb..#LimpiarDemoCancelar', N'P') IS NOT NULL
    DROP PROCEDURE #LimpiarDemoCancelar;
GO

IF OBJECT_ID(N'tempdb..#CrearPublicacionCancelar', N'P') IS NOT NULL
    DROP PROCEDURE #CrearPublicacionCancelar;
GO

IF OBJECT_ID(N'tempdb..#EstadoDemoCancelar', N'P') IS NOT NULL
    DROP PROCEDURE #EstadoDemoCancelar;
GO

-- Borra lo que cuelga de los usuarios de demostración, en orden de dependencia.
-- Pagos y renglones no se borran en la operación normal, así que sus triggers se
-- deshabilitan solo para esta limpieza. DISABLE TRIGGER es transaccional: si algo
-- falla, XACT_ABORT revierte todo y los triggers vuelven a quedar habilitados.
CREATE PROCEDURE #LimpiarDemoCancelar
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Usuarios TABLE (usuario_id INT PRIMARY KEY);

    BEGIN TRANSACTION;

    INSERT INTO @Usuarios (usuario_id)
    SELECT usuario_id
    FROM dbo.USUARIO
    WHERE email LIKE 'demo.cancelar.pedido.%@example.com';

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
CREATE PROCEDURE #CrearPublicacionCancelar
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

-- Resume un pedido, su último pago, el stock real y el stock libre de su publicación
-- en un texto comparable. Los pedidos de la demostración tienen un solo renglón.
CREATE PROCEDURE #EstadoDemoCancelar
    @PedidoId INT,
    @Estado VARCHAR(80) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Estado = NULL;

    SELECT @Estado = PE.nombre
        + ' / ' + COALESCE(
              (
                  SELECT TOP (1)
                      'pago ' + PGE.nombre
                      + CASE WHEN PG.fecha_pago IS NULL THEN ' sin fecha' ELSE ' con fecha' END
                  FROM dbo.PAGO AS PG
                  INNER JOIN dbo.PAGO_ESTADO AS PGE
                      ON PGE.pago_estado_id = PG.pago_estado_id
                  WHERE PG.pedido_id = P.pedido_id
                  ORDER BY PG.pago_id DESC
              ),
              'sin pago')
        + ' / stock ' + CAST(PUB.stock AS VARCHAR(10))
        + ' / libre ' + CAST(dbo.fn_StockLibre(PUB.publicacion_id, NULL) AS VARCHAR(10))
    FROM dbo.PEDIDO AS P
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.pedido_estado_id = P.pedido_estado_id
    INNER JOIN dbo.PEDIDO_DETALLE AS PD
        ON PD.pedido_id = P.pedido_id
    INNER JOIN dbo.PUBLICACION AS PUB
        ON PUB.publicacion_id = PD.publicacion_id
    WHERE P.pedido_id = @PedidoId;
END;
GO

-- Con XACT_ABORT en OFF, los errores provocados no cortan el lote. El paso del
-- tiempo se simula moviendo PEDIDO.fecha_pedido hacia el pasado.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

EXEC #LimpiarDemoCancelar;

DECLARE @Resultados TABLE
(
    orden INT IDENTITY(1,1) PRIMARY KEY,
    caso VARCHAR(70) NOT NULL,
    esperado VARCHAR(80) NOT NULL,
    obtenido VARCHAR(80) NULL,
    resultado AS CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END
);

DECLARE @ClienteA INT;
DECLARE @ClienteB INT;
DECLARE @DireccionA INT;
DECLARE @DireccionB INT;
DECLARE @Vendedor INT;
DECLARE @Tarjeta INT;
DECLARE @Transferencia INT;
DECLARE @Carrito dbo.DetalleVentaType;
DECLARE @Pub INT;
DECLARE @PedidoSinPago INT;
DECLARE @PedidoVencido INT;
DECLARE @PedidoConPago INT;
DECLARE @PedidoRechazo INT;
DECLARE @PedidoConfirmado INT;
DECLARE @PedidoAjeno INT;
DECLARE @PedidoInexistente INT;
DECLARE @PagoAbierto INT;
DECLARE @PagoRechazo INT;
DECLARE @PagoAprobado INT;
DECLARE @PagoNuevo INT;
DECLARE @Antes VARCHAR(80);
DECLARE @Estado VARCHAR(80);
DECLARE @Error INT;
-- Suma @@TRANCOUNT después de cada EXEC: tiene que seguir en cero.
DECLARE @Abiertas INT = 0;

BEGIN TRY
    -- Datos propios: dos clientes con dirección y un vendedor.
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
            ('Cliente A', '99000201', 'demo.cancelar.pedido.1@example.com', 'Cliente'),
            ('Cliente B', '99000202', 'demo.cancelar.pedido.2@example.com', 'Cliente'),
            ('Vendedor', '99000203', 'demo.cancelar.pedido.3@example.com', 'Vendedor')
    ) AS D (nombre, dni, email, rol)
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.nombre = D.rol;

    SELECT @ClienteA = usuario_id FROM dbo.USUARIO WHERE dni = '99000201';
    SELECT @ClienteB = usuario_id FROM dbo.USUARIO WHERE dni = '99000202';
    SELECT @Vendedor = usuario_id FROM dbo.USUARIO WHERE dni = '99000203';

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

    -- Caso 1: el stock real no cambia, y el stock libre recupera las unidades que
    -- reservaba el pedido (RN14, RN33)
    PRINT 'Caso 1: pedido pendiente sin pagos';

    EXEC #CrearPublicacionCancelar @Vendedor = @Vendedor, @Stock = 5, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 2);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @PedidoSinPago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoSinPago, @Estado = @Antes OUTPUT;

    EXEC dbo.usp_CancelarPedido
        @PedidoId = @PedidoSinPago,
        @UsuarioId = @ClienteA;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoSinPago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('1. Antes: el pedido reserva 2 unidades', 'Pendiente / sin pago / stock 5 / libre 3', @Antes),
        ('1. Después: stock igual y reserva liberada', 'Cancelado / sin pago / stock 5 / libre 5', @Estado);

    -- Caso 2: un pedido vencido sigue Pendiente, así que también se cancela
    PRINT 'Caso 2: pedido con la reserva vencida';

    EXEC #CrearPublicacionCancelar @Vendedor = @Vendedor, @Stock = 5, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @PedidoVencido OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    UPDATE dbo.PEDIDO
    SET fecha_pedido = DATEADD(MINUTE, -20, fecha_pedido)
    WHERE pedido_id = @PedidoVencido;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoVencido, @Estado = @Antes OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
    (
        '2. Reserva antes de cancelar',
        'vencida',
        CASE WHEN dbo.fn_VencimientoReserva(@PedidoVencido) <= GETDATE() THEN 'vencida' ELSE 'vigente' END
    );

    EXEC dbo.usp_CancelarPedido
        @PedidoId = @PedidoVencido,
        @UsuarioId = @ClienteA;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoVencido, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('2. Antes: vencido, ya no reserva', 'Pendiente / sin pago / stock 5 / libre 5', @Antes),
        ('2. Después', 'Cancelado / sin pago / stock 5 / libre 5', @Estado);

    -- Caso 3: el pago Pendiente queda abierto, porque la pasarela todavía puede
    -- aprobarlo. El resultado del procedimiento informa pagos_pendientes = 1
    PRINT 'Caso 3: pedido con pago pendiente';

    EXEC #CrearPublicacionCancelar @Vendedor = @Vendedor, @Stock = 5, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 2);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @PedidoConPago OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @PedidoConPago,
        @PagoMetodoId = @Tarjeta,
        @PagoId = @PagoAbierto OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoConPago, @Estado = @Antes OUTPUT;

    EXEC dbo.usp_CancelarPedido
        @PedidoId = @PedidoConPago,
        @UsuarioId = @ClienteA;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoConPago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('3. Antes', 'Pendiente / pago Pendiente sin fecha / stock 5 / libre 3', @Antes),
        ('3. Después: el pago sigue abierto', 'Cancelado / pago Pendiente sin fecha / stock 5 / libre 5', @Estado),
        (
            '3. Pagos Pendiente del pedido',
            '1',
            (
                SELECT CAST(COUNT(*) AS VARCHAR(10))
                FROM dbo.PAGO AS PG
                INNER JOIN dbo.PAGO_ESTADO AS PGE
                    ON PGE.pago_estado_id = PG.pago_estado_id
                WHERE PG.pedido_id = @PedidoConPago
                  AND PGE.nombre = 'Pendiente'
            )
        );

    -- Caso 4: la pasarela aprueba el pago del caso 3. No hay venta: el pago queda
    -- Cancelado con fecha, como rastro del cobro, y el resultado de usp_RegistrarVenta
    -- informa la devolución (RN37)
    PRINT 'Caso 4: aprobacion posterior del pago abierto';

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarVenta
            @PagoId = @PagoAbierto,
            @Resultado = 'Aprobado';
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoConPago, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('4. Error de la aprobación', 'sin error', COALESCE(CAST(@Error AS VARCHAR(10)), 'sin error')),
        ('4. Cobro sin venta y stock igual', 'Cancelado / pago Cancelado con fecha / stock 5 / libre 5', @Estado);

    -- Caso 5: la pasarela rechaza el pago abierto de otro pedido cancelado: solo
    -- cambia el pago
    PRINT 'Caso 5: rechazo posterior del pago abierto';

    EXEC #CrearPublicacionCancelar @Vendedor = @Vendedor, @Stock = 5, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteB,
        @DireccionId = @DireccionB,
        @Carrito = @Carrito,
        @PedidoId = @PedidoRechazo OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_IniciarPago
        @PedidoId = @PedidoRechazo,
        @PagoMetodoId = @Transferencia,
        @PagoId = @PagoRechazo OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC dbo.usp_CancelarPedido
        @PedidoId = @PedidoRechazo,
        @UsuarioId = @ClienteB;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarVenta
            @PagoId = @PagoRechazo,
            @Resultado = 'Rechazado';
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoRechazo, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('5. Error del rechazo', 'sin error', COALESCE(CAST(@Error AS VARCHAR(10)), 'sin error')),
        ('5. Solo cambia el pago', 'Cancelado / pago Rechazado sin fecha / stock 5 / libre 5', @Estado);

    -- Caso 6: el cliente del caso 5 intenta pagar otra vez el pedido cancelado
    PRINT 'Caso 6: pago nuevo sobre un pedido cancelado';

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_IniciarPago
            @PedidoId = @PedidoRechazo,
            @PagoMetodoId = @Tarjeta,
            @PagoId = @PagoNuevo OUTPUT;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('6. Pago nuevo sobre el pedido cancelado', '50112', CAST(@Error AS VARCHAR(10))),
        (
            '6. Pagos del pedido',
            '1',
            (SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM dbo.PAGO WHERE pedido_id = @PedidoRechazo)
        );

    -- Caso 7: un pedido Confirmado ya descontó stock y no se cancela (RN20)
    PRINT 'Caso 7: pedido confirmado';

    EXEC #CrearPublicacionCancelar @Vendedor = @Vendedor, @Stock = 5, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 2);

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

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoConfirmado, @Estado = @Antes OUTPUT;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CancelarPedido
            @PedidoId = @PedidoConfirmado,
            @UsuarioId = @ClienteA;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoConfirmado, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('7. Antes: la venta descontó 2 unidades', 'Confirmado / pago Aprobado con fecha / stock 3 / libre 3', @Antes),
        ('7. Cancelar un pedido confirmado', '50312', CAST(@Error AS VARCHAR(10))),
        ('7. Después: sin cambios', 'Confirmado / pago Aprobado con fecha / stock 3 / libre 3', @Estado);

    -- Caso 8: el pedido del caso 7 se entrega, con un UPDATE directo que
    -- trg_PEDIDO_Transicion admite
    PRINT 'Caso 8: pedido entregado';

    UPDATE dbo.PEDIDO
    SET pedido_estado_id = (
            SELECT PE.pedido_estado_id
            FROM dbo.PEDIDO_ESTADO AS PE
            WHERE PE.nombre = 'Entregado'
        )
    WHERE pedido_id = @PedidoConfirmado;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CancelarPedido
            @PedidoId = @PedidoConfirmado,
            @UsuarioId = @ClienteA;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoConfirmado, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('8. Cancelar un pedido entregado', '50312', CAST(@Error AS VARCHAR(10))),
        ('8. Después: sin cambios', 'Entregado / pago Aprobado con fecha / stock 3 / libre 3', @Estado);

    -- Caso 9: el pedido del caso 1 ya está Cancelado
    PRINT 'Caso 9: pedido ya cancelado';

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CancelarPedido
            @PedidoId = @PedidoSinPago,
            @UsuarioId = @ClienteA;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('9. Cancelar dos veces', '50312', CAST(@Error AS VARCHAR(10)));

    -- Caso 10: solo el cliente dueño cancela su pedido (RN15)
    PRINT 'Caso 10: pedido de otro cliente y pedido inexistente';

    EXEC #CrearPublicacionCancelar @Vendedor = @Vendedor, @Stock = 5, @PublicacionId = @Pub OUTPUT;

    DELETE FROM @Carrito;
    INSERT INTO @Carrito (publicacion_id, cantidad)
    VALUES (@Pub, 1);

    EXEC dbo.usp_CrearPedido
        @UsuarioId = @ClienteA,
        @DireccionId = @DireccionA,
        @Carrito = @Carrito,
        @PedidoId = @PedidoAjeno OUTPUT;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CancelarPedido
            @PedidoId = @PedidoAjeno,
            @UsuarioId = @ClienteB;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    EXEC #EstadoDemoCancelar @PedidoId = @PedidoAjeno, @Estado = @Estado OUTPUT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('10. El cliente B cancela un pedido del cliente A', '50311', CAST(@Error AS VARCHAR(10))),
        ('10. El pedido del cliente A sigue igual', 'Pendiente / sin pago / stock 5 / libre 4', @Estado);

    -- Se calcula justo antes de usarlo: la demostración inserta pedidos.
    SELECT @PedidoInexistente = MAX(pedido_id) + 1 FROM dbo.PEDIDO;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_CancelarPedido
            @PedidoId = @PedidoInexistente,
            @UsuarioId = @ClienteA;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('10. Pedido inexistente', '50311', CAST(@Error AS VARCHAR(10)));

    -- Caso 11: ninguna llamada deja una transacción abierta, tampoco las que fallaron
    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('11. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));
END TRY
BEGIN CATCH
    -- Un error no previsto queda como FALLO: así el lote termina, se muestran los
    -- resultados y el lote siguiente limpia los datos.
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('Error no previsto', 'ninguno', LEFT(ERROR_MESSAGE(), 80));
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
EXEC #LimpiarDemoCancelar;

SELECT COUNT(*) AS filas_demo
FROM dbo.USUARIO
WHERE email LIKE 'demo.cancelar.pedido.%@example.com';

DROP PROCEDURE #LimpiarDemoCancelar;
DROP PROCEDURE #CrearPublicacionCancelar;
DROP PROCEDURE #EstadoDemoCancelar;
GO
