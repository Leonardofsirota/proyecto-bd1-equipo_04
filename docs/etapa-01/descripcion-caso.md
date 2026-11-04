# Descripción del caso - Etapa 1

Este documento presenta el caso de estudio: qué sistema se desarrollará, quiénes lo utilizarán y qué información administrará.

## 1. Contexto

Los libros se venden tanto nuevos como usados. Los nuevos los ofrecen sobre todo las librerías, mientras que los usados circulan entre particulares que venden lo que ya leyeron o los textos de estudio que ya no necesitan. Esa oferta suele estar dispersa: para encontrar un título y comparar su precio y su estado, el comprador tiene que consultar a varios vendedores por separado.

Un marketplace resuelve ese problema: reúne en un solo lugar las ofertas de muchos vendedores sobre un catálogo común.

## 2. El sistema

Se desarrollará la base de datos de un marketplace online de libros. Los vendedores publican ofertas de libros, indicando precio, stock y condición del ejemplar, y los clientes compran esas ofertas. El catálogo abarca desde géneros literarios hasta áreas académicas y técnicas.

Una venta sigue este recorrido:

1. **Catálogo.** Cada edición de un libro se registra una sola vez, identificada por su ISBN.
2. **Publicación.** Cada vendedor publica su oferta de ese libro, con precio, stock y condición propios. Un mismo libro puede tener ofertas de varios vendedores.
3. **Pedido.** El cliente arma un pedido con publicaciones de uno o varios vendedores e indica la dirección de entrega. El pedido reserva esas unidades durante un plazo, sin descontarlas del stock.
4. **Pago.** El cliente paga el pedido completo en línea. Si un intento es rechazado o cancelado, puede registrar uno nuevo mientras la reserva siga vigente. Cuando se aprueba el pago, se descuenta el stock.
5. **Seguimiento.** El pedido pasa por los estados pendiente, confirmado y entregado, o termina cancelado.

En su versión inicial, el sistema opera en la provincia de Corrientes. El modelo permite incorporar otras provincias sin modificar su estructura.

## 3. Usuarios

Todos los usuarios se registran con los mismos datos: nombre, apellido, DNI, email, teléfono, fecha de nacimiento y contraseña. Cada uno tiene un único rol, que determina qué hace en el sistema:

- **Administrador.** Gestiona los usuarios y sus roles. Mantiene el catálogo de libros y autores, y las listas de referencia del sistema, como categorías, idiomas, editoriales y ubicaciones.
- **Vendedor.** Puede ser un particular o una librería. Publica ofertas, fija su precio y condición, mantiene su stock y puede pausarlas o darlas de baja. Si el libro que quiere vender no está en el catálogo, puede darlo de alta.
- **Cliente.** Registra sus direcciones, consulta el catálogo, realiza pedidos y los paga.

## 4. Información que administra

| Área          | Información registrada                                                                                                        |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Usuarios      | Datos personales y de acceso, rol y direcciones, ubicadas por ciudad y provincia.                                             |
| Catálogo      | Ficha de cada libro (título, año, páginas, editorial, idioma, encuadernación y categoría) y datos biográficos de sus autores. |
| Publicaciones | Vendedor, libro, condición del ejemplar, precio, stock y disponibilidad de cada oferta.                                       |
| Pedidos       | Cliente, fecha, estado, dirección de entrega y detalle de las publicaciones compradas, con cantidad y precio unitario.        |
| Pagos         | Intentos de pago de cada pedido, con importe, método, estado y fechas de inicio y acreditación.                               |

## 5. Conservación del historial

Lo que ya se vendió no cambia aunque cambien los datos actuales:

- **Precio.** Cada renglón del pedido guarda el precio unitario vigente al momento de la compra. Si el vendedor modifica el precio después, las ventas anteriores no se alteran.
- **Dirección.** El pedido guarda una copia de la dirección de entrega, que se mantiene aunque el cliente la edite o la elimine.
- **Bajas.** Los usuarios y las publicaciones dados de baja no se eliminan, para que los pedidos que los incluyen sigan completos.
- **Pagos.** Los intentos rechazados o cancelados se conservan como parte del historial del pedido.

El detalle de las funcionalidades incluidas y excluidas está en [alcance.md](alcance.md).
