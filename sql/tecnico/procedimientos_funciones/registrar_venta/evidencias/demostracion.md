# Demostración de `registrar_venta/script.sql`

- **Fecha:** 2026-10-31 10:02
- **Base temporal:** `tmp_validacion_rv`, recién cargada con el DDL y los datos de prueba
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso: primero lo que devuelve cada procedimiento y después las comprobaciones de `@Resultados`.

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 47             | 47        | 0        | 0          |

Datos previos a la demostración:

| Momento | Checksum de PUBLICACION | USUARIO | PEDIDO | PAGO |
| ------- | ----------------------- | ------- | ------ | ---- |
| Antes   | 241                     | 500     | 600    | 718  |
| Después | 241                     | 500     | 600    | 718  |

## Caso 1: venta exitosa con tarjeta que agota el stock

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 601       | 792            | 2        | 1000.00         | 2000.00  | 2000.00 |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 719     | 601       | 2000.00 | 2026-10-31 10:17:20.250 |

**`usp_RegistrarVenta`**

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                        |
| ------- | --------- | ----------- | ------------- | ------------------------------ |
| 719     | 601       | Aprobado    | Confirmado    | Venta registrada correctamente |

**Comprobaciones**

| Comprobación                          | Esperado                                                 | Obtenido                                                 | Resultado |
| ------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Venta exitosa                         | Aprobado con fecha / Confirmado / stock 0 / disponible 0 | Aprobado con fecha / Confirmado / stock 0 / disponible 0 | OK        |
| Transacciones abiertas tras cada EXEC | 0                                                        | 0                                                        | OK        |

## Caso 2: rechazo con reintento dentro de los 15 minutos

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 602       | 793            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 720     | 602       | 1000.00 | 2026-10-31 10:17:20.297 |

**`usp_RegistrarVenta`**

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                               |
| ------- | --------- | ----------- | ------------- | ------------------------------------- |
| 720     | 602       | Rechazado   | Pendiente     | Pago actualizado: el pedido no cambia |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 721     | 602       | 1000.00 | 2026-11-02 10:02:20.300 |

**`usp_RegistrarVenta`**

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                        |
| ------- | --------- | ----------- | ------------- | ------------------------------ |
| 721     | 602       | Aprobado    | Confirmado    | Venta registrada correctamente |

**Comprobaciones**

| Comprobación                          | Esperado                                                 | Obtenido                                                 | Resultado |
| ------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Tras el rechazo                       | Rechazado sin fecha / Pendiente / stock 3 / disponible 1 | Rechazado sin fecha / Pendiente / stock 3 / disponible 1 | OK        |
| Tras el reintento                     | Aprobado con fecha / Confirmado / stock 2 / disponible 1 | Aprobado con fecha / Confirmado / stock 2 / disponible 1 | OK        |
| Pagos en el historial del pedido      | 2                                                        | 2                                                        | OK        |
| Transacciones abiertas tras cada EXEC | 0                                                        | 0                                                        | OK        |

## Caso 3: reintento con la reserva vencida

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 603       | 794            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 722     | 603       | 1000.00 | 2026-10-31 10:17:20.310 |

**`usp_RegistrarVenta`**

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                               |
| ------- | --------- | ----------- | ------------- | ------------------------------------- |
| 722     | 603       | Rechazado   | Pendiente     | Pago actualizado: el pedido no cambia |

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 604       | 794            | 1        | 1000.00         | 1000.00  | 1000.00 |

**Comprobaciones**

| Comprobación                              | Esperado | Obtenido | Resultado |
| ----------------------------------------- | -------- | -------- | --------- |
| Reintento con la reserva vencida          | 50114    | 50114    | OK        |
| Stock libre: solo reserva el pedido nuevo | 2        | 2        | OK        |
| Transacciones abiertas tras cada EXEC     | 0        | 0        | OK        |

## Caso 4: competencia por la última unidad

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 605       | 795            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 606       | 795            | 1        | 1000.00         | 1000.00  | 1000.00 |

**Comprobaciones**

| Comprobación                            | Esperado         | Obtenido         | Resultado |
| --------------------------------------- | ---------------- | ---------------- | --------- |
| Cliente B con la unidad reservada por A | 50107            | 50107            | OK        |
| Stock con la reserva de A vigente       | real 1 / libre 0 | real 1 / libre 0 | OK        |
| Stock con la reserva de A vencida       | real 1 / libre 1 | real 1 / libre 1 | OK        |
| Stock con la reserva de B               | real 1 / libre 0 | real 1 / libre 0 | OK        |
| Transacciones abiertas tras cada EXEC   | 0                | 0                | OK        |

## Caso 5: pago ya procesado

**Comprobaciones**

| Comprobación                             | Esperado                                                 | Obtenido                                                 | Resultado |
| ---------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Segunda llamada sobre el pago del caso 1 | 50123                                                    | 50123                                                    | OK        |
| Estado sin cambios                       | Aprobado con fecha / Confirmado / stock 0 / disponible 0 | Aprobado con fecha / Confirmado / stock 0 / disponible 0 | OK        |
| Transacciones abiertas tras cada EXEC    | 0                                                        | 0                                                        | OK        |

## Caso 6: aprobación tardía con stock libre

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 607       | 796            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 723     | 607       | 1000.00 | 2026-10-31 10:17:20.343 |

**`usp_RegistrarVenta`**

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                        |
| ------- | --------- | ----------- | ------------- | ------------------------------ |
| 723     | 607       | Aprobado    | Confirmado    | Venta registrada correctamente |

**Comprobaciones**

| Comprobación                          | Esperado                                                 | Obtenido                                                 | Resultado |
| ------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Reserva antes de la aprobación        | vencida                                                  | vencida                                                  | OK        |
| Venta registrada                      | Aprobado con fecha / Confirmado / stock 0 / disponible 0 | Aprobado con fecha / Confirmado / stock 0 / disponible 0 | OK        |
| Transacciones abiertas tras cada EXEC | 0                                                        | 0                                                        | OK        |

## Caso 7: aprobación tardía sin stock libre

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 608       | 797            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 724     | 608       | 1000.00 | 2026-10-31 10:17:20.353 |

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 609       | 797            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_RegistrarVenta`**

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                                                                                   |
| ------- | --------- | ----------- | ------------- | ----------------------------------------------------------------------------------------- |
| 724     | 608       | Cancelado   | Cancelado     | Pago aprobado sin stock libre: no hay venta y la devolucion se resuelve fuera del sistema |

**Comprobaciones**

| Comprobación                          | Esperado                                                 | Obtenido                                                 | Resultado |
| ------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Error de la aprobación tardía         | sin error                                                | sin error                                                | OK        |
| Sin venta y con rastro del cobro      | Cancelado con fecha / Cancelado / stock 1 / disponible 1 | Cancelado con fecha / Cancelado / stock 1 / disponible 1 | OK        |
| Transacciones abiertas tras cada EXEC | 0                                                        | 0                                                        | OK        |

## Caso 8: aprobación con el pedido fuera de Pendiente

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 610       | 798            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 725     | 610       | 1000.00 | 2026-10-31 10:17:20.363 |

**`usp_RegistrarVenta`**

| pago_id | pedido_id | estado_pago | estado_pedido | mensaje                                                                                                    |
| ------- | --------- | ----------- | ------------- | ---------------------------------------------------------------------------------------------------------- |
| 725     | 610       | Cancelado   | Cancelado     | Pago aprobado con el pedido fuera de Pendiente: no hay venta y la devolucion se resuelve fuera del sistema |

**Comprobaciones**

| Comprobación                          | Esperado                                                 | Obtenido                                                 | Resultado |
| ------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Sin venta y con rastro del cobro      | Cancelado con fecha / Cancelado / stock 1 / disponible 1 | Cancelado con fecha / Cancelado / stock 1 / disponible 1 | OK        |
| Transacciones abiertas tras cada EXEC | 0                                                        | 0                                                        | OK        |

## Caso 9: plazos de reserva

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 611       | 799            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 726     | 611       | 1000.00 | 2026-10-31 10:17:20.373 |

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 612       | 799            | 1        | 1000.00         | 1000.00  | 1000.00 |

**`usp_IniciarPago`**

| pago_id | pedido_id | importe | vencimiento             |
| ------- | --------- | ------- | ----------------------- |
| 727     | 612       | 1000.00 | 2026-11-02 10:02:20.377 |

**`usp_CrearPedido`**

| pedido_id | publicacion_id | cantidad | precio_unitario | subtotal | total   |
| --------- | -------------- | -------- | --------------- | -------- | ------- |
| 613       | 799            | 1        | 1000.00         | 1000.00  | 1000.00 |

**Comprobaciones**

| Comprobación                                    | Esperado | Obtenido | Resultado |
| ----------------------------------------------- | -------- | -------- | --------- |
| Sin pago: minutos desde fecha_pedido            | 15       | 15       | OK        |
| Tarjeta: minutos desde la creación del pago     | 15       | 15       | OK        |
| Transferencia: horas desde la creación del pago | 48       | 48       | OK        |
| Stock libre con tres reservas vigentes          | 7        | 7        | OK        |
| Fecha futura: vencimiento de la reserva         | NULL     | NULL     | OK        |
| Fecha futura: no resta del stock libre          | 8        | 8        | OK        |
| Transacciones abiertas tras cada EXEC           | 0        | 0        | OK        |

## Caso 10: validaciones

**Comprobaciones**

| Comprobación                                     | Esperado | Obtenido | Resultado |
| ------------------------------------------------ | -------- | -------- | --------- |
| usp_CrearPedido: el usuario no es cliente        | 50101    | 50101    | OK        |
| usp_CrearPedido: dirección de otro cliente       | 50102    | 50102    | OK        |
| usp_CrearPedido: carrito vacío                   | 50103    | 50103    | OK        |
| usp_CrearPedido: cantidad cero                   | 50104    | 50104    | OK        |
| usp_CrearPedido: publicación no disponible       | 50105    | 50105    | OK        |
| usp_CrearPedido: vendedor dado de baja           | 50106    | 50106    | OK        |
| usp_CrearPedido: más unidades que el stock libre | 50107    | 50107    | OK        |
| usp_IniciarPago: método inexistente              | 50111    | 50111    | OK        |
| usp_IniciarPago: pedido no pendiente             | 50112    | 50112    | OK        |
| usp_IniciarPago: pedido con pago pendiente       | 50113    | 50113    | OK        |
| usp_IniciarPago: reserva vencida                 | 50114    | 50114    | OK        |
| usp_RegistrarVenta: resultado no válido          | 50121    | 50121    | OK        |
| usp_RegistrarVenta: pago inexistente             | 50122    | 50122    | OK        |
| usp_RegistrarVenta: pago ya procesado            | 50123    | 50123    | OK        |
| Transacciones abiertas tras cada EXEC            | 0        | 0        | OK        |
