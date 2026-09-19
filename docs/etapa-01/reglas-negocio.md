# Reglas de negocio - Etapa I

Este documento define las reglas de negocio que el sistema debe respetar, agrupadas por área.

## 1. Usuarios y clientes

### RN1. Roles de usuario

Cada usuario debe tener exactamente un rol dentro del sistema. Un mismo rol puede estar asociado a múltiples usuarios.

### RN2. Registro obligatorio del cliente

Una compra solo puede ser realizada por un usuario registrado con el rol Cliente.

### RN3. Direcciones del usuario

Un usuario puede registrar una o varias direcciones asociadas a su cuenta. Estas direcciones podrán utilizarse posteriormente como destino de una compra, en el marco de la gestión de envíos.

## 2. Catálogo de libros

### RN4. Autores de los libros

Todo libro debe estar asociado a, al menos, un autor y puede tener varios autores. A su vez, un mismo autor puede participar en uno o varios libros.

## 3. Stock

### RN5. Disponibilidad de stock

El sistema no debe permitir confirmar la compra de una cantidad de ejemplares superior al stock disponible de un libro.

### RN6. Actualización del stock

Cuando se confirme una venta, el stock de cada libro vendido debe disminuir según la cantidad adquirida.

## 4. Compras

### RN7. Conservación del precio histórico

El detalle de cada compra debe almacenar el precio unitario aplicado al momento de realizar la operación, independientemente del precio que el libro tenga posteriormente. La modificación del precio de un libro no debe alterar las ventas registradas previamente.

### RN8. Composición de la compra

Una compra debe contener al menos un libro y puede incluir varios, indicando para cada uno la cantidad adquirida y su precio unitario al momento de la operación.

### RN9. Total de la compra

El importe total de una compra debe obtenerse como la suma de (cantidad × precio unitario) de todos sus detalles, y no debe ser ingresado arbitrariamente por el usuario.

## 5. Pagos

### RN10. Métodos de pago

Cada compra debe utilizar un único método de pago, que debe corresponder a alguno de los medios admitidos por el sistema: tarjeta de débito, tarjeta de crédito o transferencia.

### RN11. Registro del pago

Todo pago debe estar asociado a una compra. Cada pago debe almacenar el importe, la fecha de pago, el método utilizado y su estado.

### RN12. Múltiples intentos de pago

Una compra puede tener uno o varios pagos asociados, lo que permite registrar nuevos intentos cuando uno anterior es rechazado o cancelado. Un pago rechazado o cancelado debe conservarse como parte del historial de la compra y no debe considerarse para completar la operación.
