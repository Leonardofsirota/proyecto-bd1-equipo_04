# Demostración: ciclo de venta con reserva de stock

Prueba los procedimientos `usp_CrearPedido`, `usp_IniciarPago` y `usp_RegistrarVenta`, que crean el pedido, inician su pago y registran el resultado que informa la pasarela de pago (el servicio externo que cobra), junto con las funciones `fn_VencimientoReserva` y `fn_StockLibre`. Cubre la reserva y el stock libre (RN12, RN13 y RN33 a RN37) y los pagos, con sus reintentos y el descuento en el importe (RN22, RN24 y RN32). La demostración crea sus propios usuarios, publicaciones, pedidos y pagos, y los borra al terminar. Las pruebas con sesiones simultáneas están en [`concurrencia.md`](concurrencia.md).

**Ejecución:** 2026-10-31, repetida el 2026-11-03 con la versión actual (triggers de consistencia, descuento en el importe del pago y demostración separada de `script.sql`) · SQL Server 2025 Express · base de prueba recién cargada · **53 de 53** comprobaciones correctas

Dos conceptos recorren todos los casos. Un pedido pendiente **reserva** sus unidades durante un plazo, sin descontarlas del stock; el stock se descuenta recién cuando se aprueba el pago. El **stock libre** de una publicación es su stock menos las unidades que reservan otros pedidos vigentes, y es lo único que puede pedirse.

## Resumen

| Caso | Qué se prueba                                          | Comprobaciones | Resultado |
| ---- | ------------------------------------------------------ | -------------- | --------- |
| 1    | Venta exitosa con tarjeta que agota el stock           | 1              | OK        |
| 2    | Rechazo con reintento dentro de los 15 minutos         | 3              | OK        |
| 3    | Reintento con la reserva vencida                       | 2              | OK        |
| 4    | Competencia por la última unidad                       | 4              | OK        |
| 5    | Pago ya procesado                                      | 2              | OK        |
| 6    | Aprobación tardía con stock libre                      | 2              | OK        |
| 7    | Aprobación tardía sin stock libre                      | 2              | OK        |
| 8    | Aprobación con el pedido fuera de Pendiente            | 1              | OK        |
| 9    | Plazos de reserva                                      | 6              | OK        |
| 10   | Validaciones                                           | 14             | OK        |
| 11   | Descuento en el importe del pago                       | 5              | OK        |
| —    | Transacciones abiertas tras cada llamada, una por caso | 11             | OK        |

En las tablas de estado, **Pago** y **Pedido** son los estados al final del caso («con fecha» indica que el pago registró su fecha de acreditación), **Stock** es el stock real de la publicación y **Disponible** indica si sigue a la venta (1) o no (0).

## Caso 1: venta exitosa con tarjeta que agota el stock

Un cliente compra con tarjeta las dos unidades de una publicación y la pasarela aprueba el pago. El pago queda Aprobado con su fecha, el pedido pasa a Confirmado y el stock baja a 0, así que la publicación deja de estar disponible (RN14).

| Comprobación  | Pago               | Pedido     | Stock | Disponible | Resultado |
| ------------- | ------------------ | ---------- | ----- | ---------- | --------- |
| Venta exitosa | Aprobado con fecha | Confirmado | 0     | 0          | OK        |

## Caso 2: rechazo con reintento dentro de los 15 minutos

El primer pago se rechaza: queda Rechazado y sin fecha, y el procedimiento responde «Pago actualizado: el pedido no cambia», porque el pedido sigue Pendiente y su reserva, vigente. Un segundo intento dentro del plazo se aprueba y concreta la venta. Los dos pagos quedan en el historial del pedido (RN24 y RN29).

| Momento           | Pago                | Pedido     | Stock | Disponible | Resultado |
| ----------------- | ------------------- | ---------- | ----- | ---------- | --------- |
| Tras el rechazo   | Rechazado sin fecha | Pendiente  | 3     | 1          | OK        |
| Tras el reintento | Aprobado con fecha  | Confirmado | 2     | 1          | OK        |

| Comprobación                     | Valor | Resultado |
| -------------------------------- | ----- | --------- |
| Pagos en el historial del pedido | 2     | OK        |

## Caso 3: reintento con la reserva vencida

El pago del pedido se rechaza y la reserva vence antes del nuevo intento. Un pedido con la reserva vencida no admite más pagos (RN35), así que el reintento se rechaza con el error 50114. Para comprar, el cliente crea otro pedido: el stock libre solo descuenta la reserva de ese pedido nuevo, porque la del vencido ya no aparta unidades.

| Comprobación                              | Valor       | Resultado |
| ----------------------------------------- | ----------- | --------- |
| Reintento con la reserva vencida          | error 50114 | OK        |
| Stock libre: solo reserva el pedido nuevo | 2           | OK        |

## Caso 4: competencia por la última unidad

Dos clientes quieren la última unidad de una publicación. Mientras la reserva del cliente A está vigente, el stock libre es 0 y el pedido del cliente B se rechaza con el error 50107. Cuando la reserva de A vence, la unidad vuelve a quedar libre y B la reserva. El stock real sigue en 1 todo el tiempo: la reserva aparta la unidad, pero no la descuenta.

| Momento                     | Stock real | Stock libre | Resultado |
| --------------------------- | ---------- | ----------- | --------- |
| Con la reserva de A vigente | 1          | 0           | OK        |
| Con la reserva de A vencida | 1          | 1           | OK        |
| Con la reserva de B         | 1          | 0           | OK        |

| Comprobación                            | Valor       | Resultado |
| --------------------------------------- | ----------- | --------- |
| Cliente B con la unidad reservada por A | error 50107 | OK        |

## Caso 5: pago ya procesado

Una segunda llamada a `usp_RegistrarVenta` sobre el pago ya aprobado del caso 1 se rechaza con el error 50123 y no cambia nada: una venta no puede registrarse dos veces.

| Comprobación                             | Valor       | Resultado |
| ---------------------------------------- | ----------- | --------- |
| Segunda llamada sobre el pago del caso 1 | error 50123 | OK        |

| Comprobación       | Pago               | Pedido     | Stock | Disponible | Resultado |
| ------------------ | ------------------ | ---------- | ----- | ---------- | --------- |
| Estado sin cambios | Aprobado con fecha | Confirmado | 0     | 0          | OK        |

## Caso 6: aprobación tardía con stock libre

La pasarela aprueba el pago cuando la reserva ya venció. Como todavía hay stock libre para todo el pedido, la venta se concreta igual (RN36).

| Comprobación                   | Valor   | Resultado |
| ------------------------------ | ------- | --------- |
| Reserva antes de la aprobación | vencida | OK        |

| Comprobación     | Pago               | Pedido     | Stock | Disponible | Resultado |
| ---------------- | ------------------ | ---------- | ----- | ---------- | --------- |
| Venta registrada | Aprobado con fecha | Confirmado | 0     | 0          | OK        |

## Caso 7: aprobación tardía sin stock libre

La reserva del pedido vence y otro pedido reserva la única unidad. Después, la pasarela aprueba el pago del primer pedido, pero ya no hay stock libre. Es un **cobro sin venta** (RN37): el dinero se cobró, pero no hay venta. El procedimiento no da error: cancela el pago y el pedido, conserva la fecha del pago como rastro del cobro y no toca el stock. Su respuesta lo explica: «Pago aprobado sin stock libre: no hay venta y la devolucion se resuelve fuera del sistema».

| Comprobación                  | Valor     | Resultado |
| ----------------------------- | --------- | --------- |
| Error de la aprobación tardía | sin error | OK        |

| Comprobación                     | Pago                | Pedido    | Stock | Disponible | Resultado |
| -------------------------------- | ------------------- | --------- | ----- | ---------- | --------- |
| Sin venta y con rastro del cobro | Cancelado con fecha | Cancelado | 1     | 1          | OK        |

## Caso 8: aprobación con el pedido fuera de Pendiente

Cuando la pasarela aprueba el pago, el pedido ya no está Pendiente. También es un cobro sin venta (RN37): el pago queda Cancelado con su fecha y el stock no cambia. La respuesta del procedimiento: «Pago aprobado con el pedido fuera de Pendiente: no hay venta y la devolucion se resuelve fuera del sistema».

| Comprobación                     | Pago                | Pedido    | Stock | Disponible | Resultado |
| -------------------------------- | ------------------- | --------- | ----- | ---------- | --------- |
| Sin venta y con rastro del cobro | Cancelado con fecha | Cancelado | 1     | 1          | OK        |

## Caso 9: plazos de reserva

Tres pedidos de la misma publicación miden el plazo de cada reserva (RN34): sin pago, dura 15 minutos desde la creación del pedido; con un pago con tarjeta, 15 minutos desde el inicio del pago, y con una transferencia, 48 horas. Con las tres reservas vigentes, el stock libre es 7. Un pedido con fecha futura no tiene vencimiento y no resta del stock libre, que pasa a 8.

| Comprobación                                    | Valor | Resultado |
| ----------------------------------------------- | ----- | --------- |
| Sin pago: minutos desde fecha_pedido            | 15    | OK        |
| Tarjeta: minutos desde la creación del pago     | 15    | OK        |
| Transferencia: horas desde la creación del pago | 48    | OK        |
| Stock libre con tres reservas vigentes          | 7     | OK        |
| Fecha futura: vencimiento de la reserva         | NULL  | OK        |
| Fecha futura: no resta del stock libre          | 8     | OK        |

## Caso 10: validaciones

Catorce llamadas con datos inválidos, una por cada validación de los tres procedimientos. Cada una se rechazó con el número de error esperado. Una publicación no disponible y la de un vendedor dado de baja comparten el error 50105, porque ninguna de las dos puede agregarse a un pedido (RN12).

| Procedimiento        | Validación                      | Error | Resultado |
| -------------------- | ------------------------------- | ----- | --------- |
| `usp_CrearPedido`    | El usuario no es cliente        | 50101 | OK        |
| `usp_CrearPedido`    | Dirección de otro cliente       | 50102 | OK        |
| `usp_CrearPedido`    | Carrito vacío                   | 50103 | OK        |
| `usp_CrearPedido`    | Cantidad cero                   | 50104 | OK        |
| `usp_CrearPedido`    | Publicación no disponible       | 50105 | OK        |
| `usp_CrearPedido`    | Vendedor dado de baja           | 50105 | OK        |
| `usp_CrearPedido`    | Más unidades que el stock libre | 50107 | OK        |
| `usp_IniciarPago`    | Método inexistente              | 50111 | OK        |
| `usp_IniciarPago`    | Pedido no pendiente             | 50112 | OK        |
| `usp_IniciarPago`    | Pedido con pago pendiente       | 50113 | OK        |
| `usp_IniciarPago`    | Reserva vencida                 | 50114 | OK        |
| `usp_RegistrarVenta` | Resultado no válido             | 50121 | OK        |
| `usp_RegistrarVenta` | Pago inexistente                | 50122 | OK        |
| `usp_RegistrarVenta` | Pago ya procesado               | 50123 | OK        |

## Caso 11: descuento en el importe del pago

Dos pedidos de la misma publicación, a 1000.00 la unidad. El primero, de 100 unidades, suma exactamente 100.000, el límite del tramo del 0 %: no tiene descuento y el pago se inicia por el total. El segundo, de 150 unidades, cae en el tramo del 5 %, y el pago se inicia por el total menos el descuento (RN22 y RN32). Antes de eso, un pago insertado directamente en la tabla por el total sin descuento se rechaza con el error 50234: el importe con descuento se exige aunque no se use el procedimiento. Los dos pagos se aprueban, y el segundo agota el stock.

| Pedido                       | Total     | Porcentaje | Importe del pago | Resultado |
| ---------------------------- | --------- | ---------- | ---------------- | --------- |
| Sin descuento (100 unidades) | 100000.00 | 0.00 %     | 100000.00        | OK        |
| Con descuento (150 unidades) | 150000.00 | 5.00 %     | 142500.00        | OK        |

| Comprobación                                        | Valor       | Resultado |
| --------------------------------------------------- | ----------- | --------- |
| Pago directo por el total sin descuento (150000.00) | error 50234 | OK        |

| Venta registrada | Pago               | Pedido     | Stock | Disponible | Resultado |
| ---------------- | ------------------ | ---------- | ----- | ---------- | --------- |
| Sin descuento    | Aprobado con fecha | Confirmado | 150   | 1          | OK        |
| Con descuento    | Aprobado con fecha | Confirmado | 0     | 0          | OK        |

## Conclusión

Los tres procedimientos recorren el ciclo de venta completo: reservan sin descontar stock, descuentan solo al aprobarse el pago, respetan los plazos de reserva y convierten en cobro sin venta la aprobación que llega sin stock libre o con el pedido fuera de Pendiente, sin perder el rastro del cobro. Cada validación tiene su número de error, y el pago se registra por el total con descuento. Después de cada llamada no quedó ninguna transacción abierta, en los 11 casos. La base quedó igual: las mismas cantidades de filas en USUARIO, PEDIDO y PAGO y el mismo checksum en PUBLICACION, sin filas de la demostración ni triggers deshabilitados.
