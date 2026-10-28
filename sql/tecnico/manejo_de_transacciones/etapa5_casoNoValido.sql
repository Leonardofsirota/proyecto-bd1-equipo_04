USE [sistema-venta-libros];
GO
---caso no validos
EXEC dbo.sp_crear_pedido @p_usuario_id=1, @p_ciudad_id=1, @p_envio_calle='catamarca',
@p_envio_altura='321', @p_envio_codigo_postal='5000', @p_publicacion_id=1, 
@p_cantidad=9, @p_pago_metodo_id=1;

--------control para verificar el ROLLBACK de la venta no valida por falta de stock

SELECT publicacion_id, stock FROM PUBLICACION WHERE publicacion_id = 1;
SELECT TOP 1 * FROM PEDIDO ORDER BY pedido_id DESC;
SELECT TOP 1 * FROM PEDIDO_DETALLE ORDER BY pedido_detalle_id DESC;
SELECT TOP 1 * FROM PAGO ORDER BY pago_id DESC;
