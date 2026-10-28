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