# Demostración de `auditar_pagos/demostracion.sql`

- **Fecha:** 2026-11-03 15:47
- **Repetición:** 2026-11-03, enseguida y sobre la misma base, después de la primera corrida de `auditar_usuarios`: los mismos resultados, con los usuarios 508 y 509, la publicación 794, los pedidos 605 a 607, los pagos 723 a 726 y los eventos del 38 al 54, en lugar de 501 y 502, 792, 601 a 603, 719 a 722 y del 1 al 17. Las corridas anteriores, sobre otra base, también dieron 24 de 24 con `filas_demo` en 0: las seis demostraciones de `triggers_auditoria` dos veces seguidas.
- **Base temporal:** `tmp_validacion_aud`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más los `script.sql` de las seis carpetas de `triggers_auditoria`: `estructura_auditoria`, `auditar_precio_publicacion`, `auditar_stock_publicacion`, `auditar_pedidos`, `auditar_pagos` y `auditar_usuarios`. Es la primera demostración que se ejecutó sobre esa base.
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración. El desglose de los valores IDENTITY de AUDITORIA se comprobó con una copia de la demostración que lista AUDITORIA antes de la limpieza final, ejecutada después sobre la misma base.

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 24             | 24        | 0        | 0          |

Tablas que escribe la demostración, antes y después de ejecutarla. El checksum es `CHECKSUM_AGG(BINARY_CHECKSUM(*))`:

| Tabla             | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| ----------------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| USUARIO           | 500         | 500           | -1321992964    | -1321992964      | 500                 | 502                   |
| DIRECCION         | 603         | 603           | -544889019     | -544889019       | 603                 | 604                   |
| PUBLICACION       | 791         | 791           | 1804080490     | 1804080490       | 791                 | 792                   |
| PEDIDO            | 600         | 600           | -2005910744    | -2005910744      | 600                 | 603                   |
| PEDIDO_DETALLE    | 1290        | 1290          | 417360875      | 417360875        | 1290                | 1293                  |
| PAGO              | 718         | 718           | -1763708289    | -1763708289      | 718                 | 722                   |
| AUDITORIA         | 0           | 0             | NULL           | NULL             | 1                   | 17                    |
| AUDITORIA_DETALLE | 0           | 0             | NULL           | NULL             | 1                   | 61                    |

AUDITORIA nunca había tenido filas: `IDENT_CURRENT` devuelve la semilla, 1, y el primer evento recibe el 1. La demostración usó 17 valores, del 1 al 17:

- 13 eventos confirmados. Dos de `trg_USUARIO_Auditoria`, el alta del vendedor y del cliente. Ocho de pagos: las cuatro altas y los cambios de los casos 2, 3, 4 y 5. Tres de los otros triggers: la confirmación del pedido y el descuento de stock en la venta del caso 3, y la cancelación del pedido del caso 4.
- Un valor del evento que el `ROLLBACK` del caso 6 revirtió.
- Tres eventos D de la limpieza: el borrado de la publicación y de los dos usuarios, que la limpieza después borra junto con los demás eventos.

Los casos 7 y 8 no consumieron valores. `AUDITORIA_DETALLE` avanza con un valor por columna registrada. `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado`, que la limpieza deshabilita dentro de su transacción, quedan habilitados (`is_disabled = 0`).

Datos de la demostración: el vendedor 501 y el cliente 502, con la dirección 604. El vendedor crea la publicación 792 (stock 50, 60000.00), de un libro con autor. Los pedidos los crea `usp_CrearPedido` en la sesión del cliente, y la pasarela actúa sin usuario de sesión.

Las comprobaciones de eventos resumen los eventos de un pago posteriores al inicio del paso como `operación columna: anterior a nuevo; usuario; origen`, con `-` para un usuario u origen NULL, y solo toman `estado`, `fecha_creacion`, `fecha_pago`, `importe`, `metodo` y `pedido_id`. **Login y fecha** comprueba que todos esos eventos tengan `login_bd = ORIGINAL_LOGIN()` y una fecha entre el inicio del paso y la comprobación.

## Caso 1: el cliente inicia un pago

El cliente 502 crea el pedido 601 por 2 unidades de la publicación 792: 120000.00, con un 5 % de descuento (6000.00). `usp_IniciarPago` registra el pago 719 con tarjeta de crédito por el total con descuento, 114000.00. El alta guarda el pedido, el importe, el método y el estado con que nace el pago, con el cliente como usuario.

| Comprobación                   | Esperado                                                                                                                               | Obtenido                                                                                                                               | Resultado |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Total del pedido sin descuento | 120000.00                                                                                                                              | 120000.00                                                                                                                              | OK        |
| Evento del alta                | I estado: NULL a Pendiente, importe: NULL a 114000.00, metodo: NULL a Tarjeta de crédito, pedido_id: NULL a 601; usuario 502; origen - | I estado: NULL a Pendiente, importe: NULL a 114000.00, metodo: NULL a Tarjeta de crédito, pedido_id: NULL a 601; usuario 502; origen - | OK        |
| Login y fecha                  | 1 evento; login real; fecha del paso                                                                                                   | 1 evento; login real; fecha del paso                                                                                                   | OK        |

## Caso 2: la pasarela rechaza el pago

Sin usuario de sesión, la pasarela rechaza el pago 719 con `usp_RegistrarVenta`, que devuelve `Pago actualizado: el pedido no cambia`. `trg_PAGO_Transicion` exige `fecha_pago` NULL en un pago Rechazado, así que el evento no tiene detalle de `fecha_pago`, y su fecha es la única constancia de cuándo se rechazó.

| Comprobación       | Esperado                                             | Obtenido                                             | Resultado |
| ------------------ | ---------------------------------------------------- | ---------------------------------------------------- | --------- |
| Error del rechazo  | sin error                                            | sin error                                            | OK        |
| Evento del rechazo | U estado: Pendiente a Rechazado; usuario -; origen - | U estado: Pendiente a Rechazado; usuario -; origen - | OK        |
| Login y fecha      | 1 evento; login real; fecha del paso                 | 1 evento; login real; fecha del paso                 | OK        |

## Caso 3: el cliente reintenta y la pasarela aprueba

El reintento es un pago nuevo del mismo pedido (RN23): `usp_IniciarPago` registra el pago 720 por transferencia, en la sesión del cliente. La pasarela lo aprueba, y `usp_RegistrarVenta` devuelve `Venta registrada correctamente`, con el pedido 601 Confirmado. Los dos intentos del pedido en `vw_Auditoria`, con quién inició y quién resolvió cada uno:

| auditoria_id | fecha                   | tabla | operacion | registro_id | columna    | valor_anterior | valor_nuevo             | login_bd     | usuario_id | usuario_email                              | origen |
| ------------ | ----------------------- | ----- | --------- | ----------- | ---------- | -------------- | ----------------------- | ------------ | ---------- | ------------------------------------------ | ------ |
| 3            | 2026-11-03 15:47:27.030 | PAGO  | I         | 719         | estado     | NULL           | Pendiente               | `admin\user` | 502        | demo.auditoria.auditar_pagos.2@example.com | NULL   |
| 3            | 2026-11-03 15:47:27.030 | PAGO  | I         | 719         | importe    | NULL           | 114000.00               | `admin\user` | 502        | demo.auditoria.auditar_pagos.2@example.com | NULL   |
| 3            | 2026-11-03 15:47:27.030 | PAGO  | I         | 719         | metodo     | NULL           | Tarjeta de crédito      | `admin\user` | 502        | demo.auditoria.auditar_pagos.2@example.com | NULL   |
| 3            | 2026-11-03 15:47:27.030 | PAGO  | I         | 719         | pedido_id  | NULL           | 601                     | `admin\user` | 502        | demo.auditoria.auditar_pagos.2@example.com | NULL   |
| 4            | 2026-11-03 15:47:27.117 | PAGO  | U         | 719         | estado     | Pendiente      | Rechazado               | `admin\user` | NULL       | NULL                                       | NULL   |
| 5            | 2026-11-03 15:47:27.120 | PAGO  | I         | 720         | estado     | NULL           | Pendiente               | `admin\user` | 502        | demo.auditoria.auditar_pagos.2@example.com | NULL   |
| 5            | 2026-11-03 15:47:27.120 | PAGO  | I         | 720         | importe    | NULL           | 114000.00               | `admin\user` | 502        | demo.auditoria.auditar_pagos.2@example.com | NULL   |
| 5            | 2026-11-03 15:47:27.120 | PAGO  | I         | 720         | metodo     | NULL           | Transferencia           | `admin\user` | 502        | demo.auditoria.auditar_pagos.2@example.com | NULL   |
| 5            | 2026-11-03 15:47:27.120 | PAGO  | I         | 720         | pedido_id  | NULL           | 601                     | `admin\user` | 502        | demo.auditoria.auditar_pagos.2@example.com | NULL   |
| 8            | 2026-11-03 15:47:27.200 | PAGO  | U         | 720         | estado     | Pendiente      | Aprobado                | `admin\user` | NULL       | NULL                                       | NULL   |
| 8            | 2026-11-03 15:47:27.200 | PAGO  | U         | 720         | fecha_pago | NULL           | 2026-11-03 15:47:27.120 | `admin\user` | NULL       | NULL                                       | NULL   |

El 6 y el 7 son la confirmación del pedido 601 y el descuento de stock de la publicación 792 en la misma venta: en esta corrida, `trg_PAGO_ConfirmarPedido` corrió antes que `trg_PAGO_Auditoria`. En la repetición, la aprobación del pago 724 fue el evento 43, inmediatamente después de su alta (42): el orden de los triggers hermanos no está fijado, y las comprobaciones no dependen de él.

| Comprobación           | Esperado                                                                                                                                                                                                                            | Obtenido                                                                                                                                                                                                                            | Resultado |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Error de la venta      | sin error                                                                                                                                                                                                                           | sin error                                                                                                                                                                                                                           | OK        |
| Eventos del pago nuevo | I estado: NULL a Pendiente, importe: NULL a 114000.00, metodo: NULL a Transferencia, pedido_id: NULL a 601; usuario 502; origen - / U estado: Pendiente a Aprobado, fecha_pago: NULL a 2026-11-03 15:47:27.120; usuario -; origen - | I estado: NULL a Pendiente, importe: NULL a 114000.00, metodo: NULL a Transferencia, pedido_id: NULL a 601; usuario 502; origen - / U estado: Pendiente a Aprobado, fecha_pago: NULL a 2026-11-03 15:47:27.120; usuario -; origen - | OK        |

## Caso 4: cobro sin venta

El cliente 502 crea el pedido 602 por 1 unidad, y `usp_IniciarPago` registra el pago 721 por 60000.00. El cliente cancela el pedido con un `UPDATE` directo, que deja el pago Pendiente. Después, la pasarela aprueba el pago, y `usp_RegistrarVenta` devuelve el pago y el pedido Cancelados, con el mensaje `Pago aprobado con el pedido fuera de Pendiente: no hay venta y la devolucion se resuelve fuera del sistema` (RN37). El pago Cancelado conserva `fecha_pago` como rastro del cobro, y el evento registra los dos cambios.

| Comprobación               | Esperado                                                                                         | Obtenido                                                                                         | Resultado |
| -------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | --------- |
| Error de la aprobación     | sin error                                                                                        | sin error                                                                                        | OK        |
| Evento del cobro sin venta | U estado: Pendiente a Cancelado, fecha_pago: NULL a 2026-11-03 15:47:27.220; usuario -; origen - | U estado: Pendiente a Cancelado, fecha_pago: NULL a 2026-11-03 15:47:27.220; usuario -; origen - | OK        |

## Caso 5: `fecha_creacion` 10 minutos hacia el pasado

El cliente 502 crea el pedido 603, y `usp_IniciarPago` registra el pago 722. Sin usuario de sesión, como hacen las demostraciones que simulan el paso del tiempo, su `fecha_creacion` se mueve 10 minutos hacia el pasado, lo que altera el plazo de la reserva (RN34). Es lo único, además del estado y de `fecha_pago`, que `trg_PAGO_Transicion` deja cambiar. El resumen exacto también comprueba que el evento no tiene detalle de estado.

| Comprobación               | Esperado                                                                                 | Obtenido                                                                                 | Resultado |
| -------------------------- | ---------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | --------- |
| Evento del cambio de fecha | U fecha_creacion: 2026-11-03 15:47:27.227 a 2026-11-03 15:37:27.227; usuario -; origen - | U fecha_creacion: 2026-11-03 15:47:27.227 a 2026-11-03 15:37:27.227; usuario -; origen - | OK        |

## Caso 6: rechazo revertido por el llamador

Sin usuario de sesión: `BEGIN TRANSACTION`, `usp_RegistrarVenta` rechaza el pago 722 y devuelve `Pago actualizado: el pedido no cambia`, y `ROLLBACK`. Es la única transacción externa de la demostración. El procedimiento no falla, así que su `COMMIT` interno solo baja `@@TRANCOUNT` a 1, y el `ROLLBACK` del llamador deshace el rechazo y también el evento que registró la auditoría. El valor IDENTITY que usó el evento no vuelve.

| Comprobación                | Esperado                                             | Obtenido                                             | Resultado |
| --------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | --------- |
| Dentro de la transacción    | U estado: Pendiente a Rechazado; usuario -; origen - | U estado: Pendiente a Rechazado; usuario -; origen - | OK        |
| Después del ROLLBACK        | sin eventos                                          | sin eventos                                          | OK        |
| Estado después del ROLLBACK | Pendiente                                            | Pendiente                                            | OK        |
| IDENTITY de AUDITORIA       | avanzó sin filas nuevas                              | avanzó sin filas nuevas                              | OK        |

## Caso 7: borrar un pago

Un `DELETE` del pago 722: `trg_PAGO_SinBorrado` lo rechaza con 50241 (RN29). `trg_PAGO_Auditoria` no audita DELETE, porque nunca habría un borrado confirmado que registrar: ni siquiera se dispara, y no consume un valor IDENTITY.

| Comprobación          | Esperado    | Obtenido    | Resultado |
| --------------------- | ----------- | ----------- | --------- |
| Error                 | 50241       | 50241       | OK        |
| Eventos               | sin eventos | sin eventos | OK        |
| IDENTITY de AUDITORIA | no avanzó   | no avanzó   | OK        |
| El pago sigue         | 1           | 1           | OK        |

## Caso 8: cambiar el estado del pago aprobado

Un `UPDATE` que pasa a Rechazado el pago aprobado 720: `trg_PAGO_Transicion` lo rechaza con 50222 (RN24, RN25). Es el primero de los triggers de UPDATE de PAGO (`sp_settriggerorder`), así que la auditoría no llega a correr y no consume un valor IDENTITY.

| Comprobación          | Esperado    | Obtenido    | Resultado |
| --------------------- | ----------- | ----------- | --------- |
| Error                 | 50222       | 50222       | OK        |
| Eventos               | sin eventos | sin eventos | OK        |
| IDENTITY de AUDITORIA | no avanzó   | no avanzó   | OK        |
| Estado sin cambios    | Aprobado    | Aprobado    | OK        |

## Caso 9: transacciones abiertas

`@Abiertas` suma `@@TRANCOUNT` después de las llamadas a `usp_EstablecerUsuarioSesion`, de la creación de la publicación, de los procedimientos de la venta, del `ROLLBACK` del caso 6 y de las sentencias que fallan.

| Comprobación           | Esperado | Obtenido | Resultado |
| ---------------------- | -------- | -------- | --------- |
| Transacciones abiertas | 0        | 0        | OK        |
