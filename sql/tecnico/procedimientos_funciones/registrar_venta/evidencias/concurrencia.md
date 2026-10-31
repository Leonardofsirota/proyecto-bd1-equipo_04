# Pruebas de concurrencia de `registrar_venta/script.sql`

- **Fecha:** 2026-10-31 09:44
- **Base temporal:** `tmp_validacion_rv`, recién cargada con el DDL y los datos de prueba
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** sesiones `sqlcmd` en paralelo, con las llamadas sincronizadas por `WAITFOR`. En A, B y C una sesión retiene la fila disputada durante 3 segundos.

## Caso A: última unidad

- **Preparación:** publicación 1 con stock 1; 8 sesiones bloqueadas a la espera de la fila
- **Llamadas:** 8 `usp_CrearPedido`
- **Esperado:** 1 pedido, 7 errores 50107, stock real 1
- **Obtenido:** 1 pedido, 7 errores 50107, stock real 1
- **Errores por número:** 50107: 7
- **Resultado:** OK

## Caso B: pagos simultáneos del mismo pedido

- **Preparación:** pedido Pendiente vigente 602; 8 sesiones bloqueadas a la espera de la fila
- **Llamadas:** 8 `usp_IniciarPago`
- **Esperado:** 1 pago, 7 errores 50113
- **Obtenido:** 1 pago, 7 errores 50113
- **Errores por número:** 50113: 7
- **Resultado:** OK

## Caso C: aprobaciones simultáneas del mismo pago

- **Preparación:** pago Pendiente 720 por 2 unidades, stock 10; 8 sesiones bloqueadas a la espera de la fila
- **Llamadas:** 8 `usp_RegistrarVenta` Aprobado
- **Esperado:** 1 venta, 7 errores 50123, pedido Confirmado, stock 8
- **Obtenido:** 1 venta, 7 errores 50123, pedido Confirmado, stock 8
- **Errores por número:** 50123: 7
- **Resultado:** OK

## Caso D: operaciones mezcladas sobre las mismas publicaciones

- **Preparación:** publicaciones 7 y 10 con stock 100000; pedidos con ambas
- **Llamadas:** 8 sesiones de 40 iteraciones: 4 con venta completa, 2 con rechazo y reintento, 2 con solo reservas
- **Esperado:** 0 errores 1205, 0 ventas sin registrar, 0 publicaciones con stock distinto del inicial menos lo vendido
- **Obtenido:** 0 errores 1205, 0 ventas sin registrar, 0 publicaciones con stock distinto del inicial menos lo vendido
- **Errores por número:** ninguno; 320 pedidos y 240 ventas
- **Resultado:** OK

## Caso E (adicional al plan): sesiones con publicaciones distintas

- **Preparación:** 8 publicaciones con stock 100000, una por sesión: la fila de `PUBLICACION` no serializa nada y las sesiones coinciden en `PEDIDO`, `PEDIDO_DETALLE` y `PAGO`
- **Llamadas:** 8 sesiones de 40 iteraciones con venta completa
- **Esperado:** 0 errores 1205, 320 ventas, 0 publicaciones con stock distinto del inicial menos lo vendido
- **Obtenido:** 0 errores 1205, 320 ventas, 0 publicaciones con stock distinto del inicial menos lo vendido
- **Errores por número:** ninguno; 320 pedidos
- **Resultado:** OK

## Totales

- **Deadlocks registrados por el servidor durante la prueba:** 0
- **Errores fuera del `TRY` de las sesiones:** 0
- **Casos en FALLO:** 0
