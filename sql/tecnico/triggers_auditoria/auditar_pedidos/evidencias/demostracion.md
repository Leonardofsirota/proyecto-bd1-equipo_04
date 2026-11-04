# Demostración: auditoría del estado y la fecha de los pedidos

Prueba `trg_PEDIDO_Auditoria`, que registra los cambios del estado y de la fecha de un pedido. Así queda constancia de quién y cuándo lo confirmó, lo entregó o lo canceló (RN19, RN20), algo que el pedido no guarda, y de los cambios de fecha que acortan la reserva (RN34). La demostración trabaja con usuarios, publicaciones y pedidos propios, y los borra al terminar.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **18 de 18** comprobaciones correctas

## Resumen

| Caso | Qué se prueba                             | Comprobaciones | Resultado |
| ---- | ----------------------------------------- | -------------- | --------- |
| 1    | La pasarela aprueba el pago de un pedido  | 3              | OK        |
| 2    | El vendedor marca entregado el pedido     | 2              | OK        |
| 3    | El cliente cancela un pedido pendiente    | 1              | OK        |
| 4    | Cobro sin venta                           | 4              | OK        |
| 5    | `fecha_pedido` 10 minutos hacia el pasado | 1              | OK        |
| 6    | Pasar a Pendiente el pedido entregado     | 4              | OK        |
| 7    | `UPDATE` sin cambios                      | 2              | OK        |
| 8    | Transacciones abiertas tras cada llamada  | 1              | OK        |

Cada evento se lee `operación columna: anterior a nuevo; usuario; origen`. I es alta, U cambio y D borrado, `-` es un valor vacío, y el origen es el trigger que hizo el cambio, vacío si lo hizo una sentencia o un procedimiento. **Login y fecha** comprueba que el evento guarde el login real y una fecha dentro del paso. Las comprobaciones solo toman `estado` y `fecha_pedido`.

La demostración usa un vendedor y un cliente. El vendedor publica dos libros, uno con stock 50 y otro con stock 2. El cliente crea los pedidos con `usp_CrearPedido`, y la pasarela actúa sin usuario de sesión.

## Caso 1: la pasarela aprueba el pago de un pedido

El cliente pide 1 unidad e inicia el pago, y la pasarela lo aprueba: «Venta registrada correctamente». El pedido lo confirma `trg_PAGO_ConfirmarPedido`, que queda como origen del evento, sin usuario (RN19).

| Comprobación              | Valor                                                                        | Resultado |
| ------------------------- | ---------------------------------------------------------------------------- | --------- |
| Error de la venta         | sin error                                                                    | OK        |
| Evento de la confirmación | U estado: Pendiente a Confirmado; usuario -; origen trg_PAGO_ConfirmarPedido | OK        |
| Login y fecha             | 1 evento; login real; fecha del paso                                         | OK        |

## Caso 2: el vendedor marca entregado el pedido

Con el vendedor declarado en la sesión, un `UPDATE` directo pasa el pedido del caso 1 a Entregado (RN20). El pedido no guarda cuándo ni quién lo entregó: lo guarda el evento. El historial del pedido en `vw_Auditoria`, con los eventos de los casos 1 y 2:

| fecha                   | operacion | columna | valor_anterior | valor_nuevo | login_bd     | usuario_id   | origen                   |
| ----------------------- | --------- | ------- | -------------- | ----------- | ------------ | ------------ | ------------------------ |
| 2026-11-03 15:31:33.117 | U         | estado  | Pendiente      | Confirmado  | `admin\user` | NULL         | trg_PAGO_ConfirmarPedido |
| 2026-11-03 15:31:33.150 | U         | estado  | Confirmado     | Entregado   | `admin\user` | vendedor 505 | NULL                     |

| Comprobación         | Valor                                                    | Resultado |
| -------------------- | -------------------------------------------------------- | --------- |
| Evento de la entrega | U estado: Confirmado a Entregado; vendedor 505; origen - | OK        |
| Login y fecha        | 1 evento; login real; fecha del paso                     | OK        |

## Caso 3: el cliente cancela un pedido pendiente

El cliente crea otro pedido y lo cancela con un `UPDATE` directo. El evento lo registra como autor.

| Comprobación             | Valor                                                  | Resultado |
| ------------------------ | ------------------------------------------------------ | --------- |
| Evento de la cancelación | U estado: Pendiente a Cancelado; cliente 506; origen - | OK        |

## Caso 4: cobro sin venta

El cliente pide las 2 unidades de la publicación con stock 2 e inicia el pago. Con el pago todavía Pendiente, el vendedor baja el stock a 1, así que el stock libre para el pedido, sin contar su propia reserva, queda en 1, menos de lo pedido. Cuando la pasarela aprueba el pago no hay venta (RN37): el procedimiento deja el pago y el pedido Cancelados y responde «Pago aprobado sin stock libre: no hay venta y la devolucion se resuelve fuera del sistema». Lo cancela con su propia sentencia, así que el evento no tiene origen, y el pedido nunca pasa por Confirmado.

| Comprobación                                | Valor                                                | Resultado |
| ------------------------------------------- | ---------------------------------------------------- | --------- |
| Stock libre para el pedido antes de aprobar | 1                                                    | OK        |
| Error de la aprobación                      | sin error                                            | OK        |
| Evento de la cancelación                    | U estado: Pendiente a Cancelado; usuario -; origen - | OK        |
| Eventos que confirman el pedido             | 0                                                    | OK        |

## Caso 5: `fecha_pedido` 10 minutos hacia el pasado

El cliente crea otro pedido, y sin usuario de sesión, como hacen las demostraciones que simulan el paso del tiempo, su fecha se mueve 10 minutos hacia el pasado. Eso acorta la reserva (RN34), y el evento guarda la fecha anterior y la nueva, sin ningún cambio de estado.

| Comprobación               | Valor                                                                                  | Resultado |
| -------------------------- | -------------------------------------------------------------------------------------- | --------- |
| Evento del cambio de fecha | U fecha_pedido: 2026-11-03 15:31:33.190 a 2026-11-03 15:21:33.190; usuario -; origen - | OK        |

## Caso 6: pasar a Pendiente el pedido entregado

El vendedor intenta volver a Pendiente el pedido entregado del caso 2. `trg_PEDIDO_Transicion` rechaza la sentencia con el error 50215 (RN19, RN20), y el pedido sigue Entregado. La auditoría no llegó a correr: no hay eventos y no se consumió ningún número de evento.

| Comprobación          | Valor       | Resultado |
| --------------------- | ----------- | --------- |
| Error                 | 50215       | OK        |
| Eventos               | sin eventos | OK        |
| IDENTITY de AUDITORIA | no avanzó   | OK        |
| Estado sin cambios    | Entregado   | OK        |

## Caso 7: `UPDATE` sin cambios

Sin usuario de sesión, dos sentencias sobre el pedido del caso 5 asignan a la fecha y al estado sus mismos valores. Ninguna deja eventos: el trigger descarta los valores que no cambiaron.

| Comprobación                        | Valor       | Resultado |
| ----------------------------------- | ----------- | --------- |
| fecha_pedido = fecha_pedido         | sin eventos | OK        |
| pedido_estado_id = pedido_estado_id | sin eventos | OK        |

## Caso 8: transacciones abiertas

Después de cada llamada a un procedimiento, de la creación de las publicaciones, de los procedimientos de la venta y de la sentencia que falla, no quedó ninguna transacción abierta (0).

## Conclusión

`trg_PEDIDO_Auditoria` deja el historial de cada pedido: la confirmación con su origen en el trigger del pago, la entrega y la cancelación con el usuario que las hizo, y la cancelación de un cobro sin venta sin pasar por Confirmado. También registra los cambios de fecha que acortan la reserva. Una transición prohibida (50215) y los `UPDATE` sin cambios no dejan eventos. La limpieza dejó la base igual, y los triggers que deshabilita mientras borra quedaron habilitados.
