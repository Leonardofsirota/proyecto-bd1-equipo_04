# Convivencia de la auditoría con los triggers de consistencia

- **Fecha:** 2026-11-03, de 15:55 a 16:01
- **Bases temporales:** `tmp_validacion_aud` (paso 1), `tmp_validacion_rv` (pasos 2 y 3, recreada entre los dos) y `tmp_validacion_tx` (paso 4). Cada una se cargó con su herramienta, sin cambios, y antes de cualquier prueba se instalaron los `script.sql` de las seis carpetas de `triggers_auditoria`: `estructura_auditoria`, `auditar_precio_publicacion`, `auditar_stock_publicacion`, `auditar_pedidos`, `auditar_pagos` y `auditar_usuarios`. Las tres quedaron borradas al final.
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** las mismas herramientas que dieron los resultados de referencia, sin cambios: `tools/validar-registrar-venta/validar.sh` (`aplicar` y `casos`) y `concurrencia.sh`, y `tools/validar-transacciones/validar.sh` y `concurrencia.sh`. La auditoría se instaló con `tools/validar-auditoria/validar.sh instalar`. Los dos `concurrencia.sh` escribieron su informe fuera del repositorio (variable `EVIDENCIA`): `registrar_venta/evidencias/concurrencia.md` y `cancelar_pedido/evidencias/concurrencia.md` no cambiaron (`git status` sin cambios). Los conteos de AUDITORIA y las comprobaciones de coherencia salen de consultas aparte, ejecutadas entre los pasos. Los resultados de referencia son los de las evidencias de cada script, obtenidos sin auditoría.

## Resumen

Todas las pruebas dieron los resultados de referencia, con 0 errores 1205 y 0 deadlocks registrados por el servidor. Los casos de los triggers de consistencia, que se revierten uno por uno, consumieron 253 valores de AUDITORIA sin dejar filas. En las dos pruebas de concurrencia, cada pago tiene exactamente un evento de alta y uno por cada cambio de estado, y ningún intento rechazado dejó eventos. No hubo que corregir nada.

## Paso 1: demostraciones de auditoría juntas

Las seis demostraciones, en este orden, sobre `tmp_validacion_aud` con los seis `script.sql` instalados. Referencia: la evidencia `demostracion.md` de cada carpeta.

| Prueba                       | Resultado de referencia  | Resultado con auditoría  | Coincide |
| ---------------------------- | ------------------------ | ------------------------ | -------- |
| `estructura_auditoria`       | 9 de 9, `filas_demo` 0   | 9 de 9, `filas_demo` 0   | Sí       |
| `auditar_precio_publicacion` | 26 de 26, `filas_demo` 0 | 26 de 26, `filas_demo` 0 | Sí       |
| `auditar_stock_publicacion`  | 17 de 17, `filas_demo` 0 | 17 de 17, `filas_demo` 0 | Sí       |
| `auditar_pedidos`            | 18 de 18, `filas_demo` 0 | 18 de 18, `filas_demo` 0 | Sí       |
| `auditar_pagos`              | 24 de 24, `filas_demo` 0 | 24 de 24, `filas_demo` 0 | Sí       |
| `auditar_usuarios`           | 22 de 22, `filas_demo` 0 | 22 de 22, `filas_demo` 0 | Sí       |

Después de la última, AUDITORIA y AUDITORIA_DETALLE tenían 0 filas, con `IDENT_CURRENT('dbo.AUDITORIA')` en 103. Había 20 triggers habilitados y ninguno deshabilitado, y USUARIO, PUBLICACION, PEDIDO y PAGO tenían 500, 791, 600 y 718 filas, los conteos de la carga.

## Paso 2: venta y casos de los triggers

`tmp_validacion_rv`, cargada con `validar.sh crear` (DDL, datos de prueba, `calcular_descuento_pedido/script.sql` y `triggers-consistencia.sql`), con la auditoría instalada. Después, `validar.sh aplicar` (`registrar_venta/script.sql` y su demostración) y `validar.sh casos`. Referencias: `registrar_venta/evidencias/demostracion.md` y `docs/etapa-03/pruebas-validacion.md`.

| Prueba                            | Resultado de referencia  | Resultado con auditoría  | Coincide |
| --------------------------------- | ------------------------ | ------------------------ | -------- |
| Demostración de `registrar_venta` | 53 de 53, `filas_demo` 0 | 53 de 53, `filas_demo` 0 | Sí       |
| `casos-triggers.sql`              | 113 de 113               | 113 de 113               | Sí       |

Los 16 controles de datos del final de `casos-triggers.sql` quedaron en 0, entre ellos `Triggers deshabilitados`. La única diferencia en la salida es `triggers_habilitados`: 20, los 15 de consistencia y los 5 de auditoría.

### Eventos que deja la demostración de `registrar_venta`

La demostración no limpia la auditoría, así que sus eventos quedan, y es lo esperado. AUDITORIA tenía 0 filas antes de `aplicar` y 63 después:

| Tabla       | Operación | Origen                      | Eventos |
| ----------- | --------- | --------------------------- | ------- |
| PAGO        | I         | -                           | 11      |
| PAGO        | U         | -                           | 11      |
| PEDIDO      | U         | -                           | 8       |
| PEDIDO      | U         | `trg_PAGO_ConfirmarPedido`  | 5       |
| PUBLICACION | D         | -                           | 10      |
| PUBLICACION | U         | `trg_PEDIDO_DescontarStock` | 5       |
| PUBLICACION | U         | `trg_PUBLICACION_Agotada`   | 3       |
| PUBLICACION | U         | `trg_USUARIO_Baja`          | 1       |
| USUARIO     | D         | -                           | 4       |
| USUARIO     | I         | -                           | 4       |
| USUARIO     | U         | -                           | 1       |

Por tabla: PAGO 22, PEDIDO 13, PUBLICACION 19 y USUARIO 9. Los eventos D son de `#LimpiarDemoVenta`, que borra las publicaciones y los usuarios de la demostración.

### AUDITORIA antes y después de los casos

Cada caso de `casos-triggers.sql` corre y se revierte en su propia transacción. El checksum es `CHECKSUM_AGG(BINARY_CHECKSUM(*))`:

| Tabla             | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| ----------------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| AUDITORIA         | 63          | 63            | 1180730774     | 1180730774       | 64                  | 317                   |
| AUDITORIA_DETALLE | 214         | 214           | 1737544946     | 1737544946       | 218                 | 677                   |

Las filas y el checksum no cambiaron, y `IDENT_CURRENT` avanzó 253 valores en AUDITORIA y 459 en AUDITORIA_DETALLE: los triggers de auditoría corrieron, y el `ROLLBACK` de cada caso deshizo sus filas.

Para separar los casos aceptados de los rechazados, se ejecutó después, sobre la misma base, una copia de `casos-triggers.sql` que anota por caso el avance de `IDENT_CURRENT` y, antes del `ROLLBACK`, las filas nuevas de AUDITORIA. También comprueba, después de cada caso, que AUDITORIA tenga las mismas filas que antes. Dio 113 de 113 otra vez, con `IDENT_CURRENT` de 317 a 570 (los mismos 253 valores) y AUDITORIA en 63 filas en los 113 casos:

| Casos                  | Cantidad | Con valores consumidos | Valores consumidos | Eventos dentro de la transacción | Detalles dentro de la transacción |
| ---------------------- | -------- | ---------------------- | ------------------ | -------------------------------- | --------------------------------- |
| Aceptados (esperado 0) | 36       | 24                     | 224                | 224                              | 395                               |
| Rechazados             | 77       | 19                     | 29                 | no se mide                       | no se mide                        |

- En los 24 casos aceptados que consumieron valores, los eventos se veían dentro de la transacción (uno por valor consumido) y desaparecieron con el `ROLLBACK`. La baja de dos vendedores en una sentencia generó 58 eventos.
- Los otros 12 aceptados no cambian columnas auditadas: altas de publicaciones y de pedidos (el INSERT no se audita en esas tablas), renglones, direcciones y autores (tablas sin auditoría), un cambio de libro, borrados que no afectan filas y UPDATE que no cambian ningún valor.
- En los 19 rechazados que consumieron valores, la auditoría corrió antes del error, y el `ROLLBACK` la deshizo. Entre ellos están los dos 50281 de `trg_USUARIO_CambioRol` y el 50275 de `trg_PUBLICACION_Historial`, triggers hermanos de la auditoría sin orden fijado: en esta corrida, la auditoría corrió primero. En un caso rechazado el error salta al `CATCH` antes de contar las filas, así que no se miden los eventos dentro de la transacción.

## Paso 3: concurrencia de la venta

`tmp_validacion_rv` recreada como en el paso 2, con la auditoría instalada y `validar.sh aplicar` (53 de 53, `filas_demo` 0). Antes de la prueba, `MAX(pago_id)` era 718 (la demostración borra sus pagos), AUDITORIA tenía 63 filas e `IDENT_CURRENT('dbo.AUDITORIA')` era 64. Referencia: `registrar_venta/evidencias/concurrencia.md`, del 2026-11-01.

| Prueba                                                       | Resultado de referencia                                                                                                           | Resultado con auditoría                                                                                                           | Coincide |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | -------- |
| Caso A: última unidad                                        | 1 pedido, 7 errores 50107, stock real 1                                                                                           | 1 pedido, 7 errores 50107, stock real 1                                                                                           | Sí       |
| Caso B: pagos simultáneos del mismo pedido                   | 1 pago, 7 errores 50113                                                                                                           | 1 pago, 7 errores 50113                                                                                                           | Sí       |
| Caso C: aprobaciones simultáneas del mismo pago              | 1 venta, 7 errores 50123, pedido Confirmado, stock 8                                                                              | 1 venta, 7 errores 50123, pedido Confirmado, stock 8                                                                              | Sí       |
| Caso D: operaciones mezcladas sobre las mismas publicaciones | 0 errores 1205, 0 ventas sin registrar, 0 publicaciones con stock distinto del inicial menos lo vendido; 320 pedidos y 240 ventas | 0 errores 1205, 0 ventas sin registrar, 0 publicaciones con stock distinto del inicial menos lo vendido; 320 pedidos y 240 ventas | Sí       |
| Caso E: sesiones con publicaciones distintas                 | 0 errores 1205, 320 ventas, 0 publicaciones con stock distinto del inicial menos lo vendido; 320 pedidos                          | 0 errores 1205, 320 ventas, 0 publicaciones con stock distinto del inicial menos lo vendido; 320 pedidos                          | Sí       |
| Deadlocks registrados por el servidor                        | 0                                                                                                                                 | 0                                                                                                                                 | Sí       |
| Errores fuera del `TRY` de las sesiones                      | 0                                                                                                                                 | 0                                                                                                                                 | Sí       |

Los ID de B y C (pedido 617 y pago 732) no son los de la referencia (631 y 743), que se tomó con la demostración del 2026-11-01. En una corrida de control con la demostración actual y sin auditoría, `IDENT_CURRENT` quedó en 615 en PEDIDO y en 730 en PAGO. El de PAGO es el mismo que con auditoría: la diferencia viene de la demostración, y la auditoría no consume valores de las tablas auditadas.

### Coherencia de la auditoría

Pagos con `pago_id` mayor que 718: los 642 que creó la prueba, del 731 al 1372.

| Pagos      | Cantidad | Con exactamente un evento | Evento                            |
| ---------- | -------- | ------------------------- | --------------------------------- |
| Todos      | 642      | 642                       | I                                 |
| Aprobados  | 561      | 561                       | U `estado: Pendiente a Aprobado`  |
| Rechazados | 80       | 80                        | U `estado: Pendiente a Rechazado` |

Ningún pago que no terminó Aprobado tiene el evento de aprobación (0), y no hay eventos de pagos que no existen (0): los intentos que fallaron con 50113 y 50123 no dejaron eventos. El pago que queda Pendiente es el del caso B.

Eventos de la prueba, posteriores al 64:

| Tabla       | Operación | Origen                      | Eventos |
| ----------- | --------- | --------------------------- | ------- |
| PAGO        | I         | -                           | 642     |
| PAGO        | U         | -                           | 641     |
| PEDIDO      | U         | `trg_PAGO_ConfirmarPedido`  | 561     |
| PUBLICACION | U         | -                           | 12      |
| PUBLICACION | U         | `trg_PEDIDO_DescontarStock` | 801     |

- 561 confirmaciones de pedido, una por venta: 1 en C, 240 en D y 320 en E. 801 descuentos de stock, uno por renglón vendido: 1 en C, 480 en D (dos publicaciones por pedido) y 320 en E. Los 12 cambios de PUBLICACION sin origen son los ajustes de stock del propio `concurrencia.sh`: 1 en A, 1 en C, 2 en D y 8 en E.
- AUDITORIA terminó con 2720 filas: 63 de la demostración y 2657 de la prueba. `IDENT_CURRENT` llegó a 2722, así que la prueba usó 2658 valores. El único hueco es el 66: el `UPDATE` de la sesión que retiene la publicación en el caso A, que termina con `ROLLBACK`.

## Paso 4: transacciones

`tmp_validacion_tx`, cargada con `validar.sh crear` (la instalación completa del README), con la auditoría instalada. Después, `aplicar alta_libro_con_autores`, `aplicar cancelar_pedido` y `concurrencia.sh`. Referencias: `alta_libro_con_autores/evidencias/demostracion.md`, `cancelar_pedido/evidencias/demostracion.md` y `cancelar_pedido/evidencias/concurrencia.md`.

| Prueba                                   | Resultado de referencia                                                                                                                | Resultado con auditoría                                                                                                                | Coincide |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| Demostración de `alta_libro_con_autores` | 28 de 28, `filas_demo` 0                                                                                                               | 28 de 28, `filas_demo` 0                                                                                                               | Sí       |
| Demostración de `cancelar_pedido`        | 24 de 24, `filas_demo` 0                                                                                                               | 24 de 24, `filas_demo` 0                                                                                                               | Sí       |
| Caso A: la aprobación llega primero      | 2 sesiones bloqueadas; pago Aprobado con fecha, pedido Confirmado, stock 2 menos; aprobación sin error y cancelación con 50312         | 2 sesiones bloqueadas; pago Aprobado con fecha, pedido Confirmado, stock 2 menos; aprobación sin error y cancelación con 50312         | Sí       |
| Caso B: la cancelación llega primero     | 2 sesiones bloqueadas; pago Cancelado con fecha, pedido Cancelado, stock igual; aprobación sin error y cancelación sin error           | 2 sesiones bloqueadas; pago Cancelado con fecha, pedido Cancelado, stock igual; aprobación sin error y cancelación sin error           | Sí       |
| Caso C: carrera libre                    | 10 pedidos coherentes, 0 mixtos, stock final igual al inicial menos los Confirmados, un error 50312 por Confirmado y ningún otro error | 10 pedidos coherentes, 0 mixtos, stock final igual al inicial menos los Confirmados, un error 50312 por Confirmado y ningún otro error | Sí       |
| Deadlocks registrados por el servidor    | 0                                                                                                                                      | 0                                                                                                                                      | Sí       |
| Errores fuera del `TRY` de las sesiones  | 0                                                                                                                                      | 0                                                                                                                                      | Sí       |

Los pedidos y pagos son los mismos de la referencia: 607 y 722 en A, 608 y 723 en B, y los pedidos 609 a 618 en C. En C, la carrera es libre y el reparto no forma parte del resultado esperado: la referencia terminó con 5 Confirmados y 5 Cancelados, y esta corrida, con 3 y 7.

### Coherencia de la auditoría

Antes de la prueba, después de las dos demostraciones, AUDITORIA tenía 36 filas, con `IDENT_CURRENT` en 36. `MAX(pago_id)` era 718 y `MAX(pedido_id)`, 600.

| Filas posteriores | Estado final | Cantidad | Con exactamente un evento de cada tipo | Eventos                                                                       |
| ----------------- | ------------ | -------- | -------------------------------------- | ----------------------------------------------------------------------------- |
| Pagos             | Aprobado     | 4        | 4                                      | I, y U `estado: Pendiente a Aprobado`                                         |
| Pagos             | Cancelado    | 8        | 8                                      | I, y U `estado: Pendiente a Cancelado`                                        |
| Pedidos           | Confirmado   | 4        | 4                                      | U `estado: Pendiente a Confirmado`, origen `trg_PAGO_ConfirmarPedido`         |
| Pedidos           | Cancelado    | 8        | 8                                      | U `estado: Pendiente a Cancelado`, sin origen: lo cambia `usp_CancelarPedido` |

No hay eventos de pagos ni de pedidos que no existen (0). Los otros 5 eventos de la prueba son de PUBLICACION: el ajuste del stock a 1000 que hace `concurrencia.sh` y los 4 descuentos de stock de las ventas, con origen `trg_PEDIDO_DescontarStock`. AUDITORIA terminó con 77 filas e `IDENT_CURRENT` en 77: la prueba registró 41 eventos sin huecos, así que las cuatro cancelaciones que fallaron con 50312 no consumieron valores. Las sesiones que retienen el pedido en A y B hacen un `UPDATE` que no cambia nada, y `trg_PEDIDO_Auditoria` no registra eventos sin cambios.

## Cierre

- Todos los resultados coinciden con los de referencia, con 0 errores 1205 y 0 deadlocks.
- Los casos de los triggers no cambiaron AUDITORIA, y su `IDENT_CURRENT` avanzó 253 valores.
- `registrar_venta/evidencias/concurrencia.md` y `cancelar_pedido/evidencias/concurrencia.md` no cambiaron.
- `tmp_validacion_aud`, `tmp_validacion_rv` y `tmp_validacion_tx` quedaron borradas, y todas las ejecuciones fueron sobre esas bases.
