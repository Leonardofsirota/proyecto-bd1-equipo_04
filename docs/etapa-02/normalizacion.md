# Normalización - Etapa 2

Este documento muestra cómo se llegó al modelo relacional en Tercera Forma Normal (3FN). El proceso parte de una tabla única que reúne toda la información de una venta y la descompone paso a paso.

Notación:

- En cada relación, los atributos en **negrita** forman la clave primaria.
- Los textos en _cursiva_ resumen un grupo de atributos, por ejemplo, _datos del cliente_.
- La flecha (→) indica una dependencia funcional: el valor de la izquierda determina el de la derecha.

## 1. Tabla sin normalizar

La tabla VENTA tiene una fila por pedido, identificada por pedido_id, con todos los datos que intervienen en la venta:

| Bloque                                                        | Contenido                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pedido                                                        | Fecha y estado del pedido.                                                                                                                                                                                                                                                         |
| Envío                                                         | Dirección de entrega en un solo valor, incluidas la ciudad y la provincia.                                                                                                                                                                                                         |
| Cliente                                                       | Identificador, datos personales y de acceso, fecha de baja y rol.                                                                                                                                                                                                                  |
| Direcciones del cliente _(grupo repetitivo)_                  | Calle, altura, piso, departamento, código postal, referencia, ciudad y provincia de cada una.                                                                                                                                                                                      |
| Renglones _(grupo repetitivo)_                                | Publicación, cantidad y precio unitario. Además, los datos de la publicación (precio actual, stock, condición, disponibilidad y fechas), de su vendedor (los mismos datos que el cliente) y del libro (ISBN, título, páginas, año, categoría, idioma, editorial y encuadernación). |
| Autores del libro _(grupo repetitivo dentro de cada renglón)_ | Identificador, nombre, apellido, ISNI, nacionalidad, fechas de nacimiento y fallecimiento, diferencial y biografía.                                                                                                                                                                |
| Pagos _(grupo repetitivo)_                                    | Importe, fechas de creación y de pago, método y estado de cada intento.                                                                                                                                                                                                            |

Los valores como el rol, la categoría, la condición, la ciudad o el método de pago figuran como texto. El total del pedido no se incluye porque se calcula a partir de los renglones.

Esta estructura tiene tres problemas:

- **Redundancia.** Los datos del cliente se repiten en cada uno de sus pedidos, y los de un libro, en cada renglón que lo incluye. Cambiar un título obliga a modificar muchas filas.
- **Anomalía de inserción.** No se puede registrar un usuario, un libro, un autor o una publicación hasta que formen parte de un pedido.
- **Anomalía de borrado.** Al eliminar el único pedido que incluye una publicación, se pierden sus datos.

## 2. Primera Forma Normal (1FN)

Una relación está en 1FN cuando cada atributo guarda un único valor atómico y no hay grupos repetitivos. VENTA no cumple ninguna de las dos condiciones, por lo que se hacen dos cambios:

- **Atomicidad.** La dirección de envío se divide en atributos simples: calle, altura, piso, departamento, código postal, referencia, ciudad y provincia.
- **Grupos repetitivos.** Cada grupo pasa a una relación propia, junto con el identificador de aquello que describe. Los renglones y los pagos describen al pedido; las direcciones, al cliente, y los autores, al libro.

Un renglón se identifica por el pedido y la publicación, porque una publicación aparece una sola vez en cada pedido. Del mismo modo, un autor figura una sola vez en cada libro. Los pagos y las direcciones tienen su propio identificador.

- PEDIDO (**pedido_id**, fecha_pedido, estado_pedido, _datos de envío_, usuario_id, _datos del cliente_)
- PEDIDO_DETALLE (**pedido_id**, **publicacion_id**, cantidad, precio_unitario, _datos de la publicación, del vendedor y del libro_)
- AUTOR_LIBRO (**libro_id**, **autor_id**, _datos del autor_)
- PAGO (**pago_id**, importe, fecha_creacion, fecha_pago, metodo_pago, estado_pago, pedido_id)
- DIRECCION (**direccion_id**, _datos de la dirección_, ciudad, provincia, usuario_id)

Cada atributo guarda ahora un solo valor, y un pedido puede tener cualquier cantidad de renglones o pagos sin cambiar la estructura.

## 3. Segunda Forma Normal (2FN)

Una relación está en 2FN cuando está en 1FN y cada atributo no clave depende de la clave primaria completa, no solo de una parte de ella. Solo pueden incumplirla las relaciones con clave compuesta: PEDIDO_DETALLE y AUTOR_LIBRO.

- **PEDIDO_DETALLE.** La cantidad y el precio unitario dependen de la clave completa: indican cuántos ejemplares de una publicación se compraron en un pedido y a qué precio. Los datos de la publicación, del vendedor y del libro, en cambio, dependen solo de la publicación (`publicacion_id → precio, stock, ...`). Se separan en la relación PUBLICACION.
- **AUTOR_LIBRO.** Los datos del autor dependen solo de `autor_id`. Se separan en la relación AUTOR, y AUTOR_LIBRO queda formada solo por el par de identificadores.

El precio de la publicación y el precio unitario del renglón no son el mismo dato. El primero es el precio actual de la oferta y depende solo de la publicación. El segundo es el precio con que se vendió y depende del pedido y de la publicación. Por eso se conservan ambos (RN26).

- PEDIDO_DETALLE (**pedido_id**, **publicacion_id**, cantidad, precio_unitario)
- PUBLICACION (**publicacion_id**, precio, stock, condicion, disponible, fecha_creacion, fecha_eliminacion, usuario_id, _datos del vendedor_, libro_id, _datos del libro_)
- AUTOR_LIBRO (**libro_id**, **autor_id**)
- AUTOR (**autor_id**, nombre, apellido, isni, nacionalidad, fecha_nacimiento, fecha_fallecimiento, diferencial, biografia)

Así, cada publicación y cada autor se registran una sola vez, y pueden cargarse aunque todavía no formen parte de un pedido o de un libro.

## 4. Tercera Forma Normal (3FN)

Una relación está en 3FN cuando está en 2FN y ningún atributo no clave depende de otro atributo no clave, es decir, cuando no hay dependencias transitivas. Quedan dos casos:

- **PEDIDO.** Los datos del cliente dependen del pedido a través del cliente (`pedido_id → usuario_id → nombre, apellido, dni, ...`). Se separan en la relación USUARIO, y el pedido conserva solo `usuario_id`.
- **PUBLICACION.** Los datos del libro dependen de la publicación a través del libro (`publicacion_id → libro_id → isbn, titulo, ...`), y los del vendedor, a través del vendedor. Los datos del libro se separan en LIBRO. Los del vendedor van a la misma relación USUARIO, porque vendedores y clientes comparten los mismos datos y se distinguen por el rol.

Otras dependencias se analizaron y no son transitivas:

- Los datos de envío dependen del pedido y no de una dirección registrada: son una copia tomada al momento de la compra.
- El código postal y la ciudad no se determinan entre sí. Un código postal puede abarcar varias localidades, y una ciudad puede tener varios códigos postales.
- La ciudad, escrita como texto, no determina la provincia, porque hay ciudades homónimas en distintas provincias.
- El ISBN, el DNI, el email y el ISNI (cuando está presente) identifican una única fila. Son claves candidatas, por lo que los atributos que determinan no generan dependencias transitivas.
- La fecha de baja de una publicación no determina su disponibilidad. Una publicación dada de baja nunca está disponible, pero una vigente puede estar disponible o pausada.

El modelo en 3FN queda formado por nueve relaciones:

- USUARIO (**usuario_id**, nombre, apellido, dni, email, telefono, fecha_nacimiento, password_hash, fecha_eliminacion, rol)
- DIRECCION (**direccion_id**, _datos de la dirección_, ciudad, provincia, usuario_id)
- AUTOR (**autor_id**, nombre, apellido, isni, nacionalidad, fecha_nacimiento, fecha_fallecimiento, diferencial, biografia)
- LIBRO (**libro_id**, isbn, titulo, nro_paginas, anio_publicacion, categoria, idioma, editorial, encuadernacion)
- AUTOR_LIBRO (**libro_id**, **autor_id**)
- PUBLICACION (**publicacion_id**, precio, stock, condicion, disponible, fecha_creacion, fecha_eliminacion, usuario_id, libro_id)
- PEDIDO (**pedido_id**, fecha_pedido, estado_pedido, _datos de envío_, envio_ciudad, envio_provincia, usuario_id)
- PEDIDO_DETALLE (**pedido_id**, **publicacion_id**, cantidad, precio_unitario)
- PAGO (**pago_id**, importe, fecha_creacion, fecha_pago, metodo_pago, estado_pago, pedido_id)

## 5. Separación de catálogos

En 3FN, varios atributos todavía guardan como texto valores que se repiten en muchas filas: el rol del usuario; la categoría, el idioma, la editorial y la encuadernación del libro; la nacionalidad del autor; la condición de la publicación; el estado del pedido; el método y el estado del pago, y la ciudad y la provincia. La 3FN no obliga a separarlos, porque ningún otro atributo depende de ellos. Se separan por una decisión de diseño, explicada en [Decisiones de diseño](decisiones-diseno.md).

- **Catálogos.** Cada uno de esos valores pasa a un catálogo con un identificador y un nombre único: USUARIO_ROL, CATEGORIA, IDIOMA, EDITORIAL, ENCUADERNACION, NACIONALIDAD, CONDICION, PEDIDO_ESTADO, PAGO_METODO y PAGO_ESTADO. Las relaciones que los usaban reemplazan el texto por una referencia.
- **Ubicación.** La ciudad y la provincia forman dos relaciones: PROVINCIA y CIUDAD, que referencia a su provincia. DIRECCION y PEDIDO referencian solo a la ciudad, y la provincia se obtiene a través de ella.

La separación mantiene la 3FN: cada catálogo contiene solo datos que dependen de su identificador, y las demás relaciones guardan únicamente la referencia.

## 6. Modelo final

Por uniformidad, todas las relaciones del modelo final tienen una clave primaria de un solo atributo. AUTOR_LIBRO y PEDIDO_DETALLE reciben `autor_libro_id` y `pedido_detalle_id` en lugar de su clave compuesta. El par de identificadores sigue sin poder repetirse, por lo que continúa siendo una clave candidata: las dependencias no cambian y el modelo se mantiene en 3FN.

La siguiente tabla resume en qué paso se obtuvo cada una de las 21 relaciones. Su estructura se describe en [Modelo relacional](modelo-relacional.md).

| Paso                    | Relaciones                                                                                                                                     |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| 1FN                     | PEDIDO, PEDIDO_DETALLE, AUTOR_LIBRO, PAGO, DIRECCION                                                                                           |
| 2FN                     | PUBLICACION, AUTOR                                                                                                                             |
| 3FN                     | USUARIO, LIBRO                                                                                                                                 |
| Separación de catálogos | USUARIO_ROL, CATEGORIA, IDIOMA, EDITORIAL, ENCUADERNACION, CONDICION, NACIONALIDAD, PEDIDO_ESTADO, PAGO_ESTADO, PAGO_METODO, PROVINCIA, CIUDAD |
