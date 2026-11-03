# Concurrencia: cancelación y aprobación simultáneas del mismo pedido

Una prueba de concurrencia lanza varias operaciones a la vez sobre los mismos datos. Aquí se disputan una cancelación con `usp_CancelarPedido`, de [`script.sql`](../script.sql), y la aprobación del pago del mismo pedido con `usp_RegistrarVenta`: el pedido debe terminar vendido o cancelado, nunca en un estado mixto. En A y B, una sesión retiene la fila del pedido 3 segundos y las dos llamadas se atienden en orden de llegada. En C no se retiene nada y las 20 llamadas, dos por pedido, arrancan a la vez. La demostración de una sola sesión está en [`demostracion.md`](demostracion.md).

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **3 de 3** casos correctos · 0 deadlocks y 0 errores fuera del `TRY`

## Resumen

| Caso | Escenario                    | Resultado clave                                    | Resultado |
| ---- | ---------------------------- | -------------------------------------------------- | --------- |
| A    | La aprobación llega primero  | Venta y cancelación rechazada con 50312            | OK        |
| B    | La cancelación llega primero | Pedido cancelado y aprobación como cobro sin venta | OK        |
| C    | Carrera libre de 10 pedidos  | 5 Confirmados, 5 Cancelados y 0 mixtos             | OK        |

## Caso A: la aprobación llega primero

Un pedido de 2 unidades tiene un pago Pendiente. Con la fila del pedido retenida, llegan primero la aprobación y medio segundo después la cancelación, y las dos quedan esperando. Gana la aprobación: se registra la venta, el pedido queda Confirmado y el stock baja 2 unidades. La cancelación encuentra el pedido ya Confirmado y recibe el error 50312.

| Dato                | Valor                                                                            |
| ------------------- | -------------------------------------------------------------------------------- |
| Llamadas            | `usp_RegistrarVenta` con Aprobado y, medio segundo después, `usp_CancelarPedido` |
| Sesiones bloqueadas | 2                                                                                |
| Pago                | Aprobado con fecha                                                               |
| Pedido              | Confirmado                                                                       |
| Stock               | 2 menos (de 1000 a 998)                                                          |
| Aprobación          | sin error                                                                        |
| Errores 50312       | 1, de la cancelación                                                             |

## Caso B: la cancelación llega primero

El mismo escenario, con el orden invertido. Gana la cancelación: el pedido queda Cancelado. La aprobación que llega después termina sin error, pero como cobro sin venta: el pago queda Cancelado con fecha como rastro del cobro (RN37) y el stock no cambia.

| Dato                | Valor                                                                            |
| ------------------- | -------------------------------------------------------------------------------- |
| Llamadas            | `usp_CancelarPedido` y, medio segundo después, `usp_RegistrarVenta` con Aprobado |
| Sesiones bloqueadas | 2                                                                                |
| Pago                | Cancelado con fecha                                                              |
| Pedido              | Cancelado                                                                        |
| Stock               | igual (998)                                                                      |
| Cancelación         | sin error                                                                        |
| Aprobación          | sin error                                                                        |
| Errores             | ninguno                                                                          |

## Caso C: carrera libre

Diez pedidos de 1 unidad, cada uno con un pago Pendiente. Para cada pedido, una cancelación y una aprobación arrancan a la vez, sin ninguna fila retenida que las ordene. Cada pedido terminó coherente: 5 Confirmados con el pago Aprobado y 5 Cancelados con el pago Cancelado con fecha (RN37), ninguno mixto. Cada pedido Confirmado tiene su cancelación rechazada con 50312, y el stock bajó exactamente lo vendido.

| Dato               | Valor                                                     |
| ------------------ | --------------------------------------------------------- |
| Llamadas           | 20, una cancelación y una aprobación por pedido, a la vez |
| Pedidos coherentes | 10                                                        |
| Pedidos mixtos     | 0                                                         |
| Confirmados        | 5, con el pago Aprobado                                   |
| Cancelados         | 5, con el pago Cancelado con fecha                        |
| Stock              | de 998 a 993, el inicial menos los Confirmados            |
| Errores 50312      | 5, uno por Confirmado                                     |
| Otros errores      | ninguno                                                   |

## Conclusión

Frente a una aprobación simultánea gana quien bloquea primero la fila del pedido, y la otra operación termina de forma coherente: la cancelación tardía recibe 50312, y la aprobación tardía queda como cobro sin venta. En la carrera libre, los 10 pedidos terminaron confirmados o cancelados, nunca en un estado mixto, con el stock exacto. El servidor no registró ningún deadlock durante la prueba, y ninguna sesión tuvo errores fuera del `TRY`.
