USE [sistema-venta-libros];
GO

IF TYPE_ID(N'dbo.DetalleVentaType') IS NULL
BEGIN
    EXEC(N'
        CREATE TYPE dbo.DetalleVentaType AS TABLE
        (
            publicacion_id INT NOT NULL PRIMARY KEY,
            cantidad INT NOT NULL
        );
    ');
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RegistrarVenta
    @UsuarioId INT,
    @PedidoEstadoId INT,
    @CiudadId INT,
    @EnvioCalle VARCHAR(255),
    @EnvioAltura INT,
    @EnvioCodigoPostal VARCHAR(10),
    @EnvioPiso VARCHAR(50) = NULL,
    @EnvioDepartamento VARCHAR(50) = NULL,
    @EnvioReferencia VARCHAR(MAX) = NULL,
    @Detalles dbo.DetalleVentaType READONLY,
    @PedidoId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FechaPedido DATETIME = GETDATE();

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.USUARIO
        WHERE usuario_id = @UsuarioId
          AND fecha_eliminacion IS NULL
    )
        THROW 50101, 'El cliente no existe o esta eliminado.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.PEDIDO_ESTADO
        WHERE pedido_estado_id = @PedidoEstadoId
    )
        THROW 50102, 'El estado del pedido no existe.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.CIUDAD
        WHERE ciudad_id = @CiudadId
    )
        THROW 50103, 'La ciudad indicada no existe.', 1;

    IF NOT EXISTS (SELECT 1 FROM @Detalles)
        THROW 50104, 'La venta debe contener al menos un producto.', 1;

    IF EXISTS (
        SELECT 1
        FROM @Detalles
        WHERE cantidad <= 0
    )
        THROW 50105, 'Las cantidades deben ser mayores que cero.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Validar disponibilidad y bloquear las publicaciones
        -- para evitar vender existencias insuficientes.
        IF EXISTS (
            SELECT 1
            FROM @Detalles AS D
            LEFT JOIN dbo.PUBLICACION AS PUB
                WITH (UPDLOCK, HOLDLOCK)
                ON PUB.publicacion_id = D.publicacion_id
            WHERE PUB.publicacion_id IS NULL
               OR PUB.disponible = 0
               OR PUB.stock < D.cantidad
               OR PUB.fecha_eliminacion IS NOT NULL
        )
            THROW 50106,
                  'Hay productos inexistentes, no disponibles o sin stock suficiente.',
                  1;

        -- Insertar el encabezado
        INSERT INTO dbo.PEDIDO
        (
            fecha_pedido,
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
        VALUES
        (
            @FechaPedido,
            @EnvioCalle,
            @EnvioAltura,
            @EnvioPiso,
            @EnvioDepartamento,
            @EnvioCodigoPostal,
            @EnvioReferencia,
            @UsuarioId,
            @PedidoEstadoId,
            @CiudadId
        );

        SET @PedidoId = CONVERT(INT, SCOPE_IDENTITY());

        -- Insertar el detalle con el precio vigente
        INSERT INTO dbo.PEDIDO_DETALLE
        (
            cantidad,
            precio_unitario,
            pedido_id,
            publicacion_id
        )
        SELECT
            D.cantidad,
            PUB.precio,
            @PedidoId,
            D.publicacion_id
        FROM @Detalles AS D
        INNER JOIN dbo.PUBLICACION AS PUB
            ON PUB.publicacion_id = D.publicacion_id;

        -- Descontar las existencias
        UPDATE PUB
        SET PUB.stock = PUB.stock - D.cantidad
        FROM dbo.PUBLICACION AS PUB
        INNER JOIN @Detalles AS D
            ON D.publicacion_id = PUB.publicacion_id;

        COMMIT TRANSACTION;

        SELECT
            @PedidoId AS pedido_id,
            dbo.fn_TotalPedido(@PedidoId) AS total_venta,
            'Venta registrada correctamente' AS mensaje;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

SELECT TOP (10)
    usuario_id, nombre, apellido
FROM dbo.USUARIO
WHERE fecha_eliminacion IS NULL;

SELECT *
FROM dbo.PEDIDO_ESTADO;

SELECT *
FROM dbo.CIUDAD;

SELECT TOP (20)
    publicacion_id, libro_id, stock, precio, disponible
FROM dbo.PUBLICACION
WHERE disponible = 1
  AND stock > 0
  AND fecha_eliminacion IS NULL;
GO

DECLARE @Productos dbo.DetalleVentaType;
DECLARE @NuevoPedidoId INT;

-- Reemplazar 1 y 2 por publicaciones reales con stock.
INSERT INTO @Productos (publicacion_id, cantidad)
VALUES
    (1, 2),
    (2, 1);

EXEC dbo.usp_RegistrarVenta
    @UsuarioId = 1,
    @PedidoEstadoId = 1,
    @CiudadId = 1,
    @EnvioCalle = 'Calle de prueba',
    @EnvioAltura = 123,
    @EnvioCodigoPostal = '3400',
    @EnvioPiso = NULL,
    @EnvioDepartamento = NULL,
    @EnvioReferencia = 'Venta de prueba',
    @Detalles = @Productos,
    @PedidoId = @NuevoPedidoId OUTPUT;

SELECT @NuevoPedidoId AS NuevoPedidoId;
GO
