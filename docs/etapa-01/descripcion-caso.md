# Descripción del caso - Etapa I

Este documento presenta el caso de estudio: qué sistema se desarrollará, quiénes lo utilizarán y qué información administrará.

## 1. Presentación del sistema

Se desarrollará una base de datos relacional para un sistema de venta de libros mediante un catálogo online. El sistema permitirá administrar un catálogo de libros y registrar las operaciones necesarias para realizar compras, controlar el stock, gestionar clientes, registrar pagos y conservar el precio aplicado a cada libro al momento de la venta.

## 2. Usuarios y roles

Los usuarios del sistema se clasificarán según su rol:

- **Administrador**
- **Vendedor**
- **Cliente**

Los clientes deberán estar registrados para poder realizar compras y podrán tener una o varias direcciones asociadas a su cuenta.

## 3. Catálogo y compras

Cada libro contará con la siguiente información:

- ISBN
- Título
- Editorial
- Género
- Autor o autores
- Stock disponible
- Precio actual

Un libro podrá estar asociado a uno o varios autores. Además, el sistema permitirá que una compra incluya uno o varios libros, con distintas cantidades de cada uno.
