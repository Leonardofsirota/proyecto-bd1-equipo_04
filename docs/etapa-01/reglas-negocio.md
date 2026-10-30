# Reglas de negocio - Etapa 1

Este documento define las reglas que el sistema debe respetar, agrupadas por área. Cada regla tiene un identificador para poder referenciarla en las etapas siguientes.

Se usa _pedido_ para referirse a la compra que realiza un cliente.

## 1. Usuarios y clientes

| ID   | Regla                    | Descripción                                                                                                                            |
| ---- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| RN01 | Rol único                | Cada usuario tiene exactamente un rol: administrador, vendedor o cliente.                                                              |
| RN02 | Gestión de roles         | Solo el administrador puede modificar el rol de un usuario.                                                                            |
| RN03 | Datos de registro        | Todo usuario registra nombre, apellido, DNI, email, teléfono, fecha de nacimiento y contraseña. El DNI y el email no pueden repetirse. |
| RN04 | Pedidos solo de clientes | Solo un usuario con rol cliente puede realizar pedidos.                                                                                |
| RN05 | Direcciones              | Un usuario puede registrar una o varias direcciones, cada una ubicada en una ciudad de una provincia.                                  |

## 2. Catálogo de libros

| ID   | Regla                      | Descripción                                                                                                                                                                               |
| ---- | -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| RN06 | ISBN único                 | Cada edición se registra una sola vez en el catálogo, identificada por su ISBN.                                                                                                           |
| RN07 | Clasificación              | Cada libro tiene una sola editorial, categoría, idioma y encuadernación.                                                                                                                  |
| RN08 | Autoría                    | Todo libro tiene al menos un autor y puede tener varios. Un autor puede figurar en varios libros.                                                                                         |
| RN09 | Mantenimiento del catálogo | El administrador mantiene el catálogo y las listas de referencia (categorías, idiomas, editoriales y ubicaciones). Un vendedor puede dar de alta un libro que aún no esté en el catálogo. |

## 3. Publicaciones y stock

| ID   | Regla                    | Descripción                                                                                                                                                                                      |
| ---- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| RN10 | Publicación por vendedor | Solo un vendedor puede publicar ofertas. Cada publicación indica el libro, la condición del ejemplar, un precio mayor que cero y el stock disponible.                                            |
| RN11 | Ofertas múltiples        | Un mismo libro puede tener publicaciones de varios vendedores, con distintos precios y condiciones. Un vendedor no puede tener dos publicaciones vigentes del mismo libro en la misma condición. |
| RN12 | Disponibilidad           | Solo pueden agregarse a un pedido publicaciones activas (no pausadas ni dadas de baja) y con stock.                                                                                              |
| RN13 | Stock suficiente         | La cantidad pedida no puede superar el stock disponible de la publicación. El stock nunca queda negativo.                                                                                        |
| RN14 | Descuento de stock       | Al confirmarse un pedido, se descuenta del stock de cada publicación la cantidad vendida.                                                                                                        |

## 4. Pedidos

| ID   | Regla                | Descripción                                                                                                                      |
| ---- | -------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| RN15 | Composición          | Un pedido pertenece a un único cliente y tiene al menos un renglón, con una cantidad mayor que cero.                             |
| RN16 | Varios vendedores    | Un pedido puede incluir publicaciones de uno o varios vendedores. Cada publicación aparece una sola vez por pedido.              |
| RN17 | Total calculado      | El total es la suma de cantidad por precio unitario de los renglones. Se calcula a partir del detalle. |
| RN18 | Dirección de entrega | El cliente elige una de sus direcciones registradas como destino del pedido.                                                     |
| RN19 | Ciclo del pedido     | El pedido se crea pendiente, pasa a confirmado cuando se aprueba uno de sus pagos y luego a entregado.                           |
| RN20 | Cancelación          | Solo un pedido pendiente puede cancelarse, ya que el sistema no gestiona devoluciones de dinero.                                 |

## 5. Pagos

| ID   | Regla             | Descripción                                                                                                                                 |
| ---- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| RN21 | Métodos admitidos | Los métodos de pago son tarjeta de débito, tarjeta de crédito y transferencia.                                                              |
| RN22 | Pago completo     | Cada pago se realiza en línea, corresponde a un solo pedido y cubre su total con un único método. No se admiten cuotas ni pagos combinados. |
| RN23 | Estados del pago  | Un pago puede estar pendiente, aprobado, rechazado o cancelado.                                                                             |
| RN24 | Reintentos        | Solo se registra un nuevo intento si el anterior fue rechazado o cancelado. Un pedido tiene a lo sumo un pago aprobado.                     |
| RN25 | Fechas del pago   | Cada pago registra su fecha de inicio. La fecha de acreditación se registra al aprobarse y no puede ser anterior a la de inicio.            |

## 6. Conservación del historial

| ID   | Regla               | Descripción                                                                                                                                            |
| ---- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| RN26 | Precio histórico    | Cada renglón guarda el precio unitario vigente al momento de la compra. Si el vendedor cambia el precio después, los pedidos anteriores no se alteran. |
| RN27 | Dirección histórica | El pedido guarda una copia de la dirección de entrega, que se mantiene aunque el cliente la edite o la elimine.                                        |
| RN28 | Bajas lógicas       | Los usuarios y las publicaciones dados de baja dejan de estar activos, pero no se eliminan, para que los pedidos que los incluyen sigan completos.     |
| RN29 | Historial de pagos  | Los intentos rechazados o cancelados se conservan como parte del historial del pedido.                                                                 |

## 7. Descuentos

| ID   | Regla                 | Descripción                                                                                                                                                                                                                                                     |
| ---- | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| RN30 | Descuento por volumen | Cada pedido tiene un porcentaje de descuento según su total: 0 % hasta 100.000, 5 % hasta 200.000 y 10 % por encima de ese monto. Un pedido cancelado no tiene descuento. |

## 8. Requisitos mínimos cubiertos

| Requisito                      | Reglas      |
| ------------------------------ | ----------- |
| Gestión de stock               | RN12 a RN14 |
| Registro de clientes           | RN03 a RN05 |
| Historial de precios unitarios | RN26        |
| Métodos de pago                | RN21 y RN22 |
