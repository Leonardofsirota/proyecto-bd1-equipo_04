# Alcance del sistema - Etapa 1

Este documento enumera las funcionalidades que el sistema contemplará en su versión inicial y las que quedan fuera de él.

El sistema funciona como un marketplace de libros: distintos vendedores publican ofertas y los clientes las compran a través de un catálogo online.

## 1. Usuarios y clientes

- Gestión de usuarios y roles.
- Roles disponibles: administrador, vendedor y cliente. Cada usuario tiene un único rol.
- Registro de los datos personales y de acceso de cada usuario.
- Registro de una o varias direcciones por usuario, ubicadas por ciudad y provincia.
- Baja de usuarios sin perder su historial de compras y publicaciones.

## 2. Catálogo de libros

- Gestión del catálogo de libros.
- Gestión de autores, editoriales y géneros.
- Registro de la ficha bibliográfica de cada edición, identificada por su ISBN.
- Clasificación de cada libro por categoría (género literario o área temática), idioma y encuadernación.
- Asociación de cada libro con uno o varios autores.
- Registro de los datos biográficos de los autores, incluida su nacionalidad.

## 3. Publicaciones y stock

- Publicación de ofertas de libros por parte de los vendedores, con precio y condición del ejemplar (nuevo o usado, en distintos grados de conservación).
- Oferta de un mismo libro por varios vendedores, a distintos precios y en distintas condiciones.
- Control del stock disponible de cada publicación.
- Pausa o baja de publicaciones sin perder las compras que las incluyen.

## 4. Ventas

- Registro de compras que incluyan uno o varios libros.
- Compras que reúnan libros de uno o varios vendedores.
- Conservación del precio unitario de cada libro al momento de la compra.
- Cálculo del total de cada compra a partir de su detalle.
- Cálculo informativo de un porcentaje de descuento según el total de cada compra.
- Registro de la dirección de entrega tal como estaba al momento de la compra.
- Manejo de los estados de las ventas: pendiente, confirmada, entregada y cancelada.

## 5. Pagos

- Métodos de pago (un único método por compra): tarjeta de débito, tarjeta de crédito o transferencia.
- Registro de pagos online.
- Estados del pago: pendiente, aprobado, rechazado y cancelado.
- Registro de varios intentos de pago por compra, conservando los rechazados o cancelados como historial.
- Registro de la fecha en que se inicia cada pago y de la fecha en que se acredita.

## 6. Fuera del alcance

- **Envíos y paquetería.** Se registra la dirección de entrega de cada compra, pero no se gestiona la logística: despacho, transportistas, seguimiento ni costos de envío.
- **Sistema complejo de pagos.** Solo se registran los pagos y su resultado. No hay integración con bancos ni pasarelas de pago, ni se contemplan cuotas, pagos combinados o devoluciones de dinero.
- **Geolocalización compleja.** La ubicación se limita a provincia y ciudad. No se usan mapas, coordenadas, cálculo de distancias ni validación automática de direcciones.
