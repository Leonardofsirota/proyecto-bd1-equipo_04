# Normalización - Etapa II

Este documento explica cómo se obtuvo el modelo relacional mediante la normalización. El proceso parte de una tabla global que reúne la información de una venta y la transforma paso a paso hasta alcanzar la Tercera Forma Normal (3FN).

En las relaciones, los atributos en negrita forman la clave primaria. La flecha (→) indica una dependencia funcional: el valor de la izquierda determina el de la derecha.

## 1. Tabla global sin normalizar

La tabla VENTA reúne en una sola fila por pedido, identificada por `pedido_id`, todos los datos que intervienen en una venta.

| Bloque                                       | Atributos |
|----------------------------------------------|-----------|
| Pedido                                       | pedido_id, fecha_pedido, estado_pedido, descripcion_estado |
| Envío                                        | direccion_envio (calle, altura, piso, departamento, código postal, referencia, ciudad y provincia en un solo valor) |
| Cliente                                      | usuario_id, nombre, apellido, dni, email, telefono, fecha_nacimiento, password_hash, imagen_url, es_activo, rol |
| Direcciones del cliente *(grupo repetitivo)* | direccion_id, calle, altura, piso, departamento, codigo_postal, referencia, ciudad, provincia |
| Renglones *(grupo repetitivo)*               | publicacion_id, cantidad, precio_unitario, precio, stock, es_activo, condicion; datos del vendedor (usuario_id y los mismos datos personales que el cliente); datos del libro (libro_id, isbn, titulo, anio_publicacion, nro_paginas, categoria, idioma, editorial, encuadernacion) y sus autores *(grupo repetitivo: autor_id, nombre)* |
| Pagos *(grupo repetitivo)*                   | pago_id, importe, fecha_creacion, fecha_pago, metodo_pago, estado_pago |

Los valores de catálogo, como el rol, la categoría, la condición, la ciudad o el método de pago, se registran como texto. El importe total del pedido no se incluye porque se calcula a partir de los renglones.

Esta estructura tiene varios problemas. Los datos del cliente se repiten en cada uno de sus pedidos, y los de un libro, en cada renglón que lo incluye, por lo que cambiar un título obliga a modificar muchas filas. Además, no es posible registrar un usuario, un libro, un autor o una publicación hasta que formen parte de un pedido, y al eliminar el único pedido de una publicación se pierden sus datos.

## 2. Primera Forma Normal (1FN)

Una relación está en 1FN cuando cada atributo contiene un único valor atómico y no hay grupos repetitivos.

VENTA no cumple ninguna de las dos condiciones. La dirección de envío concentra varios datos en un solo valor, y cada pedido contiene listas de renglones, pagos y direcciones del cliente, además de la lista de autores de cada libro.

Para llevarla a 1FN se hicieron dos cambios:

- **Atomicidad.** La dirección de envío se dividió en atributos simples: envio_calle, envio_altura, envio_piso, envio_departamento, envio_codigo_postal, envio_referencia, envio_ciudad y envio_provincia.
- **Grupos repetitivos.** Cada grupo pasó a una relación propia, junto con el identificador de aquello a lo que pertenece. Los renglones y los pagos pertenecen al pedido. Las direcciones describen al cliente y no al pedido, por lo que se separan con el identificador del usuario. Los autores describen al libro, por lo que se separan con el identificador del libro.

Un renglón se identifica por el pedido y la publicación, ya que una publicación aparece una sola vez en cada pedido. Del mismo modo, cada autor figura una sola vez en un libro. Los pagos y las direcciones ya tienen su propio identificador.

- PEDIDO (**pedido_id**, fecha_pedido, estado_pedido, descripcion_estado, atributos de envío, datos del cliente)
- PEDIDO_DETALLE (**pedido_id**, **publicacion_id**, cantidad, precio_unitario, datos de la publicación, datos del vendedor, datos del libro)
- LIBRO_AUTOR (**libro_id**, **autor_id**, nombre)
- PAGO (**pago_id**, importe, fecha_creacion, fecha_pago, metodo_pago, estado_pago, pedido_id)
- DIRECCION (**direccion_id**, calle, altura, piso, departamento, codigo_postal, referencia, ciudad, provincia, usuario_id)

Con estos cambios, cada atributo guarda un solo valor y un pedido puede tener cualquier cantidad de renglones o pagos sin modificar la estructura.

## 3. Segunda Forma Normal (2FN)

Una relación está en 2FN cuando está en 1FN y todos sus atributos no clave dependen de la clave primaria completa, y no solo de una parte de ella.

Solo las relaciones con clave compuesta pueden tener dependencias parciales: PEDIDO_DETALLE y LIBRO_AUTOR. PEDIDO, PAGO y DIRECCION tienen una clave de un solo atributo, por lo que ya cumplen 2FN.

En PEDIDO_DETALLE, la cantidad y el precio unitario dependen de la clave completa: indican cuántos ejemplares de una publicación se compraron en un pedido y a qué precio. En cambio, los datos de la publicación, del vendedor y del libro dependen solo de `publicacion_id`, y se repetirían en cada pedido que incluya esa publicación. Por eso se separan en la relación PUBLICACION.

El precio de la publicación y el precio unitario del renglón no son el mismo dato. El primero es el precio actual de la oferta y depende solo de la publicación. El segundo es el precio con el que se vendió y depende del pedido y de la publicación. Por eso se conservan ambos, y un cambio de precio no altera los pedidos ya registrados.

En LIBRO_AUTOR, el nombre del autor depende solo de `autor_id`. Se separa en la relación AUTOR, y LIBRO_AUTOR queda formada únicamente por el par de identificadores.

- PEDIDO_DETALLE (**pedido_id**, **publicacion_id**, cantidad, precio_unitario)
- PUBLICACION (**publicacion_id**, precio, stock, es_activo, condicion, datos del vendedor, datos del libro)
- LIBRO_AUTOR (**libro_id**, **autor_id**)
- AUTOR (**autor_id**, nombre)

Así, los datos de cada publicación y de cada autor se registran una sola vez, y pueden cargarse aunque todavía no formen parte de un pedido o de un libro.

## 4. Tercera Forma Normal (3FN)

Una relación está en 3FN cuando está en 2FN y ningún atributo no clave depende de otro atributo no clave, es decir, cuando no hay dependencias transitivas.

Después de 2FN, las dependencias transitivas se concentran en dos relaciones:

- **PEDIDO.** Los datos del cliente dependen del pedido a través del cliente: `pedido_id → usuario_id → nombre, apellido, dni, ...`. La descripción del estado depende del estado y no del pedido: `pedido_id → estado_pedido → descripcion_estado`. Se separan en USUARIO y PEDIDO_ESTADO, y el pedido conserva solo `usuario_id` y el estado.
- **PUBLICACION.** Los datos del libro dependen de la publicación a través del libro (`publicacion_id → libro_id → isbn, titulo, ...`), y los del vendedor, a través del vendedor (`publicacion_id → usuario_id → nombre, apellido, ...`). Los datos del libro se separan en LIBRO. Los del vendedor son los mismos que los del cliente, porque ambos son usuarios del sistema, así que se registran en la misma relación USUARIO y se distinguen por el rol.

A partir de este paso, `usuario_id` en DIRECCION y `libro_id` en LIBRO_AUTOR hacen referencia a USUARIO y LIBRO.

Otras dependencias se analizaron y no son transitivas:

- Los datos de envío dependen del propio pedido y no de una dirección registrada: son una copia de la dirección tal como estaba al momento de la compra.
- El código postal y la ciudad no se determinan entre sí, ya que un código postal puede abarcar varias localidades y una ciudad puede tener varios códigos postales.
- El ISBN del libro, el DNI y el email del usuario, y la combinación de vendedor, libro y condición de una publicación identifican una única fila. Son claves candidatas, por lo que los atributos que determinan no generan dependencias transitivas.
- Los valores de catálogo registrados como texto no determinan ningún otro atributo. En particular, la ciudad no determina la provincia, porque hay ciudades con el mismo nombre en distintas provincias.

El modelo en 3FN queda formado por diez relaciones:

- USUARIO (**usuario_id**, nombre, apellido, dni, email, telefono, fecha_nacimiento, password_hash, imagen_url, es_activo, rol)
- DIRECCION (**direccion_id**, calle, altura, piso, departamento, codigo_postal, referencia, ciudad, provincia, usuario_id)
- AUTOR (**autor_id**, nombre)
- LIBRO (**libro_id**, isbn, titulo, anio_publicacion, nro_paginas, categoria, idioma, editorial, encuadernacion)
- LIBRO_AUTOR (**libro_id**, **autor_id**)
- PUBLICACION (**publicacion_id**, precio, stock, es_activo, condicion, usuario_id, libro_id)
- PEDIDO_ESTADO (**nombre**, descripcion)
- PEDIDO (**pedido_id**, fecha_pedido, envio_calle, envio_altura, envio_piso, envio_departamento, envio_codigo_postal, envio_referencia, envio_ciudad, envio_provincia, usuario_id, estado_pedido)
- PEDIDO_DETALLE (**pedido_id**, **publicacion_id**, cantidad, precio_unitario)
- PAGO (**pago_id**, importe, fecha_creacion, fecha_pago, metodo_pago, estado_pago, pedido_id)

## 5. Separación de catálogos

En 3FN, varios atributos todavía guardan como texto valores que se repiten en muchas filas: el rol del usuario; la categoría, el idioma, la editorial y la encuadernación del libro; la condición de la publicación; el método y el estado del pago; y la ciudad y la provincia de las direcciones y del envío. 3FN no obliga a separarlos, porque ningún otro atributo depende de ellos. Se separan por una decisión de diseño: así se evitan distintas formas de escribir un mismo valor, se garantiza que solo se usen valores válidos y se pueden agregar valores nuevos sin modificar la estructura (ver [Decisiones de diseño](decisiones-diseno.md)).

Cada uno de estos valores pasó a un catálogo con un identificador y un nombre único: USUARIO_ROL, CATEGORIA, IDIOMA, EDITORIAL, ENCUADERNACION, CONDICION, PAGO_METODO y PAGO_ESTADO. Las relaciones que los usaban reemplazan el texto por una referencia al catálogo.

La ubicación geográfica forma dos relaciones: PROVINCIA, con un nombre único, y CIUDAD, con su nombre y una referencia a la provincia. Como hay ciudades homónimas, lo que no puede repetirse en CIUDAD es la combinación de nombre y provincia. DIRECCION y PEDIDO referencian solo a la ciudad, y la provincia se obtiene a través de ella.

Esta separación mantiene la 3FN: cada catálogo contiene solo datos que dependen de su identificador, y las demás relaciones guardan únicamente la referencia.

## 6. Modelo final

Por uniformidad, todas las relaciones del modelo final tienen una clave primaria de un solo atributo. PEDIDO_ESTADO recibe `pedido_estado_id`, y su nombre sigue siendo único. PEDIDO_DETALLE y LIBRO_AUTOR reciben `pedido_detalle_id` y `libro_autor_id` en lugar de su clave compuesta. En estas dos relaciones el par de identificadores sigue sin poder repetirse, por lo que continúa siendo una clave candidata: las dependencias no cambian y el modelo se mantiene en 3FN.

La siguiente tabla resume en qué paso se obtuvo cada una de las 20 relaciones del modelo final. Su estructura completa se describe en [Modelo relacional](modelo-relacional.md).

| Paso                    | Relaciones |
|-------------------------|------------|
| 1FN                     | PEDIDO, PEDIDO_DETALLE, LIBRO_AUTOR, PAGO, DIRECCION |
| 2FN                     | PUBLICACION, AUTOR |
| 3FN                     | USUARIO, LIBRO, PEDIDO_ESTADO |
| Separación de catálogos | USUARIO_ROL, CATEGORIA, IDIOMA, EDITORIAL, ENCUADERNACION, CONDICION, PAGO_METODO, PAGO_ESTADO, CIUDAD, PROVINCIA |
