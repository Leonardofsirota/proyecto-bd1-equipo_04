# Pagos por método - Etapa 4

Este documento explica la consulta [`administrador/pagos-por-metodo.sql`](../../sql/consultas/administrador/pagos-por-metodo.sql), que resuelve el caso de uso [Consultar pagos por método](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Resume, por método de pago, los intentos iniciados en un rango de fechas: cuántos hubo, cuántos se aprobaron, rechazaron, cancelaron o siguen pendientes, qué porcentaje se aprobó y qué importe sumaron los aprobados. El orden va del método con más intentos al de menos, y un método sin intentos en el período aparece en cero.

## 2. Quién la usa

El **Administrador**, para detectar un método que concentre los rechazos (RN21, RN23, RN29).

## 3. Cómo lo resuelve

- **Período:** se indica con `@fecha_desde` y `@fecha_hasta`, y se compara con la fecha de inicio del intento, porque los rechazados y los cancelados sin cobro no tienen fecha de acreditación (RN25). Como esa fecha incluye la hora, el filtro llega hasta antes del día siguiente a `@fecha_hasta`, para tomar el último día completo.
- **Uniones:** `LEFT JOIN` del método a sus pagos y de cada pago a su estado. El filtro de fechas va en el `ON`: en el `WHERE` eliminaría los métodos sin intentos en el período.
- **Conteos:** `COUNT` cuenta los intentos, y un `SUM(CASE ...)` por estado separa cuántos terminaron de cada forma. Se cuentan intentos, no pedidos: un pedido puede aportar varios (RN24).
- **Porcentaje de aprobados:** divide los aprobados por los intentos. `NULLIF` evita dividir por cero, y sin intentos el porcentaje queda vacío.
- **Importe aprobado:** suma solo los pagos aprobados. Puede diferir de los reportes de ventas, que usan la fecha de aprobación: un pago iniciado al final del rango puede aprobarse en el período siguiente.
- **Cobros sin venta:** un pago cancelado con fecha de acreditación (RN37) cuenta entre los cancelados y no suma al importe aprobado.

## 4. Resultado esperado

Con el año 2026 completo devuelve los tres métodos:

| Método             | Intentos | Aprobados | Rechazados | Cancelados | Pendientes | % aprobados | Importe aprobado |
| ------------------ | -------: | --------: | ---------: | ---------: | ---------: | ----------: | ---------------: |
| Tarjeta de crédito |      310 |       255 |         44 |         11 |          0 |     82,26 % |      $18.439.300 |
| Transferencia      |      205 |       154 |          0 |         47 |          4 |     75,12 % |      $11.117.700 |
| Tarjeta de débito  |      203 |       158 |         33 |         12 |          0 |     77,83 % |       $9.282.000 |

Los 718 intentos son todos los pagos cargados. En este rango, el importe aprobado suma $38.839.000, igual que [Ventas por mes](ventas-por-mes.md).
