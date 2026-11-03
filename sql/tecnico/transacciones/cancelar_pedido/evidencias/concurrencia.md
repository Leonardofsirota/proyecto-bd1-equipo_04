# Pruebas de concurrencia de `cancelar_pedido/script.sql`

- **Fecha:** 2026-11-03 11:20
- **Base temporal:** `tmp_validacion_tx`, recién cargada con la instalación completa y `transacciones/cancelar_pedido/script.sql`
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** sesiones `sqlcmd` en paralelo sobre el cliente 6 y la publicación 1 de los datos de prueba, con el stock subido a 1000. En A y B una sesión retiene la fila del pedido durante 3 segundos con un `UPDATE` sin cambios, y las dos llamadas, sincronizadas por `WAITFOR DELAY`, esperan en la cola de bloqueo de esa fila y se atienden en orden de llegada. En C no se retiene nada: las dos llamadas de cada pedido arrancan a la misma hora del servidor. Una sesión aparte mantiene la base abierta durante toda la prueba: con `AUTO_CLOSE`, activo por defecto en Express, la base se cierra al salir la última conexión, vacía su caché de planes y cada llamada recompila los procedimientos.

## Caso A: la aprobación llega primero

- **Preparación:** pedido 607 de 2 unidades con el pago Pendiente 722, publicación 1 con stock 1000; la fila del pedido queda retenida 3 s
- **Llamadas:** `usp_RegistrarVenta` Aprobado a 1,0 s y `usp_CancelarPedido` a 1,5 s
- **Esperado:** 2 sesiones bloqueadas; pago Aprobado con fecha, pedido Confirmado, stock 2 menos; aprobación sin error y cancelación con 50312
- **Obtenido:** 2 sesiones bloqueadas; pago Aprobado con fecha, pedido Confirmado, stock 2 menos; aprobación sin error y cancelación con 50312
- **Errores por número:** 50312: 1
- **Resultado:** OK

## Caso B: la cancelación llega primero

- **Preparación:** pedido 608 de 2 unidades con el pago Pendiente 723, publicación 1 con stock 998; la fila del pedido queda retenida 3 s
- **Llamadas:** `usp_CancelarPedido` a 1,0 s y `usp_RegistrarVenta` Aprobado a 1,5 s
- **Esperado:** 2 sesiones bloqueadas; pago Cancelado con fecha, pedido Cancelado, stock igual; aprobación sin error y cancelación sin error
- **Obtenido:** 2 sesiones bloqueadas; pago Cancelado con fecha, pedido Cancelado, stock igual; aprobación sin error y cancelación sin error
- **Errores por número:** ninguno
- **Resultado:** OK

## Caso C: carrera libre

- **Preparación:** 10 pedidos de 1 unidad con un pago Pendiente cada uno (609, 610, 611, 612, 613, 614, 615, 616, 617, 618); publicación 1 con stock 998
- **Llamadas:** por pedido, `usp_CancelarPedido` y `usp_RegistrarVenta` Aprobado lanzadas a la vez (20 sesiones con `WAITFOR TIME '11:20:15:600'`), sin retener
- **Esperado:** 10 pedidos coherentes, 0 mixtos, stock final igual al inicial menos los Confirmados, un error 50312 por Confirmado y ningún otro error
- **Obtenido:** 10 pedidos coherentes, 0 mixtos, stock final igual al inicial menos los Confirmados, un error 50312 por Confirmado y ningún otro error
- **Errores por número:** 50312: 5; terminaron 5 Confirmados con el pago Aprobado y 5 Cancelados con el pago Cancelado con fecha (RN37); stock de 998 a 993
- **Resultado:** OK

## Totales

- **Deadlocks registrados por el servidor durante la prueba:** 0
- **Errores fuera del `TRY` de las sesiones:** 0
- **Casos en FALLO:** 0
