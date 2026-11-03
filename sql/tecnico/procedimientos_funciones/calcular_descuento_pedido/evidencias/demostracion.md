# Demostración de `calcular_descuento_pedido/demostracion.sql`

- **Fecha:** 2026-11-03 09:38
- **Repetición:** 2026-11-03, enseguida y sobre la misma base: salida idéntica.
- **Base temporal:** `tmp_validacion_pf`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más `abm_categorias/script.sql`
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Lo esperado es lo que anotan los comentarios de la demostración. `sqlcmd` muestra los decimales en cero como `.00`; acá figuran como `0.00`.

## Resumen

| Consultas | Coinciden con lo esperado | No coinciden |
| --------- | ------------------------- | ------------ |
| 7         | 7                         | 0            |

## Caso 1: tramos de descuento

Una consulta por tramo, con los pedidos 1, 15 y 18.

| pedido_id | PorcentajeDescuento | TotalPedido | ImporteDescuento |
| --------- | ------------------- | ----------- | ---------------- |
| 1         | 0.00                | 35000.00    | 0.00             |
| 15        | 5.00                | 100700.00   | 5035.00          |
| 18        | 10.00               | 203600.00   | 20360.00         |

**Comprobaciones**

| Comprobación               | Esperado                              | Obtenido                                       | Resultado |
| -------------------------- | ------------------------------------- | ---------------------------------------------- | --------- |
| Tramo del 0 % (pedido 1)   | total 35000 / 0 % / descuento 0       | total 35000.00 / 0.00 % / descuento 0.00       | OK        |
| Tramo del 5 % (pedido 15)  | total 100700 / 5 % / descuento 5035   | total 100700.00 / 5.00 % / descuento 5035.00   | OK        |
| Tramo del 10 % (pedido 18) | total 203600 / 10 % / descuento 20360 | total 203600.00 / 10.00 % / descuento 20360.00 | OK        |

## Caso 2: pedido cancelado de más de 100.000

| pedido_id | Estado    | PorcentajeDescuento | TotalPedido | ImporteDescuento |
| --------- | --------- | ------------------- | ----------- | ---------------- |
| 62        | Cancelado | 0.00                | 127400.00   | 0.00             |

**Comprobaciones**

| Comprobación          | Esperado          | Obtenido                                     | Resultado |
| --------------------- | ----------------- | -------------------------------------------- | --------- |
| Pedido cancelado (62) | 0 % / descuento 0 | 0.00 % / descuento 0.00, con total 127400.00 | OK        |

## Caso 3: pedido inexistente

| PorcentajeDescuento |
| ------------------- |
| 0.00                |

**Comprobaciones**

| Comprobación                      | Esperado | Obtenido | Resultado |
| --------------------------------- | -------- | -------- | --------- |
| `fn_PorcentajeDescuentoPedido(0)` | 0        | 0.00     | OK        |

## Caso 4: reparto del descuento del pedido 15

| pedido_detalle_id | Subtotal | DescuentoRenglon | Cobrado  |
| ----------------- | -------- | ---------------- | -------- |
| 31                | 19600.00 | 980.00           | 18620.00 |
| 32                | 18400.00 | 920.00           | 17480.00 |
| 33                | 62700.00 | 3135.00          | 59565.00 |

**Comprobaciones**

| Comprobación           | Esperado                            | Obtenido                                                                     | Resultado |
| ---------------------- | ----------------------------------- | ---------------------------------------------------------------------------- | --------- |
| Descuento por renglón  | 980 / 920 / 3135                    | 980.00 / 920.00 / 3135.00                                                    | OK        |
| Suma de los descuentos | 5035, el descuento del pedido       | 5035.00                                                                      | OK        |
| Suma de lo cobrado     | 95665, el importe del pago aprobado | 95665.00; el pago 19 del pedido está Aprobado por 95665.00 (consulta aparte) | OK        |

## Caso 5: renglón inexistente

| DescuentoRenglon |
| ---------------- |
| NULL             |

**Comprobaciones**

| Comprobación             | Esperado | Obtenido | Resultado |
| ------------------------ | -------- | -------- | --------- |
| `fn_DescuentoRenglon(0)` | NULL     | NULL     | OK        |
