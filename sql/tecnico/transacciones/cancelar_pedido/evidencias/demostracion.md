# Demostración: cancelación de un pedido

Prueba `usp_CancelarPedido`, que cancela un pedido Pendiente a pedido del cliente que lo hizo (RN20). No toca el stock, porque la reserva del pedido se libera sola (RN33), ni el pago abierto, que si la pasarela lo aprueba después queda como cobro sin venta (RN37). La demostración trabaja con clientes, publicaciones y pedidos propios, y los borra al terminar. La cancelación frente a una aprobación simultánea está en [`concurrencia.md`](concurrencia.md).

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **24 de 24** comprobaciones correctas

## Resumen

| Caso | Qué se prueba                               | Comprobaciones | Resultado |
| ---- | ------------------------------------------- | -------------- | --------- |
| 1    | Pedido Pendiente sin pagos                  | 2              | OK        |
| 2    | Pedido con la reserva vencida               | 3              | OK        |
| 3    | Pedido con pago Pendiente                   | 3              | OK        |
| 4    | Aprobación posterior del pago del caso 3    | 2              | OK        |
| 5    | Rechazo posterior de un pago abierto        | 2              | OK        |
| 6    | Pago nuevo sobre un pedido cancelado        | 2              | OK        |
| 7    | Pedido Confirmado                           | 3              | OK        |
| 8    | Pedido Entregado                            | 2              | OK        |
| 9    | Pedido ya Cancelado                         | 1              | OK        |
| 10   | Pedido de otro cliente y pedido inexistente | 3              | OK        |
| 11   | Transacciones abiertas tras cada llamada    | 1              | OK        |

Un pedido Pendiente reserva sus unidades sin descontarlas del stock real, y el stock libre es el stock real menos las reservas vigentes. Cada pedido tiene un solo renglón, de una publicación propia con stock 5, así que los stocks de las tablas son los de esa publicación.

## Caso 1: pedido Pendiente sin pagos

El cliente pide 2 unidades y cancela el pedido. El procedimiento responde «Pedido cancelado correctamente», sin pagos pendientes. El stock real no cambia y la reserva se libera: el stock libre vuelve a 5.

| Momento                   | Pedido    | Último pago | Stock real | Stock libre | Resultado |
| ------------------------- | --------- | ----------- | ---------- | ----------- | --------- |
| Antes: reserva 2 unidades | Pendiente | sin pago    | 5          | 3           | OK        |
| Después: reserva liberada | Cancelado | sin pago    | 5          | 5           | OK        |

## Caso 2: pedido con la reserva vencida

Un pedido de 1 unidad, hecho hace 20 minutos, ya no reserva porque su plazo venció, pero sigue Pendiente, así que todavía se puede cancelar.

| Comprobación              | Valor   | Resultado |
| ------------------------- | ------- | --------- |
| Reserva antes de cancelar | vencida | OK        |

| Momento                       | Pedido    | Último pago | Stock real | Stock libre | Resultado |
| ----------------------------- | --------- | ----------- | ---------- | ----------- | --------- |
| Antes: vencido, ya no reserva | Pendiente | sin pago    | 5          | 5           | OK        |
| Después                       | Cancelado | sin pago    | 5          | 5           | OK        |

## Caso 3: pedido con pago Pendiente

Un pedido de 2 unidades tiene un pago por tarjeta de 2000.00 todavía Pendiente. La cancelación no toca el pago, porque la pasarela todavía puede aprobarlo, y lo avisa: «Pedido cancelado: el pago pendiente sigue abierto y, si se aprueba, queda como cobro sin venta», con un pago pendiente.

| Momento                        | Pedido    | Último pago         | Stock real | Stock libre | Resultado |
| ------------------------------ | --------- | ------------------- | ---------- | ----------- | --------- |
| Antes                          | Pendiente | Pendiente sin fecha | 5          | 3           | OK        |
| Después: el pago sigue abierto | Cancelado | Pendiente sin fecha | 5          | 5           | OK        |

| Comprobación               | Valor | Resultado |
| -------------------------- | ----- | --------- |
| Pagos Pendiente del pedido | 1     | OK        |

## Caso 4: aprobación posterior del pago del caso 3

La pasarela aprueba el pago que quedó abierto en el caso 3. `usp_RegistrarVenta` termina sin error, pero no hay venta, porque el pedido ya no está Pendiente: el pago queda Cancelado con fecha como rastro del cobro, y el stock no cambia (RN37). El mensaje lo explica: «Pago aprobado con el pedido fuera de Pendiente: no hay venta y la devolucion se resuelve fuera del sistema».

| Comprobación           | Valor     | Resultado |
| ---------------------- | --------- | --------- |
| Error de la aprobación | sin error | OK        |

| Momento                       | Pedido    | Último pago         | Stock real | Stock libre | Resultado |
| ----------------------------- | --------- | ------------------- | ---------- | ----------- | --------- |
| Cobro sin venta y stock igual | Cancelado | Cancelado con fecha | 5          | 5           | OK        |

## Caso 5: rechazo posterior de un pago abierto

Otro cliente pide 1 unidad, inicia un pago por transferencia y cancela el pedido, que también informa un pago pendiente. Después la pasarela rechaza el pago: solo cambia el pago, y el procedimiento responde «Pago actualizado: el pedido no cambia».

| Comprobación      | Valor     | Resultado |
| ----------------- | --------- | --------- |
| Error del rechazo | sin error | OK        |

| Momento             | Pedido    | Último pago         | Stock real | Stock libre | Resultado |
| ------------------- | --------- | ------------------- | ---------- | ----------- | --------- |
| Solo cambia el pago | Cancelado | Rechazado sin fecha | 5          | 5           | OK        |

## Caso 6: pago nuevo sobre un pedido cancelado

El mismo cliente intenta pagar otra vez el pedido cancelado del caso 5. `usp_IniciarPago` lo rechaza con el error 50112, y el pedido sigue con un solo pago.

| Comprobación                         | Valor | Resultado |
| ------------------------------------ | ----- | --------- |
| Pago nuevo sobre el pedido cancelado | 50112 | OK        |
| Pagos del pedido                     | 1     | OK        |

## Caso 7: pedido Confirmado

Un pedido de 2 unidades se vende con un pago aprobado: `usp_RegistrarVenta` responde «Venta registrada correctamente» y el stock baja a 3. Un pedido Confirmado ya descontó stock y no se cancela (RN20): el procedimiento lo rechaza con el error 50312 y el pedido queda como estaba.

| Comprobación                  | Valor | Resultado |
| ----------------------------- | ----- | --------- |
| Cancelar un pedido confirmado | 50312 | OK        |

| Momento                             | Pedido     | Último pago        | Stock real | Stock libre | Resultado |
| ----------------------------------- | ---------- | ------------------ | ---------- | ----------- | --------- |
| Antes: la venta descontó 2 unidades | Confirmado | Aprobado con fecha | 3          | 3           | OK        |
| Después: sin cambios                | Confirmado | Aprobado con fecha | 3          | 3           | OK        |

## Caso 8: pedido Entregado

El pedido del caso 7 pasa de Confirmado a Entregado con un `UPDATE` directo, que el trigger de transiciones admite. Tampoco se puede cancelar: error 50312 y sin cambios.

| Comprobación                 | Valor | Resultado |
| ---------------------------- | ----- | --------- |
| Cancelar un pedido entregado | 50312 | OK        |

| Momento              | Pedido    | Último pago        | Stock real | Stock libre | Resultado |
| -------------------- | --------- | ------------------ | ---------- | ----------- | --------- |
| Después: sin cambios | Entregado | Aprobado con fecha | 3          | 3           | OK        |

## Caso 9: pedido ya Cancelado

El cliente del caso 1 intenta cancelar otra vez el mismo pedido, y el procedimiento lo rechaza con el error 50312.

| Comprobación       | Valor | Resultado |
| ------------------ | ----- | --------- |
| Cancelar dos veces | 50312 | OK        |

## Caso 10: pedido de otro cliente y pedido inexistente

Un cliente intenta cancelar un pedido de 1 unidad de otro cliente, y después el dueño intenta cancelar un pedido inexistente. Los dos intentos reciben el mismo error, 50311, y el pedido ajeno sigue Pendiente con su reserva.

| Comprobación                         | Valor | Resultado |
| ------------------------------------ | ----- | --------- |
| Un cliente cancela un pedido de otro | 50311 | OK        |
| Pedido inexistente                   | 50311 | OK        |

| Momento                     | Pedido    | Último pago | Stock real | Stock libre | Resultado |
| --------------------------- | --------- | ----------- | ---------- | ----------- | --------- |
| El pedido ajeno sigue igual | Pendiente | sin pago    | 5          | 4           | OK        |

## Caso 11: transacciones abiertas

Después de cada llamada a un procedimiento, también de las que fallaron, no quedó ninguna transacción abierta (0).

## Conclusión

`usp_CancelarPedido` cancela solo pedidos Pendientes del cliente que los hizo, incluso con la reserva vencida, y deja el stock real como estaba mientras la reserva se libera. El pago abierto no se toca: si se aprueba después, queda como cobro sin venta, y si se rechaza, solo cambia el pago. Los pedidos Confirmados, Entregados o ya Cancelados se rechazan con 50312, los ajenos o inexistentes con 50311, y un pedido cancelado no admite un pago nuevo (50112). Ninguna llamada dejó una transacción abierta, y la limpieza borró todas las filas de la demostración: la base quedó igual.
