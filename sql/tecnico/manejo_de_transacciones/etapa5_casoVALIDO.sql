
USE [sistema-venta-libros];
GO
-----verifar datos de las tablas antes de la ejecucion de la venta
SELECT TOP 3 usuario_id, nombre FROM USUARIO WHERE fecha_eliminacion IS NULL;
SELECT TOP 3 ciudad_id, nombre FROM CIUDAD;
SELECT TOP 3 publicacion_id, stock, precio, disponible FROM PUBLICACION 
     WHERE fecha_eliminacion IS NULL AND disponible = 1 AND stock > 0;
SELECT * FROM PAGO_METODO;
SELECT * FROM PEDIDO_ESTADO;
-----------------------------------------------------------------------
-- CONTROL ANTES
SELECT publicacion_id, stock FROM PUBLICACION WHERE publicacion_id = 1;

-- EJECUTO PROCEDIMIENTO
EXEC dbo.sp_crear_pedido 
    @p_usuario_id = 1, 
    @p_ciudad_id = 1, 
    @p_envio_calle = 'San Martin',
    @p_envio_altura = '123',
    @p_envio_codigo_postal = '5000',
    @p_publicacion_id = 1,
    @p_cantidad = 1,
    @p_pago_metodo_id = 1;

-- CONTROL DESPUES
SELECT publicacion_id, stock FROM PUBLICACION WHERE publicacion_id = 1;
SELECT TOP 1 * FROM PEDIDO ORDER BY pedido_id DESC;
SELECT TOP 1 * FROM PEDIDO_DETALLE ORDER BY pedido_detalle_id DESC;
SELECT TOP 1 * FROM PAGO ORDER BY pago_id DESC;
