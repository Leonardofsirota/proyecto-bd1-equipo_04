# Pedidos del cliente - Etapa 4

Este documento explica la consulta [`cliente/pedidos-del-cliente.sql`](../../sql/consultas/cliente/pedidos-del-cliente.sql), que resuelve el caso de uso [Consultar pedidos del cliente](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Muestra el historial de pedidos de un cliente, del más reciente al más antiguo. De cada uno indica la fecha, el estado, la cantidad de libros, el total y el resultado de su último intento de pago.

Incluye los pedidos cancelados y los que todavía no registran ningún pago, que muestran «Sin pago». Si el cliente no hizo pedidos, la consulta no devuelve filas.

## 2. Quién la usa

El **Cliente**, para ver qué pedidos le falta pagar, cuáles esperan la entrega y cuáles ya recibió.

## 3. Cómo lo resuelve

- **Cliente elegido:** se indica con la variable `@cliente_id`.
- **Uniones:** une el pedido con su estado y sus renglones.
- **Cantidad y total:** `GROUP BY` por pedido; `SUM` acumula las unidades y la cantidad × precio unitario de cada renglón (RN17).
- **Último intento:** `OUTER APPLY` ejecuta, para cada pedido, una subconsulta que toma su pago más reciente con `TOP 1`. Funciona como un `LEFT JOIN`, así que conserva los pedidos sin pagos, y `COALESCE` les muestra «Sin pago». Si el pedido tiene un pago aprobado, es ese, porque después de uno aprobado no se registran más intentos (RN24).
- **Fecha de pago:** solo aparece si el último intento acreditó un cobro (RN25). Si ese intento figura cancelado, es un cobro que no concretó la venta (RN37).
- **Orden:** por fecha del pedido y, a igual fecha, por número.

## 4. Resultado esperado

Con `@cliente_id = 347` devuelve tres pedidos:

| Pedido | Fecha      | Estado    | Libros |    Total | Último pago | Método de pago     |
| -----: | ---------- | --------- | -----: | -------: | ----------- | ------------------ |
|    584 | 26/12/2026 | Pendiente |      4 | $128.300 | Sin pago    | —                  |
|    533 | 30/11/2026 | Entregado |      5 | $104.900 | Aprobado    | Tarjeta de crédito |
|    103 | 10/03/2026 | Entregado |      2 |  $33.200 | Aprobado    | Transferencia      |
