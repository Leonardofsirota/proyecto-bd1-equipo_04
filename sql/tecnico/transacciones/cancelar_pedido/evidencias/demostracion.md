# Demostración de `cancelar_pedido/demostracion.sql`

- **Fecha:** 2026-11-03 11:11
- **Repetición:** 2026-11-03, enseguida y sobre la misma base: los mismos resultados, con los pedidos 607 a 612, los pagos 722 a 724 y las publicaciones 798 a 803 en lugar de 601 a 606, 719 a 721 y 792 a 797. Las dos corridas previas a las pruebas de concurrencia, cada una sobre una base recién creada, también dieron 24 de 24 con `filas_demo` en 0.
- **Base temporal:** `tmp_validacion_tx`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más `transacciones/cancelar_pedido/script.sql`
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración. La cancelación frente a una aprobación simultánea está en [`concurrencia.md`](concurrencia.md).

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 24             | 24        | 0        | 0          |

Tablas que escribe la demostración, antes y después de ejecutarla. El checksum es `CHECKSUM_AGG(BINARY_CHECKSUM(*))`, salvo en `PUBLICACION`, donde se calcula sobre `publicacion_id`, `stock` y `disponible`:

| Tabla          | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| -------------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| USUARIO        | 500         | 500           | -1321992964    | -1321992964      | 500                 | 503                   |
| DIRECCION      | 603         | 603           | -544889019     | -544889019       | 603                 | 605                   |
| PUBLICACION    | 791         | 791           | 241            | 241              | 791                 | 797                   |
| PEDIDO         | 600         | 600           | -2005910744    | -2005910744      | 600                 | 606                   |
| PEDIDO_DETALLE | 1290        | 1290          | 417360875      | 417360875        | 1290                | 1296                  |
| PAGO           | 718         | 718           | -1763708289    | -1763708289      | 718                 | 721                   |

La limpieza borra todas las filas de la demostración, y `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado`, que la limpieza deshabilita para poder borrar, quedan habilitados (`is_disabled = 0`) antes y después. `PAGO` avanza 3, por los pagos de los casos 3, 5 y 7: el intento del caso 6 falla con 50112 antes del `INSERT` y no consume ningún valor.

Las comprobaciones de estado resumen el pedido como `estado del pedido / último pago / stock real / stock libre`, donde el stock libre es `fn_StockLibre(publicación, NULL)`. Cada pedido tiene un solo renglón, de una publicación propia con stock 5.

## Caso 1: pedido Pendiente sin pagos

El cliente A pide 2 unidades de la publicación 792 (pedido 601) y lo cancela.

| pedido_id | estado_pedido | pagos_pendientes | mensaje                        |
| --------- | ------------- | ---------------- | ------------------------------ |
| 601       | Cancelado     | 0                | Pedido cancelado correctamente |

| Comprobación                            | Esperado                                 | Obtenido                                 | Resultado |
| --------------------------------------- | ---------------------------------------- | ---------------------------------------- | --------- |
| Antes: el pedido reserva 2 unidades     | Pendiente / sin pago / stock 5 / libre 3 | Pendiente / sin pago / stock 5 / libre 3 | OK        |
| Después: stock igual y reserva liberada | Cancelado / sin pago / stock 5 / libre 5 | Cancelado / sin pago / stock 5 / libre 5 | OK        |

## Caso 2: pedido con la reserva vencida

Pedido 602, de 1 unidad, con `fecha_pedido` 20 minutos atrás. Ya no reserva, pero sigue Pendiente, así que se cancela.

| Comprobación                  | Esperado                                 | Obtenido                                 | Resultado |
| ----------------------------- | ---------------------------------------- | ---------------------------------------- | --------- |
| Reserva antes de cancelar     | vencida                                  | vencida                                  | OK        |
| Antes: vencido, ya no reserva | Pendiente / sin pago / stock 5 / libre 5 | Pendiente / sin pago / stock 5 / libre 5 | OK        |
| Después                       | Cancelado / sin pago / stock 5 / libre 5 | Cancelado / sin pago / stock 5 / libre 5 | OK        |

## Caso 3: pedido con pago Pendiente

Pedido 603, de 2 unidades, con el pago 719 por tarjeta, por 2000.00. La cancelación no toca el pago: la pasarela todavía puede aprobarlo.

| pedido_id | estado_pedido | pagos_pendientes | mensaje                                                                                        |
| --------- | ------------- | ---------------- | ---------------------------------------------------------------------------------------------- |
| 603       | Cancelado     | 1                | Pedido cancelado: el pago pendiente sigue abierto y, si se aprueba, queda como cobro sin venta |

| Comprobación                   | Esperado                                                 | Obtenido                                                 | Resultado |
| ------------------------------ | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Antes                          | Pendiente / pago Pendiente sin fecha / stock 5 / libre 3 | Pendiente / pago Pendiente sin fecha / stock 5 / libre 3 | OK        |
| Después: el pago sigue abierto | Cancelado / pago Pendiente sin fecha / stock 5 / libre 5 | Cancelado / pago Pendiente sin fecha / stock 5 / libre 5 | OK        |
| Pagos Pendiente del pedido     | 1                                                        | 1                                                        | OK        |

## Caso 4: aprobación posterior del pago del caso 3

La pasarela aprueba el pago 719. `usp_RegistrarVenta` termina sin error: no hay venta, el pago queda Cancelado con fecha como rastro del cobro (RN37) y el stock no cambia.

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                                                                                                    |
| ------- | --------- | ----------- | ------------- | ---------------------------------------------------------------------------------------------------------- |
| 719     | 603       | Cancelado   | Cancelado     | Pago aprobado con el pedido fuera de Pendiente: no hay venta y la devolucion se resuelve fuera del sistema |

| Comprobación                  | Esperado                                                 | Obtenido                                                 | Resultado |
| ----------------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Error de la aprobación        | sin error                                                | sin error                                                | OK        |
| Cobro sin venta y stock igual | Cancelado / pago Cancelado con fecha / stock 5 / libre 5 | Cancelado / pago Cancelado con fecha / stock 5 / libre 5 | OK        |

## Caso 5: rechazo posterior de un pago abierto

El cliente B pide 1 unidad (pedido 604), inicia el pago 720 por transferencia y cancela el pedido, que también informa `pagos_pendientes = 1`. Después la pasarela rechaza el pago: solo cambia el pago.

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                               |
| ------- | --------- | ----------- | ------------- | ------------------------------------- |
| 720     | 604       | Rechazado   | Cancelado     | Pago actualizado: el pedido no cambia |

| Comprobación        | Esperado                                                 | Obtenido                                                 | Resultado |
| ------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Error del rechazo   | sin error                                                | sin error                                                | OK        |
| Solo cambia el pago | Cancelado / pago Rechazado sin fecha / stock 5 / libre 5 | Cancelado / pago Rechazado sin fecha / stock 5 / libre 5 | OK        |

## Caso 6: pago nuevo sobre un pedido cancelado

El cliente B intenta pagar otra vez el pedido 604.

| Comprobación                         | Esperado | Obtenido | Resultado |
| ------------------------------------ | -------- | -------- | --------- |
| Pago nuevo sobre el pedido cancelado | 50112    | 50112    | OK        |
| Pagos del pedido                     | 1        | 1        | OK        |

## Caso 7: pedido Confirmado

Pedido 605, de 2 unidades, vendido con el pago 721: `usp_RegistrarVenta` devuelve `Venta registrada correctamente` y el stock baja a 3. Un pedido Confirmado ya descontó stock y no se cancela (RN20).

| Comprobación                        | Esperado                                                 | Obtenido                                                 | Resultado |
| ----------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Antes: la venta descontó 2 unidades | Confirmado / pago Aprobado con fecha / stock 3 / libre 3 | Confirmado / pago Aprobado con fecha / stock 3 / libre 3 | OK        |
| Cancelar un pedido confirmado       | 50312                                                    | 50312                                                    | OK        |
| Después: sin cambios                | Confirmado / pago Aprobado con fecha / stock 3 / libre 3 | Confirmado / pago Aprobado con fecha / stock 3 / libre 3 | OK        |

## Caso 8: pedido Entregado

El pedido 605 pasa de Confirmado a Entregado con un `UPDATE` directo, que `trg_PEDIDO_Transicion` admite.

| Comprobación                 | Esperado                                                | Obtenido                                                | Resultado |
| ---------------------------- | ------------------------------------------------------- | ------------------------------------------------------- | --------- |
| Cancelar un pedido entregado | 50312                                                   | 50312                                                   | OK        |
| Después: sin cambios         | Entregado / pago Aprobado con fecha / stock 3 / libre 3 | Entregado / pago Aprobado con fecha / stock 3 / libre 3 | OK        |

## Caso 9: pedido ya Cancelado

El cliente A intenta cancelar otra vez el pedido 601 del caso 1.

| Comprobación       | Esperado | Obtenido | Resultado |
| ------------------ | -------- | -------- | --------- |
| Cancelar dos veces | 50312    | 50312    | OK        |

## Caso 10: pedido de otro cliente y pedido inexistente

El cliente B intenta cancelar el pedido 606, de 1 unidad, del cliente A. Después el cliente A intenta cancelar `MAX(pedido_id) + 1`, calculado justo antes de la llamada.

| Comprobación                                 | Esperado                                 | Obtenido                                 | Resultado |
| -------------------------------------------- | ---------------------------------------- | ---------------------------------------- | --------- |
| El cliente B cancela un pedido del cliente A | 50311                                    | 50311                                    | OK        |
| El pedido del cliente A sigue igual          | Pendiente / sin pago / stock 5 / libre 4 | Pendiente / sin pago / stock 5 / libre 4 | OK        |
| Pedido inexistente                           | 50311                                    | 50311                                    | OK        |

## Caso 11: transacciones abiertas

`@Abiertas` suma `@@TRANCOUNT` después de cada llamada a un procedimiento, también de las que fallaron.

| Comprobación                          | Esperado | Obtenido | Resultado |
| ------------------------------------- | -------- | -------- | --------- |
| Transacciones abiertas tras cada EXEC | 0        | 0        | OK        |
