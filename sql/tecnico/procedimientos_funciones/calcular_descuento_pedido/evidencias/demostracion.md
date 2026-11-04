# Demostración: cálculo del descuento por volumen

Prueba las funciones `fn_TotalPedido`, `fn_PorcentajeDescuentoPedido`, `fn_ImporteDescuento` y `fn_DescuentoRenglon`, que calculan el total de un pedido, su porcentaje de descuento por tramo, el importe de ese descuento y la parte que le toca a cada renglón. Cubren el total calculado (RN17) y el descuento por volumen, que se calcula y no se almacena (RN30 a RN32). La demostración solo consulta pedidos de los datos de prueba: no escribe en la base.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **7 de 7** consultas coinciden con lo esperado

## Resumen

| Caso | Qué se prueba                             | Consultas | Resultado |
| ---- | ----------------------------------------- | --------- | --------- |
| 1    | Tramos de descuento                       | 3         | OK        |
| 2    | Pedido cancelado de más de 100.000        | 1         | OK        |
| 3    | Pedido inexistente                        | 1         | OK        |
| 4    | Reparto del descuento entre los renglones | 1         | OK        |
| 5    | Renglón inexistente                       | 1         | OK        |

## Caso 1: tramos de descuento

Un pedido de cada tramo: hasta 100.000 no hay descuento, hasta 200.000 corresponde el 5 % y por encima, el 10 %. En los tres pedidos, el porcentaje y el importe del descuento son los que fija la regla.

| Pedido | Total     | Porcentaje | Descuento | Resultado |
| ------ | --------- | ---------- | --------- | --------- |
| 1      | 35000.00  | 0.00 %     | 0.00      | OK        |
| 15     | 100700.00 | 5.00 %     | 5035.00   | OK        |
| 18     | 203600.00 | 10.00 %    | 20360.00  | OK        |

## Caso 2: pedido cancelado de más de 100.000

Un pedido cancelado no recibe descuento, aunque su total supere 100.000: las funciones devuelven 0 % y un descuento de 0.00.

| Pedido | Estado    | Total     | Porcentaje | Descuento | Resultado |
| ------ | --------- | --------- | ---------- | --------- | --------- |
| 62     | Cancelado | 127400.00 | 0.00 %     | 0.00      | OK        |

## Caso 3: pedido inexistente

Para un pedido que no existe, la función del porcentaje devuelve 0.00 en lugar de fallar.

| Consulta                          | Valor | Resultado |
| --------------------------------- | ----- | --------- |
| `fn_PorcentajeDescuentoPedido(0)` | 0.00  | OK        |

## Caso 4: reparto del descuento entre los renglones

El descuento del pedido del tramo del 5 % (5035.00) se reparte entre sus tres renglones, en proporción al subtotal de cada uno. Las partes suman exactamente el descuento del pedido, y lo cobrado por renglón suma el importe del pago aprobado del pedido. Por eso un reporte que suma ventas por renglón coincide con lo cobrado.

| Renglón | Subtotal | Descuento | Cobrado  |
| ------- | -------- | --------- | -------- |
| 31      | 19600.00 | 980.00    | 18620.00 |
| 32      | 18400.00 | 920.00    | 17480.00 |
| 33      | 62700.00 | 3135.00   | 59565.00 |

| Comprobación                                           | Valor                    | Resultado |
| ------------------------------------------------------ | ------------------------ | --------- |
| Descuento de cada renglón                              | 980.00, 920.00 y 3135.00 | OK        |
| Suma de los descuentos, igual al descuento del pedido  | 5035.00                  | OK        |
| Suma de lo cobrado, igual al importe del pago aprobado | 95665.00                 | OK        |

## Caso 5: renglón inexistente

Para un renglón que no existe, la función del reparto devuelve NULL en lugar de fallar.

| Consulta                 | Valor | Resultado |
| ------------------------ | ----- | --------- |
| `fn_DescuentoRenglon(0)` | NULL  | OK        |

## Conclusión

Las funciones aplican los tres tramos del descuento, incluido el límite de 100.000, y no descuentan nada a un pedido cancelado. El reparto por renglón suma exactamente el descuento del pedido, y lo cobrado por renglón, el importe del pago aprobado. Ante un pedido o un renglón inexistente devuelven 0.00 o NULL, sin error. La demostración solo lee: la base quedó igual.
