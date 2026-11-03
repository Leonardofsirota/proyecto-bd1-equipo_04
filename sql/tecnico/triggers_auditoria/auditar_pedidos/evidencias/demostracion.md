# Demostración de `auditar_pedidos/demostracion.sql`

- **Fecha:** 2026-11-03 15:31
- **Repetición:** 2026-11-03, enseguida y sobre la misma base, después de repetir la demostración de `auditar_stock_publicacion`: los mismos resultados, con los usuarios 511 y 512, las publicaciones 804 y 805, los pedidos 607 a 610 y los eventos del 39 al 47, en lugar de 505 y 506, 797 y 798, 602 a 605 y del 16 al 24. Las corridas anteriores, sobre otra base, también dieron 18 de 18 con `filas_demo` en 0: las cuatro demostraciones de `triggers_auditoria` dos veces seguidas.
- **Base temporal:** `tmp_validacion_aud`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más los `script.sql` de `triggers_auditoria/estructura_auditoria`, `auditar_precio_publicacion`, `auditar_stock_publicacion` y `auditar_pedidos`. Antes se ejecutó la demostración de `auditar_stock_publicacion`.
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración.

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 18             | 18        | 0        | 0          |

Tablas que escribe la demostración, antes y después de ejecutarla. El checksum es `CHECKSUM_AGG(BINARY_CHECKSUM(*))`:

| Tabla             | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| ----------------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| USUARIO           | 500         | 500           | -1321992964    | -1321992964      | 504                 | 506                   |
| DIRECCION         | 603         | 603           | -544889019     | -544889019       | 604                 | 605                   |
| PUBLICACION       | 791         | 791           | 1804080490     | 1804080490       | 796                 | 798                   |
| PEDIDO            | 600         | 600           | -2005910744    | -2005910744      | 601                 | 605                   |
| PEDIDO_DETALLE    | 1290        | 1290          | 417360875      | 417360875        | 1291                | 1295                  |
| PAGO              | 718         | 718           | -1763708289    | -1763708289      | 719                 | 721                   |
| AUDITORIA         | 0           | 0             | NULL           | NULL             | 15                  | 24                    |
| AUDITORIA_DETALLE | 0           | 0             | NULL           | NULL             | 48                  | 69                    |

`AUDITORIA` usó 9 valores, del 16 al 24. Siete son los eventos confirmados de los casos 1 a 5: cinco de pedidos y dos de `trg_PUBLICACION_AuditoriaStock`, el descuento de stock de la venta del caso 1 y el ajuste manual del caso 4. Los otros dos son los eventos D del borrado de las dos publicaciones, en la limpieza, que después los borra junto con los demás. Los casos 6 y 7 no consumieron valores. `AUDITORIA_DETALLE` avanza con un valor por columna registrada. `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado`, que la limpieza deshabilita dentro de su transacción, quedan habilitados (`is_disabled = 0`).

Datos de la demostración: el vendedor 505 y el cliente 506, con la dirección 605. El vendedor crea las publicaciones 797 (stock 50, 8000.00) y 798 (stock 2, 6000.00), de libros con autor. Los pedidos los crea `usp_CrearPedido` en la sesión del cliente, y la pasarela actúa sin usuario de sesión.

Las comprobaciones de eventos resumen los eventos de un pedido posteriores al inicio del paso como `operación columna: anterior a nuevo; usuario; origen`, con `-` para un usuario u origen NULL, y solo toman `estado` y `fecha_pedido`. **Login y fecha** comprueba que todos esos eventos tengan `login_bd = ORIGINAL_LOGIN()` y una fecha entre el inicio del paso y la comprobación.

## Caso 1: la pasarela aprueba el pago de un pedido

El cliente 506 crea el pedido 602 por 1 unidad de la publicación 797, y `usp_IniciarPago` registra el pago 720. La pasarela lo aprueba con `usp_RegistrarVenta`, que devuelve `Venta registrada correctamente`. La confirmación la hace `trg_PAGO_ConfirmarPedido`, que queda como origen del evento (RN19).

| Comprobación              | Esperado                                                                     | Obtenido                                                                     | Resultado |
| ------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------- | --------- |
| Error de la venta         | sin error                                                                    | sin error                                                                    | OK        |
| Evento de la confirmación | U estado: Pendiente a Confirmado; usuario -; origen trg_PAGO_ConfirmarPedido | U estado: Pendiente a Confirmado; usuario -; origen trg_PAGO_ConfirmarPedido | OK        |
| Login y fecha             | 1 evento; login real; fecha del paso                                         | 1 evento; login real; fecha del paso                                         | OK        |

## Caso 2: el vendedor marca entregado el pedido

Con el vendedor 505 declarado en la sesión, un `UPDATE` directo pasa el pedido 602 a Entregado (RN20). PEDIDO no guarda cuándo ni quién lo entregó: lo guarda el evento. El historial del pedido en `vw_Auditoria`, con los eventos de los casos 1 y 2:

| auditoria_id | fecha                   | tabla  | operacion | registro_id | columna | valor_anterior | valor_nuevo | login_bd     | usuario_id | usuario_email                                | origen                   |
| ------------ | ----------------------- | ------ | --------- | ----------- | ------- | -------------- | ----------- | ------------ | ---------- | -------------------------------------------- | ------------------------ |
| 17           | 2026-11-03 15:31:33.117 | PEDIDO | U         | 602         | estado  | Pendiente      | Confirmado  | `admin\user` | NULL       | NULL                                         | trg_PAGO_ConfirmarPedido |
| 18           | 2026-11-03 15:31:33.150 | PEDIDO | U         | 602         | estado  | Confirmado     | Entregado   | `admin\user` | 505        | demo.auditoria.auditar_pedidos.1@example.com | NULL                     |

El 16 es el descuento de stock de la publicación 797 en la misma venta, registrado por `trg_PUBLICACION_AuditoriaStock`. En la repetición, el historial del pedido 607 tuvo los eventos 39 y 41, con el del stock en medio: el orden entre `trg_PEDIDO_DescontarStock` y `trg_PEDIDO_Auditoria` no está fijado.

| Comprobación         | Esperado                                                | Obtenido                                                | Resultado |
| -------------------- | ------------------------------------------------------- | ------------------------------------------------------- | --------- |
| Evento de la entrega | U estado: Confirmado a Entregado; usuario 505; origen - | U estado: Confirmado a Entregado; usuario 505; origen - | OK        |
| Login y fecha        | 1 evento; login real; fecha del paso                    | 1 evento; login real; fecha del paso                    | OK        |

## Caso 3: el cliente cancela un pedido pendiente

El cliente 506 crea el pedido 603 y lo cancela con un `UPDATE` directo. El evento lo registra como autor.

| Comprobación             | Esperado                                               | Obtenido                                               | Resultado |
| ------------------------ | ------------------------------------------------------ | ------------------------------------------------------ | --------- |
| Evento de la cancelación | U estado: Pendiente a Cancelado; usuario 506; origen - | U estado: Pendiente a Cancelado; usuario 506; origen - | OK        |

## Caso 4: cobro sin venta

El cliente 506 crea el pedido 604 por las 2 unidades de la publicación 798, y `usp_IniciarPago` registra el pago 721. Con el pago Pendiente, el vendedor 505 baja el stock a 1: el stock libre para el pedido, sin contar su propia reserva, es 1, menor que las 2 unidades. La pasarela aprueba el pago, y `usp_RegistrarVenta` devuelve el pago y el pedido Cancelados, con el mensaje `Pago aprobado sin stock libre: no hay venta y la devolucion se resuelve fuera del sistema` (RN37). El procedimiento cancela el pedido con su propio `UPDATE`: el evento no tiene origen, y el pedido nunca pasa por Confirmado.

| Comprobación                                | Esperado                                             | Obtenido                                             | Resultado |
| ------------------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | --------- |
| Stock libre para el pedido antes de aprobar | 1                                                    | 1                                                    | OK        |
| Error de la aprobación                      | sin error                                            | sin error                                            | OK        |
| Evento de la cancelación                    | U estado: Pendiente a Cancelado; usuario -; origen - | U estado: Pendiente a Cancelado; usuario -; origen - | OK        |
| Eventos que confirman el pedido             | 0                                                    | 0                                                    | OK        |

## Caso 5: `fecha_pedido` 10 minutos hacia el pasado

El cliente 506 crea el pedido 605. Sin usuario de sesión, como hacen las demostraciones que simulan el paso del tiempo, su `fecha_pedido` se mueve 10 minutos hacia el pasado, lo que acorta la reserva (RN34). El evento guarda la fecha anterior y la nueva, con el estilo 121. El resumen exacto también comprueba que no tiene detalle de estado.

| Comprobación               | Esperado                                                                               | Obtenido                                                                               | Resultado |
| -------------------------- | -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | --------- |
| Evento del cambio de fecha | U fecha_pedido: 2026-11-03 15:31:33.190 a 2026-11-03 15:21:33.190; usuario -; origen - | U fecha_pedido: 2026-11-03 15:31:33.190 a 2026-11-03 15:21:33.190; usuario -; origen - | OK        |

## Caso 6: pasar a Pendiente el pedido entregado

El vendedor 505 intenta volver a Pendiente el pedido 602. `trg_PEDIDO_Transicion` rechaza la sentencia con 50215 (RN19, RN20). Es el primero de los triggers de UPDATE de PEDIDO (`sp_settriggerorder`), así que la auditoría no llega a correr y no consume un valor IDENTITY.

| Comprobación          | Esperado    | Obtenido    | Resultado |
| --------------------- | ----------- | ----------- | --------- |
| Error                 | 50215       | 50215       | OK        |
| Eventos               | sin eventos | sin eventos | OK        |
| IDENTITY de AUDITORIA | no avanzó   | no avanzó   | OK        |
| Estado sin cambios    | Entregado   | Entregado   | OK        |

## Caso 7: `UPDATE` sin cambios

Sin usuario de sesión, dos sentencias sobre el pedido 605: `fecha_pedido = fecha_pedido` y `pedido_estado_id = pedido_estado_id`. Las dos pasan el control de `UPDATE()`, y el filtro con `EXCEPT` descarta los valores que no cambiaron.

| Comprobación                        | Esperado    | Obtenido    | Resultado |
| ----------------------------------- | ----------- | ----------- | --------- |
| fecha_pedido = fecha_pedido         | sin eventos | sin eventos | OK        |
| pedido_estado_id = pedido_estado_id | sin eventos | sin eventos | OK        |

## Caso 8: transacciones abiertas

`@Abiertas` suma `@@TRANCOUNT` después de las llamadas a `usp_EstablecerUsuarioSesion`, de la creación de las publicaciones, de los procedimientos de la venta y de la sentencia que falla.

| Comprobación           | Esperado | Obtenido | Resultado |
| ---------------------- | -------- | -------- | --------- |
| Transacciones abiertas | 0        | 0        | OK        |
