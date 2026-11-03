# Concurrencia: ciclo de venta con sesiones simultáneas

Una prueba de concurrencia lanza varias operaciones a la vez sobre los mismos datos, para comprobar que los procedimientos de [`script.sql`](../script.sql) no venden dos veces la misma unidad, no duplican pedidos, pagos ni ventas y no se traban entre sí. Las sesiones son `sqlcmd` en paralelo, sincronizadas para llamar al mismo tiempo; en A, B y C una sesión retiene 3 segundos la fila disputada, para que las demás lleguen juntas. La demostración de una sola sesión está en [`demostracion.md`](demostracion.md).

**Ejecución:** 2026-11-01 · SQL Server 2025 Express · base de prueba recién cargada · **5 de 5** casos correctos · 0 deadlocks y 0 errores fuera del `TRY`

## Resumen

| Caso | Escenario                                            | Resultado clave               | Resultado |
| ---- | ---------------------------------------------------- | ----------------------------- | --------- |
| A    | 8 pedidos por la última unidad                       | 1 pedido y 7 errores 50107    | OK        |
| B    | 8 pagos para el mismo pedido                         | 1 pago y 7 errores 50113      | OK        |
| C    | 8 aprobaciones del mismo pago                        | 1 venta y 7 errores 50123     | OK        |
| D    | Operaciones mezcladas sobre las mismas publicaciones | 240 ventas, sin interbloqueos | OK        |
| E    | Sesiones con publicaciones distintas                 | 320 ventas, sin interbloqueos | OK        |

## Caso A: última unidad

Ocho sesiones intentan crear un pedido por la única unidad de una publicación. Una sola lo consigue; las otras siete esperan a que se libere la fila y, al encontrar la unidad reservada, reciben el error 50107 (más unidades que el stock libre). El stock real sigue en 1, porque la reserva no lo descuenta.

| Dato             | Valor               |
| ---------------- | ------------------- |
| Llamadas         | 8 `usp_CrearPedido` |
| Pedidos creados  | 1                   |
| Errores 50107    | 7                   |
| Stock real final | 1                   |

## Caso B: pagos simultáneos del mismo pedido

Ocho sesiones intentan iniciar un pago para el mismo pedido pendiente y con la reserva vigente. Solo una lo inicia; las demás reciben el error 50113, porque el pedido ya tiene un pago pendiente. Un pedido nunca tiene dos pagos en curso.

| Dato          | Valor               |
| ------------- | ------------------- |
| Llamadas      | 8 `usp_IniciarPago` |
| Pagos creados | 1                   |
| Errores 50113 | 7                   |

## Caso C: aprobaciones simultáneas del mismo pago

Ocho sesiones registran a la vez la aprobación del mismo pago pendiente, por 2 unidades de una publicación con stock 10. Solo una registra la venta; las otras siete reciben el error 50123 (pago ya procesado). El pedido queda Confirmado y el stock se descuenta una sola vez.

| Dato          | Valor                               |
| ------------- | ----------------------------------- |
| Llamadas      | 8 `usp_RegistrarVenta` con Aprobado |
| Ventas        | 1                                   |
| Errores 50123 | 7                                   |
| Pedido        | Confirmado                          |
| Stock final   | 8                                   |

## Caso D: operaciones mezcladas sobre las mismas publicaciones

Ocho sesiones repiten 40 veces operaciones distintas sobre dos publicaciones con stock de sobra: cuatro hacen la venta completa, dos un rechazo con reintento y dos solo reservan. Las sesiones compiten todo el tiempo por las mismas filas y aun así no hubo ningún interbloqueo (error 1205): cada venta quedó registrada y el stock de cada publicación es el inicial menos lo vendido.

| Dato                                                          | Valor                                                                |
| ------------------------------------------------------------- | -------------------------------------------------------------------- |
| Sesiones                                                      | 8, de 40 iteraciones                                                 |
| Mezcla                                                        | 4 con venta completa, 2 con rechazo y reintento, 2 con solo reservas |
| Publicaciones                                                 | 2, con stock 100000                                                  |
| Pedidos                                                       | 320                                                                  |
| Ventas                                                        | 240                                                                  |
| Errores 1205                                                  | 0                                                                    |
| Ventas sin registrar                                          | 0                                                                    |
| Publicaciones con stock distinto del inicial menos lo vendido | 0                                                                    |
| Otros errores                                                 | ninguno                                                              |

## Caso E: sesiones con publicaciones distintas

Ocho sesiones hacen 40 ventas completas cada una, cada sesión con su propia publicación. Como no comparten la fila de la publicación, nada las ordena antes de llegar a las tablas que sí comparten: `PEDIDO`, `PEDIDO_DETALLE` y `PAGO`. Tampoco hubo interbloqueos: las 320 ventas se registraron y el stock de cada publicación es el inicial menos lo vendido.

| Dato                                                          | Valor                                   |
| ------------------------------------------------------------- | --------------------------------------- |
| Sesiones                                                      | 8, de 40 iteraciones con venta completa |
| Publicaciones                                                 | 8, una por sesión, con stock 100000     |
| Pedidos                                                       | 320                                     |
| Ventas                                                        | 320                                     |
| Errores 1205                                                  | 0                                       |
| Publicaciones con stock distinto del inicial menos lo vendido | 0                                       |
| Otros errores                                                 | ninguno                                 |

## Conclusión

En cada carrera por la misma fila hubo un solo ganador entre 8 llamadas, y las otras siete recibieron el error que corresponde: un solo pedido por la última unidad, un solo pago por pedido y una sola venta por pago. Las cargas mixtas terminaron sin interbloqueos (0 errores 1205), sin ventas perdidas y con el stock exacto. El servidor no registró ningún deadlock durante la prueba, y ninguna sesión tuvo errores fuera del `TRY`.
