USE [sistema-venta-libros];
GO

CREATE OR ALTER PROCEDURE sp_crear_pedido
    @p_usuario_id INT,
    @p_ciudad_id INT,
    @p_envio_calle NVARCHAR(255),
    @p_envio_altura NVARCHAR(20),
    @p_envio_codigo_postal NVARCHAR(20),
    @p_publicacion_id INT,
    @p_cantidad INT,
    @p_pago_metodo_id INT,
    @p_envio_piso NVARCHAR(20) = NULL,
    @p_envio_departamento NVARCHAR(20) = NULL,
    @p_envio_referencia NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_precio DECIMAL(10,2);
    DECLARE @v_stock INT;
    DECLARE @v_disponible BIT;
    DECLARE @v_pedido_id INT;
    DECLARE @v_importe DECIMAL(10,2);
    DECLARE @v_pedido_estado_id INT;
    DECLARE @v_pago_estado_id INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @p_cantidad IS NULL OR @p_cantidad <= 0
        BEGIN
            RAISERROR('ERROR: La cantidad debe ser mayor a 0', 16, 1);
        END

        IF NOT EXISTS (SELECT 1 FROM USUARIO WHERE usuario_id = @p_usuario_id AND fecha_eliminacion IS NULL)
        BEGIN
            RAISERROR('ERROR: Usuario inexistente o eliminado', 16, 1);
        END

        IF NOT EXISTS (SELECT 1 FROM CIUDAD WHERE ciudad_id = @p_ciudad_id)
        BEGIN
            RAISERROR('ERROR: Ciudad inexistente', 16, 1);
        END

        SELECT @v_precio = precio, @v_stock = stock, @v_disponible = disponible
        FROM PUBLICACION WITH (UPDLOCK, ROWLOCK)
        WHERE publicacion_id = @p_publicacion_id AND fecha_eliminacion IS NULL;

        IF @v_precio IS NULL
        BEGIN
            RAISERROR('ERROR: Publicacion inexistente o eliminada', 16, 1);
        END

        IF @v_disponible = 0
        BEGIN
            RAISERROR('ERROR: Publicacion no disponible', 16, 1);
        END

        IF @v_stock < @p_cantidad
        BEGIN
            RAISERROR('ERROR: Stock insuficiente', 16, 1);
        END

        SELECT TOP 1 @v_pedido_estado_id = pedido_estado_id FROM PEDIDO_ESTADO WHERE nombre = 'Pendiente';
        IF @v_pedido_estado_id IS NULL SET @v_pedido_estado_id = 1;

        SELECT TOP 1 @v_pago_estado_id = pago_estado_id FROM PAGO_ESTADO WHERE nombre = 'Pendiente';
        IF @v_pago_estado_id IS NULL SET @v_pago_estado_id = 1;

        INSERT INTO PEDIDO (fecha_pedido, envio_calle, envio_altura, envio_piso, envio_departamento, envio_codigo_postal, envio_referencia, usuario_id, pedido_estado_id, ciudad_id)
        VALUES (GETDATE(), @p_envio_calle, @p_envio_altura, @p_envio_piso, @p_envio_departamento, @p_envio_codigo_postal, @p_envio_referencia, @p_usuario_id, @v_pedido_estado_id, @p_ciudad_id);
        
        SET @v_pedido_id = SCOPE_IDENTITY();
        SET @v_importe = @v_precio * @p_cantidad;

        INSERT INTO PEDIDO_DETALLE (cantidad, precio_unitario, pedido_id, publicacion_id)
        VALUES (@p_cantidad, @v_precio, @v_pedido_id, @p_publicacion_id);

        UPDATE PUBLICACION SET stock = stock - @p_cantidad WHERE publicacion_id = @p_publicacion_id;

        INSERT INTO PAGO (importe, fecha_creacion, pago_estado_id, pago_metodo_id, pedido_id)
        VALUES (@v_importe, GETDATE(), @v_pago_estado_id, @p_pago_metodo_id, @v_pedido_id);

        COMMIT TRANSACTION;

        SELECT CONCAT('PEDIDO CREADO OK - ID: ', @v_pedido_id, ' IMPORTE: ', @v_importe) AS Resultado;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Esto devuelve el error real
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH
END
GO
