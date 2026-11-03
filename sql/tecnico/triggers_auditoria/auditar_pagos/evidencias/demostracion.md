# Demostración: auditoría de los pagos

Prueba `trg_PAGO_Auditoria`, que registra el alta de cada pago y los cambios de su estado y de sus fechas. Así queda constancia de quién inició cada intento y de cuándo la pasarela lo aprobó o lo rechazó (RN23 a RN25), de los cobros sin venta (RN37) y de los cambios de fecha que alteran la reserva (RN34). La demostración trabaja con usuarios, una publicación y pedidos propios, y los borra al terminar.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **24 de 24** comprobaciones correctas

## Resumen

| Caso | Qué se prueba                               | Comprobaciones | Resultado |
| ---- | ------------------------------------------- | -------------- | --------- |
| 1    | El cliente inicia un pago                   | 3              | OK        |
| 2    | La pasarela rechaza el pago                 | 3              | OK        |
| 3    | El cliente reintenta y la pasarela aprueba  | 2              | OK        |
| 4    | Cobro sin venta                             | 2              | OK        |
| 5    | `fecha_creacion` 10 minutos hacia el pasado | 1              | OK        |
| 6    | Rechazo revertido por el llamador           | 4              | OK        |
| 7    | Borrar un pago                              | 4              | OK        |
| 8    | Cambiar el estado del pago aprobado         | 4              | OK        |
| 9    | Transacciones abiertas tras cada llamada    | 1              | OK        |

Cada evento se lee `operación columna: anterior a nuevo; usuario; origen`. I es alta, U cambio y D borrado, `-` es un valor vacío, y el origen es el trigger que hizo el cambio, vacío si lo hizo una sentencia o un procedimiento. **Login y fecha** comprueba que el evento guarde el login real y una fecha dentro del paso. Las comprobaciones solo toman `estado`, `fecha_creacion`, `fecha_pago`, `importe`, `metodo` y `pedido_id`.

La demostración usa un vendedor y un cliente. El vendedor publica un libro con stock 50 a 60000.00. El cliente crea los pedidos con `usp_CrearPedido` e inicia los pagos con `usp_IniciarPago`, y la pasarela actúa sin usuario de sesión.

## Caso 1: el cliente inicia un pago

El cliente pide 2 unidades, por un total de 120000.00 que recibe un 5 % de descuento, e inicia el pago con tarjeta de crédito por el total con descuento, 114000.00. El alta guarda el pedido, el importe, el método y el estado con que nace el pago, con el cliente como usuario y sin origen:

| Columna   | Nuevo              |
| --------- | ------------------ |
| estado    | Pendiente          |
| importe   | 114000.00          |
| metodo    | Tarjeta de crédito |
| pedido_id | 601                |

| Comprobación                   | Valor                                                            | Resultado |
| ------------------------------ | ---------------------------------------------------------------- | --------- |
| Total del pedido sin descuento | 120000.00                                                        | OK        |
| Evento del alta                | I con estado, importe, metodo y pedido_id; cliente 502; origen - | OK        |
| Login y fecha                  | 1 evento; login real; fecha del paso                             | OK        |

## Caso 2: la pasarela rechaza el pago

La pasarela rechaza el pago con `usp_RegistrarVenta`, que responde «Pago actualizado: el pedido no cambia». Un pago Rechazado no tiene `fecha_pago`, así que el evento solo registra el cambio de estado, y su fecha es la única constancia de cuándo se rechazó.

| Comprobación       | Valor                                                | Resultado |
| ------------------ | ---------------------------------------------------- | --------- |
| Error del rechazo  | sin error                                            | OK        |
| Evento del rechazo | U estado: Pendiente a Rechazado; usuario -; origen - | OK        |
| Login y fecha      | 1 evento; login real; fecha del paso                 | OK        |

## Caso 3: el cliente reintenta y la pasarela aprueba

El reintento es un pago nuevo del mismo pedido (RN24), esta vez por transferencia. La pasarela lo aprueba, «Venta registrada correctamente», y el pedido queda Confirmado. Los dos intentos del pedido quedan registrados en `vw_Auditoria`: los inicia el cliente y los resuelve la pasarela, sin usuario de sesión.

| Comprobación      | Valor     | Resultado |
| ----------------- | --------- | --------- |
| Error de la venta | sin error | OK        |

Una sola comprobación toma los dos eventos del pago nuevo, en orden:

| Orden | Evento                                                                                          | Resultado |
| ----- | ----------------------------------------------------------------------------------------------- | --------- |
| 1     | I: el alta, como la del caso 1 pero con metodo Transferencia; cliente 502; origen -             | OK        |
| 2     | U estado: Pendiente a Aprobado, fecha_pago: NULL a 2026-11-03 15:47:27.120; usuario -; origen - | OK        |

## Caso 4: cobro sin venta

El cliente crea otro pedido por 1 unidad e inicia un pago por 60000.00. Después cancela el pedido con un `UPDATE` directo, que deja el pago Pendiente. Cuando la pasarela aprueba ese pago no hay venta (RN37): `usp_RegistrarVenta` deja el pago Cancelado y responde «Pago aprobado con el pedido fuera de Pendiente: no hay venta y la devolucion se resuelve fuera del sistema». El pago Cancelado conserva `fecha_pago` como rastro del cobro (RN25), y el evento registra los dos cambios.

| Comprobación               | Valor                                                                                            | Resultado |
| -------------------------- | ------------------------------------------------------------------------------------------------ | --------- |
| Error de la aprobación     | sin error                                                                                        | OK        |
| Evento del cobro sin venta | U estado: Pendiente a Cancelado, fecha_pago: NULL a 2026-11-03 15:47:27.220; usuario -; origen - | OK        |

## Caso 5: `fecha_creacion` 10 minutos hacia el pasado

El cliente crea un tercer pedido e inicia su pago. Sin usuario de sesión, como hacen las demostraciones que simulan el paso del tiempo, la `fecha_creacion` del pago se mueve 10 minutos hacia el pasado, lo que altera el plazo de la reserva (RN34). Es lo único, además del estado y de `fecha_pago`, que se puede cambiar de un pago. El evento guarda la fecha anterior y la nueva, sin ningún cambio de estado.

| Comprobación               | Valor                                                                                    | Resultado |
| -------------------------- | ---------------------------------------------------------------------------------------- | --------- |
| Evento del cambio de fecha | U fecha_creacion: 2026-11-03 15:47:27.227 a 2026-11-03 15:37:27.227; usuario -; origen - | OK        |

## Caso 6: rechazo revertido por el llamador

Dentro de una transacción abierta por el llamador, la pasarela rechaza el pago del caso 5 con `usp_RegistrarVenta`, que responde «Pago actualizado: el pedido no cambia», y después el llamador hace `ROLLBACK`. El `COMMIT` interno del procedimiento no confirma nada mientras haya una transacción externa, y el `ROLLBACK` del llamador deshace el rechazo y su evento. El número de evento se consumió, pero no quedó ninguna fila.

| Comprobación                | Valor                                                | Resultado |
| --------------------------- | ---------------------------------------------------- | --------- |
| Dentro de la transacción    | U estado: Pendiente a Rechazado; usuario -; origen - | OK        |
| Después del ROLLBACK        | sin eventos                                          | OK        |
| Estado después del ROLLBACK | Pendiente                                            | OK        |
| IDENTITY de AUDITORIA       | avanzó sin filas nuevas                              | OK        |

## Caso 7: borrar un pago

Un `DELETE` del mismo pago: `trg_PAGO_SinBorrado` lo rechaza con el error 50241, porque los intentos se conservan como historial del pedido (RN29). `trg_PAGO_Auditoria` no audita DELETE, porque nunca habría un borrado confirmado que registrar: no hay eventos y no se consumió ningún número de evento.

| Comprobación          | Valor       | Resultado |
| --------------------- | ----------- | --------- |
| Error                 | 50241       | OK        |
| Eventos               | sin eventos | OK        |
| IDENTITY de AUDITORIA | no avanzó   | OK        |
| El pago sigue         | 1           | OK        |

## Caso 8: cambiar el estado del pago aprobado

Un `UPDATE` intenta pasar a Rechazado el pago aprobado del caso 3. `trg_PAGO_Transicion` rechaza la sentencia con el error 50222 (RN24, RN25), y el pago sigue Aprobado. La auditoría no llegó a correr: no hay eventos y no se consumió ningún número de evento.

| Comprobación          | Valor       | Resultado |
| --------------------- | ----------- | --------- |
| Error                 | 50222       | OK        |
| Eventos               | sin eventos | OK        |
| IDENTITY de AUDITORIA | no avanzó   | OK        |
| Estado sin cambios    | Aprobado    | OK        |

## Caso 9: transacciones abiertas

Después de cada llamada a un procedimiento, de la creación de la publicación, de los procedimientos de la venta, del `ROLLBACK` del caso 6 y de las sentencias que fallan, no quedó ninguna transacción abierta (0).

## Conclusión

`trg_PAGO_Auditoria` deja el historial de cada pago: el alta con el cliente que lo inició, y el rechazo, la aprobación y el cobro sin venta resueltos por la pasarela, con la fecha de cada uno aunque el pago no la guarde. También registra los cambios de `fecha_creacion` que alteran la reserva. Un evento revertido por el llamador no queda, y un borrado (50241) o una transición prohibida (50222) no dejan eventos. La limpieza no dejó filas de la demostración y dejó la base igual, y los triggers que deshabilita mientras borra quedaron habilitados.
