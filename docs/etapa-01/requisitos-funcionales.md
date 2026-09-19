# Requisitos funcionales - Etapa I

Este documento detalla los requisitos funcionales del sistema, organizados según el actor que los utiliza.

## 1. Administrador

| ID  | Requisito                                 | Descripción                                                                                                                                      |
| --- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| RF1 | Gestión de usuarios                       | El sistema debe permitir al Administrador registrar, modificar y consultar los usuarios del sistema.                                             |
| RF2 | Gestión de roles                          | El sistema debe permitir al Administrador asignar a cada usuario uno de los roles disponibles: Administrador o Vendedor.                         |
| RF3 | Gestión de libros                         | El sistema debe permitir al Administrador registrar, modificar y consultar los libros disponibles en el catálogo.                                |
| RF4 | Gestión de autores, editoriales y géneros | El sistema debe permitir al Administrador registrar y mantener los autores, las editoriales y los géneros utilizados para clasificar los libros. |

## 2. Vendedor

| ID   | Requisito                               | Descripción                                                                                                                                 |
| ---- | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| RF5  | Gestión de libros                       | El sistema debe permitir al Vendedor registrar, modificar y consultar los libros disponibles en el catálogo.                                |
| RF6  | Gestión de stock                        | El sistema debe permitir al Vendedor actualizar el stock disponible de los libros.                                                          |
| RF7  | Consulta de ventas                      | El sistema debe permitir al Vendedor consultar las ventas registradas y sus respectivos detalles.                                           |
| RF8  | Gestión del estado de las ventas        | El sistema debe permitir al Vendedor actualizar el estado de una venta según el flujo definido por el sistema.                              |
| RF9  | Gestión de cancelaciones y devoluciones | El sistema debe permitir al Vendedor registrar la cancelación o devolución de una venta y restituir al stock las unidades correspondientes. |
| RF10 | Gestión de precios                      | El sistema debe permitir al Vendedor modificar el precio actual de venta de los libros.                                                     |

## 3. Cliente

| ID   | Requisito                   | Descripción                                                                                                                                                                                           |
| ---- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| RF11 | Gestión de cuenta           | El sistema debe permitir al Cliente registrarse y mantener sus datos personales: nombre, apellido, DNI, correo electrónico y teléfono.                                                                |
| RF12 | Gestión de direcciones      | El sistema debe permitir al Cliente registrar y mantener una o varias direcciones asociadas a su cuenta.                                                                                              |
| RF13 | Consulta del catálogo       | El sistema debe permitir al Cliente consultar los libros disponibles, incluyendo su información bibliográfica, precio y stock.                                                                        |
| RF14 | Realización de compras      | El sistema debe permitir al Cliente realizar una compra seleccionando uno o varios libros y especificando la cantidad de cada uno.                                                                    |
| RF15 | Selección del medio de pago | El sistema debe permitir al Cliente seleccionar un único método de pago online para cada compra: tarjeta de débito, tarjeta de crédito o transferencia.                                               |
| RF16 | Consulta de compras         | El sistema debe permitir al Cliente consultar las compras realizadas, incluyendo los libros adquiridos, las cantidades, los precios aplicados, el importe total, el pago y el estado de la operación. |
