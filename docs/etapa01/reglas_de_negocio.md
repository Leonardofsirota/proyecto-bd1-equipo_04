# Reglas de negocio - Etapa I

## RN1. Roles de usuario

Cada usuario debe poseer exactamente un rol dentro del sistema. Un mismo rol puede estar asociado a múltiples usuarios.

## RN2. Registro obligatorio del cliente

Una compra solamente puede ser realizada por un usuario registrado con rol Cliente.

## RN3. Direcciones del usuario

Un usuario puede registrar una o varias direcciones asociadas a su cuenta. La dirección podrá utilizarse posteriormente como destino de una compra en la gestión de envíos.

## RN4. Autores de los libros

Todo libro debe estar asociado al menos a un autor, mientras que un mismo autor puede participar en uno o varios libros. Del mismo modo, un libro puede poseer múltiples autores.

## RN5. Disponibilidad de stock

El sistema no debe permitir confirmar la compra de una cantidad de ejemplares superior al stock disponible de un libro.

## RN6. Actualización del stock

Cuando una venta sea confirmada, el stock de cada libro vendido debe disminuir según la cantidad adquirida.

## RN7. Conservación del precio histórico

El detalle de cada compra debe almacenar el precio unitario aplicado al momento de realizar la operación, independientemente del precio actual que posteriormente tenga el libro. La modificación del precio de un libro no debe alterar las ventas registradas previamente.

## RN8. Composición de la compra

Una compra debe contener al menos un libro o puede incluir múltiples libros, indicando para cada uno la cantidad adquirida y su precio unitario al momento de la operación.

## RN9. Total de la compra

El importe total de una compra debe obtenerse a partir de la suma de (cantidad x precio unitario) de todos sus detalles y no debe ser ingresado arbitrariamente por el usuario.

## RN10. Métodos de pago

La compra debe completarse mediante un único pago aprobado por el importe total, utilizando un solo método que deberá corresponder a alguno de los medios admitidos por el sistema: tarjeta de débito, tarjeta de crédito o transferencia. No se permiten pagos parciales.

## RN11. Registro del pago

Todo pago debe estar asociado a una compra. Cada pago debe almacenar el importe, la fecha del pago, el método utilizado y su estado.

## RN12. Múltiples intentos de pago

Una compra puede tener uno o varios pagos asociados, permitiendo registrar nuevos intentos de pago cuando uno anterior sea rechazado o cancelado. Un pago rechazado o cancelado debe conservarse como parte del historial de la compra y no debe considerarse para completar la operación.
