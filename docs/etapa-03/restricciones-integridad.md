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

Las reglas que dependen de otras filas o de otras tablas no pueden expresarse con estos mecanismos. De ellas se ocupan los [triggers](#6-triggers) y los procedimientos de la Etapa 5.

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

## 6. Triggers

Los triggers de `sql/ddl/triggers-consistencia.sql` controlan reglas que dependen de otras filas o de otras tablas. Se cumplen aunque los datos se modifiquen con sentencias directas, sin pasar por los procedimientos:

| Trigger                     | Tabla y operación                   | Reglas                 | Qué impide o propaga                                                                                                                                                                                                                           |
| --------------------------- | ----------------------------------- | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `trg_PAGO_ConfirmarPedido`  | PAGO, `UPDATE`                      | RN19, RN37             | Al aprobarse un pago, confirma su pedido. Impide aprobarlo con el pedido fuera de pendiente (error 50201) o sin stock libre para todos sus renglones (50202).                                                                                  |
| `trg_PEDIDO_DescontarStock` | PEDIDO, `UPDATE`                    | RN14                   | Al pasar un pedido de pendiente a confirmado, descuenta del stock la cantidad vendida.                                                                                                                                                         |
| `trg_PUBLICACION_Agotada`   | PUBLICACION, `INSERT` y `UPDATE`    | RN12, RN14             | Marca como no disponible la publicación que queda con stock cero.                                                                                                                                                                              |
| `trg_PEDIDO_Transicion`     | PEDIDO, `UPDATE`                    | RN19, RN20, RN27       | Impide cambiar el cliente, la ciudad o la dirección copiada (50214), pasar a un estado no permitido (50215) y confirmar un pedido sin pago aprobado (50216).                                                                                   |
| `trg_PAGO_Transicion`       | PAGO, `UPDATE`                      | RN22, RN24, RN25       | Impide cambiar el pedido, el importe o el método de un pago (50221), y modificar el estado o la fecha de acreditación de un pago ya procesado (50222). Exige la fecha en un pago aprobado y no la admite en uno pendiente o rechazado (50223). |
| `trg_DETALLE_Congelado`     | PEDIDO_DETALLE, `UPDATE` y `DELETE` | RN15, RN17, RN22, RN26 | Impide modificar o borrar renglones (50251). Para cambiar un carrito se crea otro pedido.                                                                                                                                                      |
| `trg_PAGO_Alta`             | PAGO, `INSERT`                      | RN22, RN24, RN35       | Exige que un pago nazca pendiente y sin fecha de acreditación (50231), sobre un pedido pendiente (50232), sin otro pago pendiente o aprobado (50233), por el total del pedido (50234) y con la reserva vigente (50235).                        |
| `trg_PAGO_SinBorrado`       | PAGO, `DELETE`                      | RN29                   | Impide borrar pagos (50241).                                                                                                                                                                                                                   |
| `trg_PUBLICACION_Historial` | PUBLICACION, `UPDATE`               | RN28                   | Impide cambiar el vendedor, el libro o la condición de una publicación con renglones (50274), porque reescribiría comprobantes y reportes de ventas pasadas, y revertir la baja de una publicación (50275).                                    |
| `trg_PEDIDO_Alta`           | PEDIDO, `INSERT`                    | RN04, RN18, RN19, RN28 | Exige que un pedido nazca pendiente (50211), de un cliente activo (50212) y con la copia de una dirección del cliente, que coincida en ciudad, calle, altura, código postal, piso y departamento (50213).                                      |
| `trg_PUBLICACION_Vendedor`  | PUBLICACION, `INSERT` y `UPDATE`    | RN08, RN10, RN12       | Exige que quien publica tenga el rol de vendedor (50271) y que el libro tenga autor (50272). Impide que quede disponible una publicación de un vendedor dado de baja (50273).                                                                  |
| `trg_USUARIO_CambioRol`     | USUARIO, `UPDATE`                   | RN04, RN10             | Impide cambiar el rol de un usuario con pedidos o publicaciones (50281).                                                                                                                                                                       |

Las únicas transiciones de estado permitidas para un pedido son de pendiente a confirmado, de pendiente a cancelado y de confirmado a entregado. Un pago solo cambia de estado mientras está pendiente.

- **Una cadena en una sola transacción.** Aprobar un pago confirma el pedido, confirmar el pedido descuenta el stock y el stock en cero oculta la publicación. Todo ocurre dentro de la sentencia que aprueba el pago: si un paso falla, se revierte entero. La cadena necesita la opción de servidor `nested triggers` en 1, su valor por defecto; con 0 se corta sin dar error.
- **Relación con los procedimientos.** `usp_RegistrarVenta` solo cambia el estado del pago: la confirmación y el descuento son de los triggers. Conserva su propio control del stock libre porque debe decidir antes de escribir: un error del trigger revertiría el pago, y se perdería el rastro del cobro (RN37). También conserva el control de un pago ya procesado (50123), que lee el estado con el bloqueo tomado. Por lo mismo, `usp_IniciarPago` valida antes de escribir: `trg_PAGO_Alta` no lo reemplaza, sino que cubre las sentencias directas. Tampoco `trg_PEDIDO_Alta` reemplaza los controles de `usp_CrearPedido`: el procedimiento valida al cliente y la dirección antes de abrir la transacción, mientras que el trigger solo ve la copia de la dirección.
- **Rastro del cobro.** Un pago cancelado puede tener fecha de acreditación: es el cobro que no concretó una venta (RN37).
- **Orden.** `trg_PEDIDO_Transicion` corre primero entre los triggers de PEDIDO, para que el error no dependa del orden: de lo contrario, un pedido sin pago ni stock podría fallar por `chk_publicacion_stock`. Del mismo modo, `trg_PAGO_Transicion` corre primero entre los de PAGO, para rechazar antes de que `trg_PAGO_ConfirmarPedido` propague el cambio.
- **Reponer stock no reactiva una publicación.** `disponible` no distingue una publicación agotada de una pausada, así que reanudarla es una decisión del vendedor.
- **Publicaciones de un vendedor dado de baja.** `trg_PUBLICACION_Vendedor` solo rechaza que queden disponibles. Retirarlas es válido: `trg_PUBLICACION_Agotada` lo hace cuando se quedan sin stock.
- **Libros sin autor y pedidos sin renglones.** RN08 y RN15 no se pueden exigir en el alta, porque la fila padre debe existir antes que sus autores o sus renglones. En su lugar, los triggers impiden usar esa fila: un libro sin autor no se publica (50272), y un pedido sin renglones no se paga (50234).
- **Datos que siguen modificables.** Una publicación vendida puede cambiar de precio y de stock, porque cada renglón guarda su precio (RN26). Una dirección usada en pedidos puede editarse, porque cada pedido conserva su copia (RN27).
- **Fechas libres.** `PEDIDO.fecha_pedido` y `PAGO.fecha_creacion` no se congelan: la demostración de la Etapa 5 las mueve para simular el paso del tiempo.
- **Limpieza de la demostración.** La demostración de la Etapa 5 borra sus propios pagos y renglones. Para eso deshabilita `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado` dentro de una transacción: si algo falla, se revierte también la deshabilitación.
- **Altas simultáneas.** Con `READ_COMMITTED_SNAPSHOT`, un trigger no ve las filas sin confirmar de otra sesión. Dos `INSERT` directos simultáneos sobre el mismo pedido pasan `trg_PAGO_Alta` y dejan dos pagos abiertos, como se comprobó en las [pruebas](pruebas-validacion.md#7-triggers). `usp_IniciarPago` no tiene este problema, porque bloquea la fila del pedido antes de validar: frente a altas simultáneas, RN24 queda garantizada solo si los pagos se inician por el procedimiento.
- **Filas ya cargadas.** Los triggers revisan solo las filas que cambian. Los datos de prueba se comprobaron aparte, en [Pruebas y validación](pruebas-validacion.md#7-triggers).
