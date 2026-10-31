# Pedidos a entregar - Etapa 4

Este documento explica la consulta [`vendedor/pedidos-a-entregar.sql`](../../sql/consultas/vendedor/pedidos-a-entregar.sql), que resuelve el caso de uso [Consultar pedidos a entregar](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Lista los renglones que un vendedor todavía debe entregar: sus libros en pedidos con pago aprobado que siguen confirmados. Muestra el cliente, la dirección de envío, el detalle de cada libro y el total que le corresponde en cada pedido, del pago más antiguo al más reciente.

Un pedido puede incluir libros de varios vendedores (RN16): solo se muestran los renglones del vendedor indicado. Si no tiene nada para entregar, la consulta no devuelve filas.

## 2. Quién la usa

El **Vendedor**, para preparar y despachar lo que ya se cobró.

## 3. Cómo lo resuelve

- **Vendedor elegido:** se indica con la variable `@vendedor_id`.
- **Uniones:** une el pedido con su estado, su pago aprobado, su cliente, la ciudad y la provincia de entrega y sus renglones; de cada renglón llega al libro y a la condición a través de la publicación.
- **Qué falta entregar:** el `WHERE` pide un pago aprobado y un pedido confirmado. Es la única consulta sobre [ventas](casos-uso.md#3-qué-se-considera-una-venta) que filtra por el estado del pedido, porque necesita separar lo cobrado y sin entregar de lo ya entregado.
- **Dirección de envío:** es la copia guardada en el pedido, no la dirección actual del cliente (RN27). `CONCAT` reúne sus partes y omite el piso y el departamento si faltan.
- **Total del vendedor:** `SUM(...) OVER (PARTITION BY ...)` conserva el detalle de cada renglón. Como la función de ventana se calcula después del `WHERE`, suma solo los renglones del vendedor y no el total del pedido.
- **Fecha de venta:** es la de aprobación del pago, y ordena los pedidos para entregar primero los que se cobraron antes.

## 4. Resultado esperado

Con `@vendedor_id = 25` devuelve los tres renglones del pedido 586, vendido el 26 de diciembre de 2026 a Gabriela Bogado Godoy, con envío a Av. Libertador 577, Paso de la Patria:

| Publicación | Libro                             | Condición | Cantidad | Precio unitario | Subtotal |
| ----------: | --------------------------------- | --------- | -------: | --------------: | -------: |
|         338 | El túnel                          | Nuevo     |        1 |         $22.000 |  $22.000 |
|         528 | Macbeth                           | Nuevo     |        1 |         $21.000 |  $21.000 |
|          35 | El amor en los tiempos del cólera | Nuevo     |        1 |         $26.900 |  $26.900 |

El total del vendedor, $69.900, se repite en los tres renglones. El pedido completo suma $124.400: los $54.500 restantes corresponden a otro vendedor.
