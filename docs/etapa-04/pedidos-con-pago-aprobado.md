# Pedidos con pago aprobado - Etapa 4

Este documento explica la consulta [`pagos/pedidos-con-pago-aprobado.sql`](../../sql/consultas/pagos/pedidos-con-pago-aprobado.sql), que resuelve el caso de uso [Consultar pedidos con pago aprobado](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Lista los pedidos ya cobrados, uno por fila y ordenados por número. De cada uno muestra el cliente, el estado del pedido, el importe pagado y el método de pago.

## 2. Quién la usa

- **Vendedor:** para saber qué pedidos ya se cobraron. Los que siguen confirmados son los que todavía falta entregar.
- **Administrador:** para controlar los cobros del marketplace y cómo se pagaron.

## 3. Cómo lo resuelve

- **Uniones:** une el cliente con sus pedidos, cada pedido con su estado y con sus pagos, y cada pago con su estado y su método.
- **Filtro:** el `WHERE` deja solo los pagos aprobados. Como un pedido tiene a lo sumo uno, ningún pedido se repite.
- **Importe:** es el del pago aprobado, que coincide con el total del pedido (RN22).

## 4. Resultado esperado

Devuelve 567 de los 600 pedidos: 555 entregados y 12 confirmados. Las primeras filas son:

| Pedido | Cliente           | Estado del pedido | Importe | Método de pago     |
| -----: | ----------------- | ----------------- | ------: | ------------------ |
|      1 | Jorge Suárez      | Entregado         | $35.000 | Tarjeta de crédito |
|      2 | Ariel Castro      | Entregado         | $37.100 | Tarjeta de débito  |
|      3 | Walter Raúl López | Entregado         | $38.400 | Tarjeta de débito  |

Los 33 pedidos restantes son los que lista [Pedidos sin pago aprobado](pedidos-sin-pago-aprobado.md).
