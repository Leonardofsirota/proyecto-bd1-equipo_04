# Restricciones de integridad - Etapa 3

Este documento reúne las restricciones que el motor hace cumplir sobre los datos: qué impide cada una y qué regla de negocio protege. Los criterios con que se definieron están en [Implementación](implementacion.md#5-integridad-de-los-datos), y su verificación, en [Pruebas y validación](pruebas-validacion.md).

## 1. Resumen

El esquema protege los datos en tres niveles:

| Integridad  | Qué asegura                                                                           | Mecanismos                                                      |
| ----------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| De entidad  | Cada fila se identifica sin ambigüedad y los identificadores naturales no se repiten. | `PRIMARY KEY` (21), `UNIQUE` (17), índices únicos filtrados (2) |
| Referencial | Toda referencia apunta a una fila que existe.                                         | `FOREIGN KEY` (22)                                              |
| De dominio  | Cada columna admite solo valores válidos.                                             | `CHECK` (18), `NOT NULL` (82 columnas), `DEFAULT` (4)           |

Una operación que incumple cualquiera de ellas se rechaza entera, y el mensaje de error nombra la restricción incumplida.

## 2. Integridad de entidad

Cada tabla tiene una clave primaria numerada por el motor, que no se repite ni puede quedar vacía. Pero ese número no tiene significado propio, así que no alcanza para evitar duplicados reales: dos filas con distinto ID podrían describir el mismo libro. De eso se ocupan las restricciones de unicidad:

| Tabla                 | No puede repetirse                                            | Regla |
| --------------------- | ------------------------------------------------------------- | ----- |
| Catálogos y PROVINCIA | El nombre                                                     | —     |
| CIUDAD                | El nombre, dentro de la misma provincia                       | RN05  |
| USUARIO               | El DNI y el email, cada uno por separado                      | RN03  |
| LIBRO                 | El ISBN                                                       | RN06  |
| AUTOR                 | El ISNI, entre los autores que lo tienen                      | —     |
| AUTOR_LIBRO           | El mismo autor en el mismo libro                              | RN08  |
| PUBLICACION           | Vendedor, libro y condición, entre las publicaciones vigentes | RN11  |
| PEDIDO_DETALLE        | La misma publicación en el mismo pedido                       | RN16  |

Las dos filas que dicen «entre…» usan índices únicos filtrados, que exigen la unicidad solo a una parte de las filas. Así puede haber varios autores sin ISNI, y un vendedor puede volver a publicar un libro después de dar de baja la oferta anterior.

**Mayúsculas y tildes.** La base no fija una intercalación propia y toma la del servidor. En la instalación del equipo es `SQL_Latin1_General_CP1_CI_AS`, que no distingue mayúsculas pero sí tildes. Por eso «novela» se rechaza como duplicado de «Novela», y un email ya registrado no puede cargarse otra vez escrito en mayúsculas. En cambio, «Poesia» se acepta como distinta de «Poesía»: evitar esas variantes queda a cargo de quien mantiene los catálogos.

## 3. Integridad referencial

### 3.1 Referencias

Las 22 claves foráneas siguen las referencias del modelo relacional:

| Tabla          | Referencia a                                          |
| -------------- | ----------------------------------------------------- |
| CIUDAD         | PROVINCIA                                             |
| USUARIO        | USUARIO_ROL                                           |
| DIRECCION      | USUARIO, CIUDAD                                       |
| AUTOR          | NACIONALIDAD (opcional)                               |
| LIBRO          | ENCUADERNACION, CATEGORIA, IDIOMA, EDITORIAL          |
| AUTOR_LIBRO    | LIBRO, AUTOR                                          |
| PUBLICACION    | USUARIO (vendedor), LIBRO, CONDICION                  |
| PEDIDO         | USUARIO (cliente), PEDIDO_ESTADO, CIUDAD (de entrega) |
| PEDIDO_DETALLE | PEDIDO, PUBLICACION                                   |
| PAGO           | PAGO_ESTADO, PAGO_METODO, PEDIDO                      |

Todas son obligatorias, salvo la nacionalidad del autor: puede faltar, pero si se indica, debe existir en el catálogo.

### 3.2 Qué impiden

Ninguna clave foránea propaga cambios: todas usan la regla `NO ACTION`. En la práctica, el motor controla tres situaciones:

- **Referencias inexistentes.** No se puede guardar una fila que apunte a un registro que no existe, como un pedido de un cliente inexistente o un renglón de una publicación inexistente.
- **Borrado de registros en uso.** No se puede borrar una fila mientras otra la referencie. Por ejemplo, la categoría «Novela» no puede eliminarse mientras haya libros clasificados en ella:

  ```sql
  DELETE FROM dbo.CATEGORIA WHERE categoria_id = 1;  -- Novela
  -- Msg 547: The DELETE statement conflicted with the REFERENCE constraint "fk_libro_categoria".
  ```

- **Cambio de identificadores.** No puede ocurrir: SQL Server no permite modificar una clave numerada por el motor (`IDENTITY`), así que ninguna referencia queda desactualizada.

Para retirar un registro en uso, antes hay que eliminar o reasignar las filas que dependen de él. Los usuarios y las publicaciones nunca llegan a ese punto: se dan de baja sin borrarse (RN28) y su historial queda completo.

## 4. Integridad de dominio

### 4.1 Validaciones

Los `CHECK` revisan cada fila al insertarla o modificarla:

| Tabla          | Restricción                               | Qué exige                                                    |
| -------------- | ----------------------------------------- | ------------------------------------------------------------ |
| USUARIO        | `chk_usuario_dni`                         | DNI de 7 u 8 dígitos, sin puntos ni espacios                 |
|                | `chk_usuario_email`                       | Email con la forma `nombre@dominio.ext`                      |
|                | `chk_usuario_fecha_nacimiento`            | Fecha de nacimiento anterior a hoy                           |
| DIRECCION      | `chk_direccion_altura`                    | Altura mayor que cero                                        |
| AUTOR          | `chk_autor_fechas`                        | Fallecimiento no anterior al nacimiento, si se conocen ambos |
|                | `chk_autor_isni`                          | ISNI de 15 dígitos seguidos de un dígito o una X             |
| LIBRO          | `chk_libro_isbn`                          | ISBN de 13 dígitos                                           |
|                | `chk_libro_nro_paginas`                   | Al menos una página                                          |
|                | `chk_libro_anio_publicacion`              | Año mayor que cero y, como máximo, el siguiente al actual    |
| PUBLICACION    | `chk_publicacion_stock`                   | Stock nunca negativo                                         |
|                | `chk_publicacion_precio`                  | Precio mayor que cero                                        |
|                | `chk_publicacion_fechas`                  | Baja no anterior al alta                                     |
|                | `chk_publicacion_eliminada_no_disponible` | Una publicación dada de baja no figura como disponible       |
| PEDIDO         | `chk_pedido_envio_altura`                 | Altura de entrega mayor que cero                             |
| PEDIDO_DETALLE | `chk_pedido_detalle_cantidad`             | Cantidad mayor que cero                                      |
|                | `chk_pedido_detalle_precio_unitario`      | Precio unitario mayor que cero                               |
| PAGO           | `chk_pago_importe`                        | Importe mayor que cero                                       |
|                | `chk_pago_fechas`                         | Acreditación no anterior al inicio del pago                  |

Conviene tener presentes tres comportamientos:

- **Largo exacto del ISBN y el ISNI.** Las columnas de largo fijo completan con espacios los valores más cortos, y el espacio no es un carácter válido. Por eso un ISBN de 9 dígitos se rechaza igual que uno con letras.
- **Datos vacíos.** Una validación solo rechaza la fila cuando su condición resulta falsa. Si el dato está vacío, el resultado queda indeterminado y la fila se acepta: un autor sin ISNI no incumple `chk_autor_isni`.
- **Email.** El control es solo de forma: exige un texto con arroba y punto, pero no comprueba que la dirección exista.

### 4.2 Datos obligatorios y valores por defecto

De las 97 columnas, 82 son obligatorias. Solo admiten vacío las 15 que representan datos que pueden no conocerse o que todavía no ocurrieron:

| Tabla       | Columnas opcionales                                                                              | Por qué                                           |
| ----------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------- |
| USUARIO     | `fecha_eliminacion`                                                                              | Queda vacía mientras el usuario está activo.      |
| DIRECCION   | `piso`, `departamento`, `referencia`                                                             | No toda dirección los tiene.                      |
| AUTOR       | `isni`, `nacionalidad_id`, `fecha_nacimiento`, `fecha_fallecimiento`, `diferencial`, `biografia` | No siempre se conocen al dar de alta al autor.    |
| PUBLICACION | `fecha_eliminacion`                                                                              | Queda vacía mientras la publicación está vigente. |
| PEDIDO      | `envio_piso`, `envio_departamento`, `envio_referencia`                                           | Copian los datos opcionales de la dirección.      |
| PAGO        | `fecha_pago`                                                                                     | Queda vacía hasta que el pago se aprueba.         |

Cuatro columnas obligatorias tienen un valor por defecto, que el motor completa si la inserción no lo indica: la publicación, el pedido y el pago registran como fecha de alta el momento de la inserción, y toda publicación nueva queda disponible.

## 5. Reglas de negocio que garantiza el esquema

| Reglas      | Qué asegura el esquema                                                                              | Qué queda para la Etapa 5                               |
| ----------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| RN01, RN03  | Cada usuario tiene un único rol y sus datos de registro completos; el DNI y el email no se repiten. | —                                                       |
| RN05        | Cada dirección pertenece a un usuario y a una ciudad existentes.                                    | —                                                       |
| RN06, RN07  | El ISBN no se repite, y cada libro tiene una sola editorial, categoría, idioma y encuadernación.    | —                                                       |
| RN08        | Un autor figura una sola vez en cada libro.                                                         | Que todo libro tenga al menos un autor.                 |
| RN10        | Toda publicación indica libro, condición, precio mayor que cero y stock.                            | Que quien publica tenga el rol de vendedor.             |
| RN11        | Un vendedor no repite libro y condición entre sus publicaciones vigentes.                           | —                                                       |
| RN13        | El stock nunca es negativo.                                                                         | Que la cantidad pedida no supere el stock.              |
| RN15        | Cada pedido pertenece a un único cliente, y cada renglón tiene una cantidad mayor que cero.         | Que todo pedido tenga al menos un renglón.              |
| RN16        | Una publicación aparece una sola vez por pedido.                                                    | —                                                       |
| RN21 a RN23 | Cada pago corresponde a un solo pedido, con un único método y un estado tomados de sus catálogos.   | Que el importe coincida con el total del pedido (RN22). |
| RN25        | El pago registra su fecha de inicio, y la acreditación no puede ser anterior.                       | Que la acreditación se registre al aprobarse el pago.   |
| RN26, RN27  | El renglón guarda su propio precio unitario, y el pedido, su propia copia de la dirección.          | —                                                       |
| RN28        | Nada se borra en cascada, y una publicación dada de baja no puede figurar como disponible.          | —                                                       |

RN17 y RN29 se cumplen por la forma de las tablas: el total del pedido no se almacena, y un pedido admite varios intentos de pago. Las restantes no pueden expresarse con restricciones y se implementan en la Etapa 5: las que dependen de otras filas o de otras tablas están listadas en [Modelo relacional](../etapa-02/modelo-relacional.md#5-reglas-que-el-esquema-no-garantiza), y las de permisos (RN02 y RN09) corresponden a la seguridad de la base.
