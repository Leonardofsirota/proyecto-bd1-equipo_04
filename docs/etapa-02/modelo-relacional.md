# Modelo relacional - Etapa 2

Este documento describe el modelo relacional: cómo se obtuvo a partir del diagrama entidad-relación y qué guarda cada tabla. El motivo de cada decisión está en [Decisiones de diseño](decisiones-diseno.md), y el análisis de la 3FN, en [Normalización](normalizacion.md).

## 1. Resumen

El modelo tiene 21 tablas:

| Grupo       | Tablas                                                                                                                      | Cantidad |
| ----------- | --------------------------------------------------------------------------------------------------------------------------- | -------- |
| Principales | USUARIO, DIRECCION, AUTOR, LIBRO, PUBLICACION, PEDIDO, PAGO                                                                 | 7        |
| Intermedias | AUTOR_LIBRO, PEDIDO_DETALLE                                                                                                 | 2        |
| Ubicación   | PROVINCIA, CIUDAD                                                                                                           | 2        |
| Catálogos   | USUARIO_ROL, CATEGORIA, IDIOMA, EDITORIAL, ENCUADERNACION, CONDICION, NACIONALIDAD, PEDIDO_ESTADO, PAGO_ESTADO, PAGO_METODO | 10       |

La cantidad supera la referencia de 6 a 10 tablas. El ciclo de venta se sostiene con las nueve tablas principales e intermedias. Las doce restantes son listas de valores pequeñas y estables: evitan repetir texto en cada registro y no agregan pasos a la operación de venta.

## 2. Del DER al modelo relacional

La transformación siguió estas reglas:

- **Entidades.** Cada entidad se convirtió en una tabla con el mismo nombre, y sus atributos, en columnas. Los atributos opcionales dieron lugar a columnas que admiten valores vacíos.
- **Relaciones de uno a muchos.** Se representan con una clave foránea en la tabla del lado «muchos». Todas son obligatorias, salvo la nacionalidad del autor.
- **Relaciones de muchos a muchos.** Se transformaron en tablas intermedias. La relación entre autores y libros dio lugar a AUTOR_LIBRO. La relación entre pedidos y publicaciones dio lugar a PEDIDO_DETALLE, que además incorpora sus atributos propios: la cantidad y el precio unitario.
- **Atributo derivado.** El total del pedido se calcula a partir del detalle, por lo que no se almacena.

El modelo no tiene relaciones de uno a uno.

## 3. Convenciones

- Cada tabla tiene una clave primaria de una sola columna, con el nombre de la tabla seguido de `_id`.
- Cada clave foránea lleva el mismo nombre que la clave primaria a la que apunta. Por ejemplo, `libro_id` en PUBLICACION referencia a LIBRO.

## 4. Tablas

En las tablas siguientes, la columna **Referencia a** indica las tablas a las que apuntan sus claves foráneas, y **No se repite**, los datos que deben ser únicos.

### 4.1 Catálogos

Los diez catálogos tienen la misma estructura: un identificador y un nombre que no puede repetirse.

| Catálogo       | Qué clasifica                                 | Ejemplos de valores                                  |
| -------------- | --------------------------------------------- | ---------------------------------------------------- |
| USUARIO_ROL    | Rol del usuario                               | Administrador, Vendedor, Cliente                     |
| CATEGORIA      | Género literario o área temática del libro    | Novela, Poesía, Informática, Derecho                 |
| IDIOMA         | Idioma del libro                              | Español, Inglés, Portugués                           |
| EDITORIAL      | Editorial del libro                           | Planeta, Sudamericana, Eudeba                        |
| ENCUADERNACION | Encuadernación del libro                      | Tapa blanda, Tapa dura                               |
| CONDICION      | Estado de conservación del ejemplar publicado | Nuevo, Como nuevo, Muy bueno, Bueno, Aceptable       |
| NACIONALIDAD   | Nacionalidad del autor                        | Argentina, Uruguaya, Británica                       |
| PEDIDO_ESTADO  | Etapa en que se encuentra el pedido           | Pendiente, Confirmado, Entregado, Cancelado          |
| PAGO_ESTADO    | Resultado de cada intento de pago             | Pendiente, Aprobado, Rechazado, Cancelado            |
| PAGO_METODO    | Medio con que se paga                         | Tarjeta de débito, Tarjeta de crédito, Transferencia |

### 4.2 Usuarios y ubicación

| Tabla     | Qué guarda                                                                                          | Referencia a    | No se repite                  |
| --------- | --------------------------------------------------------------------------------------------------- | --------------- | ----------------------------- |
| PROVINCIA | Nombre de la provincia.                                                                             | —               | Nombre                        |
| CIUDAD    | Nombre de la ciudad.                                                                                | PROVINCIA       | Nombre dentro de la provincia |
| USUARIO   | Nombre, apellido, DNI, email, teléfono, fecha de nacimiento, hash de la contraseña y fecha de baja. | USUARIO_ROL     | DNI; email                    |
| DIRECCION | Calle, altura, piso, departamento, código postal y una referencia para la entrega.                  | USUARIO, CIUDAD | —                             |

### 4.3 Libros y publicaciones

| Tabla       | Qué guarda                                                                             | Referencia a                                 | No se repite                                                  |
| ----------- | -------------------------------------------------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------- |
| AUTOR       | Nombre, apellido, ISNI, fechas de nacimiento y fallecimiento, diferencial y biografía. | NACIONALIDAD (opcional)                      | ISNI, cuando se registra                                      |
| LIBRO       | ISBN, título, cantidad de páginas y año de publicación.                                | CATEGORIA, IDIOMA, EDITORIAL, ENCUADERNACION | ISBN                                                          |
| AUTOR_LIBRO | El vínculo entre un autor y uno de sus libros.                                         | AUTOR, LIBRO                                 | Par autor-libro                                               |
| PUBLICACION | Precio, stock, disponibilidad y fechas de creación y de baja.                          | USUARIO (vendedor), LIBRO, CONDICION         | Vendedor, libro y condición, entre las publicaciones vigentes |

### 4.4 Pedidos y pagos

| Tabla          | Qué guarda                                                                                                          | Referencia a                                          | No se repite           |
| -------------- | ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ---------------------- |
| PEDIDO         | Fecha del pedido y copia de la dirección de entrega: calle, altura, piso, departamento, código postal y referencia. | USUARIO (cliente), PEDIDO_ESTADO, CIUDAD (de entrega) | —                      |
| PEDIDO_DETALLE | Cantidad y precio unitario de cada renglón.                                                                         | PEDIDO, PUBLICACION                                   | Par pedido-publicación |
| PAGO           | Importe, fecha de creación y fecha de pago.                                                                         | PEDIDO, PAGO_METODO, PAGO_ESTADO                      | —                      |

## 5. Reglas que el esquema no garantiza

Las claves y las restricciones de unicidad no alcanzan para asegurar algunas reglas de negocio, porque dependen de datos de otras filas o de otras tablas:

| Reglas     | Qué debe controlarse                                                                                                                                                                                                     |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| RN04, RN10 | Que quien realiza un pedido tenga el rol de cliente, y quien publica, el de vendedor.                                                                                                                                    |
| RN08, RN15 | Que todo libro tenga al menos un autor y todo pedido, al menos un renglón. La clave foránea asegura que cada fila intermedia pertenezca a un libro o a un pedido, pero no que cada libro o pedido tenga filas asociadas. |
| RN12, RN13 | Que solo se agreguen a un pedido publicaciones disponibles, vigentes y con stock suficiente.                                                                                                                             |
| RN14       | Que el stock se descuente al confirmarse el pedido.                                                                                                                                                                      |
| RN18       | Que la dirección copiada en el pedido sea una de las direcciones registradas por el cliente.                                                                                                                             |
| RN19, RN20 | Que el pedido avance por sus estados en el orden previsto y solo se cancele mientras está pendiente.                                                                                                                     |
| RN22       | Que el importe de cada pago coincida con el total del pedido.                                                                                                                                                            |
| RN24       | Que un nuevo intento de pago solo se registre si el anterior fue rechazado o cancelado, y que cada pedido tenga a lo sumo un pago aprobado.                                                                              |
| RN25       | Que la fecha de pago se registre cuando el pago se aprueba.                                                                                                                                                              |

El control de estas reglas corresponde a los mecanismos de la Etapa 5: procedimientos, transacciones y triggers.
