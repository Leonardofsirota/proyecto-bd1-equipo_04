# Convivencia de la auditoría con los triggers de consistencia

Comprueba que, con la estructura de auditoría y los cinco triggers de auditoría instalados, las pruebas anteriores del proyecto dan lo mismo, lo revertido no deja auditoría y la concurrencia no empeora. Se repitieron las mismas pruebas, con las mismas herramientas y sin cambios, y se compararon con sus resultados de referencia, obtenidos sin auditoría y documentados en la evidencia de cada script.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · todas las pruebas coinciden con la referencia · 0 errores 1205 y 0 deadlocks

## Resumen

| Paso | Qué se repitió con la auditoría                                 | Pruebas | Coinciden |
| ---- | --------------------------------------------------------------- | ------- | --------- |
| 1    | Las seis demostraciones de auditoría, una detrás de otra        | 6       | 6         |
| 2    | La demostración de la venta y los casos de los triggers         | 2       | 2         |
| 3    | La prueba de concurrencia de la venta                           | 7       | 7         |
| 4    | Las demostraciones y la prueba de concurrencia de transacciones | 7       | 7         |

En las tablas, `filas_demo` es la cantidad de filas de la demostración que quedan al terminar: 0 significa que borró todo lo que creó. El origen de un evento es el trigger de consistencia que hizo el cambio, y `-` indica un cambio directo.

## Paso 1: demostraciones de auditoría juntas

Las seis demostraciones se ejecutaron en orden sobre la misma base, con todos los objetos de auditoría instalados. Cada una dio el mismo resultado que su evidencia, y ninguna dejó filas.

| Demostración                                                                                | Resultado                | Coincide |
| ------------------------------------------------------------------------------------------- | ------------------------ | -------- |
| [`estructura_auditoria`](demostracion.md)                                                   | 9 de 9, `filas_demo` 0   | Sí       |
| [`auditar_precio_publicacion`](../../auditar_precio_publicacion/evidencias/demostracion.md) | 26 de 26, `filas_demo` 0 | Sí       |
| [`auditar_stock_publicacion`](../../auditar_stock_publicacion/evidencias/demostracion.md)   | 17 de 17, `filas_demo` 0 | Sí       |
| [`auditar_pedidos`](../../auditar_pedidos/evidencias/demostracion.md)                       | 18 de 18, `filas_demo` 0 | Sí       |
| [`auditar_pagos`](../../auditar_pagos/evidencias/demostracion.md)                           | 24 de 24, `filas_demo` 0 | Sí       |
| [`auditar_usuarios`](../../auditar_usuarios/evidencias/demostracion.md)                     | 22 de 22, `filas_demo` 0 | Sí       |

Al terminar, AUDITORIA quedó vacía y los 20 triggers, habilitados.

## Paso 2: venta y casos de los triggers

Sobre una base con los triggers de consistencia y la auditoría, se ejecutaron la demostración de [`registrar_venta`](../../../procedimientos_funciones/registrar_venta/evidencias/demostracion.md) y los casos de los triggers de consistencia de [`pruebas-validacion.md`](../../../../../docs/etapa-03/pruebas-validacion.md). La única diferencia en la salida es la cantidad de triggers habilitados: 20, los 15 de consistencia y los 5 de auditoría. Los controles de datos del final de los casos quedaron en 0.

| Prueba                            | Resultado                | Coincide |
| --------------------------------- | ------------------------ | -------- |
| Demostración de `registrar_venta` | 53 de 53, `filas_demo` 0 | Sí       |
| Casos de los triggers             | 113 de 113               | Sí       |

La demostración de la venta no limpia la auditoría, así que sus 63 eventos quedan, como se espera: PAGO 22, PEDIDO 13, PUBLICACION 19 y USUARIO 9. Los borrados entre ellos son los de la limpieza de la demostración.

Cada caso de los triggers corre en su propia transacción y se revierte. Cada evento toma un número de AUDITORIA, y el `ROLLBACK` deshace la fila pero no devuelve el número. AUDITORIA tuvo 63 filas antes y después de los casos, con el mismo checksum, y los casos consumieron 253 números de evento (459 de detalle) sin dejar filas: la auditoría corrió y la reversión la deshizo.

| Casos      | Cantidad | Consumieron números | Números consumidos |
| ---------- | -------- | ------------------- | ------------------ |
| Aceptados  | 36       | 24                  | 224                |
| Rechazados | 77       | 19                  | 29                 |

En los aceptados, los eventos se veían dentro de la transacción y desaparecieron con el `ROLLBACK`. En los rechazados, la auditoría llegó a correr antes del error, y el `ROLLBACK` la deshizo. Los 12 aceptados que no consumieron números no cambian columnas auditadas.

## Paso 3: concurrencia de la venta

Se repitió la prueba de [concurrencia de la venta](../../../procedimientos_funciones/registrar_venta/evidencias/concurrencia.md), del 2026-11-01, sobre una base recién cargada con la auditoría. Los IDs de los casos B y C no son los de la referencia porque la demostración cambió desde entonces, y la auditoría no consume valores de las tablas auditadas.

| Prueba                                                       | Resultado                                                                                                                         | Coincide |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- | -------- |
| Caso A: última unidad                                        | 1 pedido, 7 errores 50107, stock real 1                                                                                           | Sí       |
| Caso B: pagos simultáneos del mismo pedido                   | 1 pago, 7 errores 50113                                                                                                           | Sí       |
| Caso C: aprobaciones simultáneas del mismo pago              | 1 venta, 7 errores 50123, pedido Confirmado, stock 8                                                                              | Sí       |
| Caso D: operaciones mezcladas sobre las mismas publicaciones | 0 errores 1205, 0 ventas sin registrar, 0 publicaciones con stock distinto del inicial menos lo vendido; 320 pedidos y 240 ventas | Sí       |
| Caso E: sesiones con publicaciones distintas                 | 0 errores 1205, 320 ventas, 0 publicaciones con stock distinto del inicial menos lo vendido; 320 pedidos                          | Sí       |
| Deadlocks registrados por el servidor                        | 0                                                                                                                                 | Sí       |
| Errores fuera del `TRY` de las sesiones                      | 0                                                                                                                                 | Sí       |

### Coherencia de la auditoría

La prueba creó 642 pagos. Cada uno tiene exactamente un evento de alta, y cada cambio de estado, exactamente un evento. El único que queda Pendiente es el del caso B.

| Pagos      | Cantidad | Con exactamente un evento | Evento                            |
| ---------- | -------- | ------------------------- | --------------------------------- |
| Todos      | 642      | 642                       | I                                 |
| Aprobados  | 561      | 561                       | U `estado: Pendiente a Aprobado`  |
| Rechazados | 80       | 80                        | U `estado: Pendiente a Rechazado` |

Eventos de la prueba:

| Tabla       | Operación | Origen                      | Eventos |
| ----------- | --------- | --------------------------- | ------- |
| PAGO        | I         | -                           | 642     |
| PAGO        | U         | -                           | 641     |
| PEDIDO      | U         | `trg_PAGO_ConfirmarPedido`  | 561     |
| PUBLICACION | U         | -                           | 12      |
| PUBLICACION | U         | `trg_PEDIDO_DescontarStock` | 801     |

Hay una confirmación de pedido por venta (561) y un descuento de stock por renglón vendido (801), y ningún intento fallido dejó eventos: ningún pago que no terminó Aprobado tiene el evento de aprobación, y no hay eventos de pagos que no existen. Los 12 cambios de PUBLICACION sin origen son los ajustes de stock con que la prueba prepara sus casos.

## Paso 4: transacciones

Sobre una base con la instalación completa y la auditoría, se repitieron las demostraciones de [`alta_libro_con_autores`](../../../transacciones/alta_libro_con_autores/evidencias/demostracion.md) y [`cancelar_pedido`](../../../transacciones/cancelar_pedido/evidencias/demostracion.md) y la [prueba de concurrencia](../../../transacciones/cancelar_pedido/evidencias/concurrencia.md) entre la aprobación de un pago y la cancelación de su pedido.

| Prueba                                   | Resultado                                                                                                                              | Coincide |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| Demostración de `alta_libro_con_autores` | 28 de 28, `filas_demo` 0                                                                                                               | Sí       |
| Demostración de `cancelar_pedido`        | 24 de 24, `filas_demo` 0                                                                                                               | Sí       |
| Caso A: la aprobación llega primero      | 2 sesiones bloqueadas; pago Aprobado con fecha, pedido Confirmado, stock 2 menos; aprobación sin error y cancelación con 50312         | Sí       |
| Caso B: la cancelación llega primero     | 2 sesiones bloqueadas; pago Cancelado con fecha, pedido Cancelado, stock igual; aprobación sin error y cancelación sin error           | Sí       |
| Caso C: carrera libre                    | 10 pedidos coherentes, 0 mixtos, stock final igual al inicial menos los Confirmados, un error 50312 por Confirmado y ningún otro error | Sí       |
| Deadlocks registrados por el servidor    | 0                                                                                                                                      | Sí       |
| Errores fuera del `TRY` de las sesiones  | 0                                                                                                                                      | Sí       |

En el caso C, la referencia terminó con 5 pedidos Confirmados y 5 Cancelados, y esta corrida, con 3 y 7. En una carrera libre gana quien llega primero, así que el reparto no forma parte del resultado esperado: lo que se comprueba es que cada pedido termine coherente con su pago y que el stock coincida con los Confirmados.

### Coherencia de la auditoría

| Tabla  | Estado final | Cantidad | Con exactamente un evento de cada tipo | Eventos                                                                       |
| ------ | ------------ | -------- | -------------------------------------- | ----------------------------------------------------------------------------- |
| PAGO   | Aprobado     | 4        | 4                                      | I, y U `estado: Pendiente a Aprobado`                                         |
| PAGO   | Cancelado    | 8        | 8                                      | I, y U `estado: Pendiente a Cancelado`                                        |
| PEDIDO | Confirmado   | 4        | 4                                      | U `estado: Pendiente a Confirmado`, origen `trg_PAGO_ConfirmarPedido`         |
| PEDIDO | Cancelado    | 8        | 8                                      | U `estado: Pendiente a Cancelado`, sin origen: lo cambia `usp_CancelarPedido` |

No hay eventos de pagos ni de pedidos que no existen. Los otros 5 eventos son de PUBLICACION: el ajuste de stock con que la prueba prepara sus casos y los 4 descuentos de stock de las ventas, con origen `trg_PEDIDO_DescontarStock`. La prueba registró 41 eventos sin huecos, así que las cancelaciones rechazadas con 50312 no consumieron números, y las sesiones que retienen el pedido sin cambiarlo no generan eventos.

## Conclusión

Todas las pruebas coinciden con la referencia, con 0 errores 1205 y 0 deadlocks: la auditoría no cambia el resultado de las demostraciones, de los triggers de consistencia ni de la concurrencia. Los casos de los triggers no dejaron filas de auditoría, porque lo revertido se deshace junto con su evento. La auditoría de la concurrencia es coherente: cada cambio confirmado tiene su evento, y ningún intento rechazado lo tiene.
