# Comprobante de venta - Etapa 4

Este documento explica la consulta [`cliente/factura-comprobante.sql`](../../sql/consultas/cliente/factura-comprobante.sql), que resuelve el caso de uso [Consultar comprobante de venta](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Arma el comprobante de una venta. El encabezado muestra el número de venta, la fecha, el método de pago y el cliente. El detalle tiene un renglón por cada libro comprado, con su cantidad, precio unitario y subtotal, y el total de la venta.

Si el pedido indicado no es una [venta](casos-uso.md#3-qué-se-considera-una-venta), la consulta no devuelve filas.

## 2. Quién la usa

El **Cliente**, como constancia de una compra ya pagada: qué compró, a qué precio y cuánto pagó en total.

## 3. Cómo lo resuelve

- **Venta elegida:** se indica con la variable `@pedido_id`.
- **Uniones:** une el pedido con su pago aprobado, el método de pago, el cliente y los renglones; de cada renglón llega al libro a través de la publicación.
- **Precio histórico:** usa el precio guardado en el renglón al momento de la compra, no el precio actual de la publicación. Así, el comprobante no cambia si el vendedor modifica su precio después (RN26).
- **Fecha de venta:** es la de aprobación del pago, no la de creación del pedido. Es el mismo [criterio](casos-uso.md#3-qué-se-considera-una-venta) con que los reportes de ventas ubican cada venta en un período.
- **Subtotal y total:** el subtotal es cantidad × precio unitario. El total suma los subtotales con `SUM(...) OVER (PARTITION BY ...)`, una función de ventana: suma sin agrupar, así cada renglón conserva su detalle y además muestra el total (RN17).
- **Renglones:** `ROW_NUMBER()` los numera desde 1.

## 4. Resultado esperado

Con `@pedido_id = 151`, la venta del 3 de abril de 2026 a Diego Ojeda, pagada por transferencia:

| Renglón | Libro                                | Cantidad | Precio unitario | Subtotal |
| ------: | ------------------------------------ | -------: | --------------: | -------: |
|       1 | It                                   |        1 |         $16.500 |  $16.500 |
|       2 | Las venas abiertas de América Latina |        1 |         $19.900 |  $19.900 |

El total, $36.400, se repite en los dos renglones. Los datos del encabezado también se repiten en cada uno, porque la consulta devuelve una sola tabla.
