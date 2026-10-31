# Pedidos sin pago aprobado - Etapa 4

Este documento explica la consulta [`administrador/pedidos-sin-pago-aprobado.sql`](../../sql/consultas/administrador/pedidos-sin-pago-aprobado.sql), que resuelve el caso de uso [Consultar pedidos sin pago aprobado](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Lista los pedidos sin un pago aprobado, que por lo tanto no son [ventas](casos-uso.md#3-qué-se-considera-una-venta), del más antiguo al más reciente. De cada uno muestra la fecha, el cliente, el estado del pedido, el total y cómo terminó su último intento de pago, o «Sin pago» si no tiene ninguno.

Es el complemento de [Pedidos con pago aprobado](pedidos-con-pago-aprobado.md): entre las dos consultas aparecen todos los pedidos, cada uno una sola vez.

## 2. Quién la usa

El **Administrador**, para seguir los pedidos con pagos pendientes, rechazados o cancelados.

## 3. Cómo lo resuelve

- **Uniones:** une el pedido con su cliente, su estado y sus renglones.
- **Filtro:** un `NOT EXISTS` descarta los pedidos que tienen un pago aprobado. Se filtra por pedido y no por pago: si un pedido tuvo un intento rechazado y después uno aprobado, no aparece.
- **Total:** como no hay un pago aprobado del cual tomar el importe, se calcula a partir del detalle, con `SUM` y `GROUP BY` por pedido (RN17).
- **Último intento:** una subconsulta en el `SELECT` busca, para cada pedido, el estado de su pago más reciente. Si el pedido no tiene pagos, `COALESCE` muestra «Sin pago». Así el pedido aparece una sola vez aunque tenga varios intentos.
- **Cobros sin venta:** un pago aprobado sin stock libre para todo el pedido queda cancelado, y su pedido también (RN37). Ese pedido aparece aquí con el estado «Cancelado» en ambas columnas, aunque se le haya cobrado: la consulta no lo distingue de otra cancelación.

## 4. Resultado esperado

Devuelve 33 pedidos:

| Estado del pedido | Último intento de pago | Pedidos |
| ----------------- | ---------------------- | ------: |
| Cancelado         | Cancelado              |      10 |
| Cancelado         | Rechazado              |       4 |
| Cancelado         | Sin pago               |       5 |
| Pendiente         | Pendiente              |       4 |
| Pendiente         | Rechazado              |       2 |
| Pendiente         | Sin pago               |       8 |
