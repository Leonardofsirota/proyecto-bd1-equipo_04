# Pedidos a entregar - Etapa 4

Este documento explica la consulta [`vendedor/pedidos-a-entregar.sql`](../../sql/consultas/vendedor/pedidos-a-entregar.sql), que resuelve el caso de uso [Consultar pedidos a entregar](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Lista los renglones que un vendedor todavía debe entregar: sus libros en pedidos con pago aprobado que siguen confirmados. Muestra el cliente, la dirección de envío, el detalle de cada libro y el total que le corresponde en cada pedido, del pago más antiguo al más reciente.

Un pedido puede incluir libros de varios vendedores (RN16): solo se muestran los renglones del vendedor indicado. Si no tiene nada para entregar, la consulta no devuelve filas.

El total del vendedor es lo cobrado por sus renglones: el descuento no modifica el total del pedido, pero reduce el importe cobrado (RN32), así que cada renglón muestra su parte del descuento y el total la resta.

## 2. Quién la usa

El **Vendedor**, para preparar y despachar lo que ya se cobró.

## 3. Cómo lo resuelve

- **Vendedor elegido:** se indica con la variable `@vendedor_id`.
- **Uniones:** une el pedido con su estado, su pago aprobado, su cliente, la ciudad y la provincia de entrega y sus renglones; de cada renglón llega al libro y a la condición a través de la publicación.
- **Qué falta entregar:** el `WHERE` pide un pago aprobado y un pedido confirmado. Es la única consulta sobre [ventas](casos-uso.md#3-qué-se-considera-una-venta) que filtra por el estado del pedido, porque necesita separar lo cobrado y sin entregar de lo ya entregado.
- **Dirección de envío:** es la copia guardada en el pedido, no la dirección actual del cliente (RN27). `CONCAT` reúne sus partes y omite el piso y el departamento si faltan.
- **Descuento:** un pedido tiene un solo descuento, aunque incluya libros de varios vendedores (RN30). `dbo.fn_DescuentoRenglon` calcula la parte de cada renglón en proporción a su subtotal, y las partes de un pedido suman exactamente su descuento. La función se crea en [`calcular_descuento_pedido/script.sql`](../../sql/tecnico/procedimientos_funciones/calcular_descuento_pedido/script.sql), de la Etapa 5, que debe ejecutarse antes que esta consulta.
- **Total del vendedor:** `SUM(...) OVER (PARTITION BY ...)` suma el subtotal menos el descuento de cada renglón y conserva el detalle. Como la función de ventana se calcula después del `WHERE`, suma solo los renglones del vendedor y no el total del pedido.
- **Fecha de venta:** es la de aprobación del pago, y ordena los pedidos para entregar primero los que se cobraron antes.

## 4. Resultado esperado

Con `@vendedor_id = 25` devuelve los tres renglones del pedido 586, vendido el 26 de diciembre de 2026 a Gabriela Bogado Godoy, con envío a Av. Libertador 577, Paso de la Patria:

| Publicación | Libro                             | Condición | Cantidad | Precio unitario | Subtotal | Descuento |
| ----------: | --------------------------------- | --------- | -------: | --------------: | -------: | --------: |
|         338 | El túnel                          | Nuevo     |        1 |         $22.000 |  $22.000 |    $1.100 |
|         528 | Macbeth                           | Nuevo     |        1 |         $21.000 |  $21.000 |    $1.050 |
|          35 | El amor en los tiempos del cólera | Nuevo     |        1 |         $26.900 |  $26.900 |    $1.345 |

El total del vendedor, $66.405, se repite en los tres renglones: sus subtotales suman $69.900, menos $3.495 de descuento. El pedido completo suma $124.400, así que tiene un descuento del 5 % (RN30): $6.220. Los $54.500 restantes corresponden a otro vendedor, y su parte del descuento, $2.725, completa el del pedido. El pago aprobado fue de $118.180.
