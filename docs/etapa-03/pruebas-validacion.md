# Pruebas y validación - Etapa 3

Este documento muestra cómo se comprobó que la implementación funciona: que los scripts crean la estructura diseñada, que los datos se cargan completos y coherentes, y que el motor rechaza los datos inválidos. Cómo se construyó la base está en [Implementación](implementacion.md), y qué protege cada restricción, en [Restricciones de integridad](restricciones-integridad.md).

## 1. Cómo se probó

- **Base descartable.** Las pruebas se ejecutaron sobre copias de los scripts que crean una base temporal en lugar de `sistema-venta-libros`. Al terminar, esa base se eliminó; la base del proyecto no se modificó.
- **Desde la línea de comandos.** Todo se ejecutó con `sqlcmd` en SQL Server 2025 Express. Así se confirma, además, que los scripts no dependen de las opciones que SSMS activa por defecto.
- **Cada prueba parte de los mismos datos.** Las operaciones que modifican filas corren dentro de una transacción que luego se deshace.

| Área        | Qué se verificó                                                                  | Pruebas                 | Resultado       |
| ----------- | -------------------------------------------------------------------------------- | ----------------------- | --------------- |
| Estructura  | Que el script cree exactamente los objetos diseñados.                            | 12 conteos              | Coincide        |
| Scripts     | Protección ante una segunda ejecución, carga «todo o nada», idioma de la sesión. | 6 escenarios            | Correcto        |
| Datos       | Cantidad de filas y coherencia con las reglas de negocio.                        | 21 tablas, 15 controles | Sin diferencias |
| Integridad  | Que se rechacen los datos inválidos y se acepten los válidos.                    | 59 casos                | 59 de 59        |
| Historial   | Que las ventas no se alteren por cambios de precio, de dirección o por bajas.    | 4 operaciones           | Correcto        |

## 2. Estructura creada

Después de ejecutar el DDL, se consultó el catálogo del motor para contar lo que efectivamente se creó y compararlo con el diseño:

| Objeto                                | Diseño  | Creado  |
| ------------------------------------- | ------- | ------- |
| Tablas                                | 21      | 21      |
| Columnas (obligatorias)               | 97 (82) | 97 (82) |
| Claves primarias                      | 21      | 21      |
| Restricciones `UNIQUE`                | 17      | 17      |
| Índices únicos filtrados              | 2       | 2       |
| Claves foráneas (todas `NO ACTION`)   | 22      | 22      |
| Validaciones `CHECK`                  | 18      | 18      |
| Valores por defecto                   | 4       | 4       |

Además, todas las restricciones tienen su nombre explícito, con el prefijo que corresponde, y ninguna clave foránea ni validación quedó deshabilitada o sin verificar.

## 3. Ejecución de los scripts

| Situación                                  | Resultado                                                     |
| ------------------------------------------ | ------------------------------------------------------------- |
| DDL sobre un servidor sin la base          | Crea la base con sus 21 tablas.                               |
| DDL por segunda vez                        | Avisa que la base ya existe y se detiene sin modificar nada.  |
| Carga de datos sobre tablas vacías         | Inserta 6.173 filas y confirma «Precarga finalizada…».        |
| Carga de datos por segunda vez             | Avisa que la base ya tiene datos; siguen siendo 6.173 filas.  |
| Carga con un error en el último `INSERT`   | Informa el error y las 21 tablas quedan vacías.               |
| Carga con la sesión en español             | Inserta las mismas 6.173 filas, con fechas idénticas.         |

**Todo o nada.** Para provocar el error se alteró una copia del script de datos, con importe cero en el último pago. El motor rechazó esa fila por `chk_pago_importe` y deshizo todo lo insertado antes: no quedó una carga a medias.

**Idioma de la sesión.** En español, el motor lee las fechas como día/mes. Una fecha escrita con un espacio cambia de sentido; las del script, no:

```sql
SET LANGUAGE Español;
SELECT CAST('2026-03-05 10:15:00' AS DATETIME);  -- 2026-05-03: 3 de mayo
SELECT CAST('2026-03-05T10:15:00' AS DATETIME);  -- 2026-03-05: 5 de marzo, como en el script
```

## 4. Datos de prueba

Las filas cargadas coinciden, tabla por tabla, con las cantidades de [Implementación](implementacion.md#62-cantidad-de-registros).

Algunas reglas de negocio no las controla el esquema, porque dependen de otras filas o de otras tablas. Para comprobar que los datos de prueba igualmente las respetan, se buscaron con consultas las filas que las incumplirían. **Ninguna consulta encontró casos:**

| Reglas     | Se buscaron                                                                                       |
| ---------- | ------------------------------------------------------------------------------------------------- |
| RN04, RN10 | Pedidos de usuarios que no son clientes; publicaciones de usuarios que no son vendedores.         |
| RN08, RN15 | Libros sin autor; pedidos sin renglones.                                                          |
| RN12       | Renglones con publicaciones no vigentes al hacer el pedido; publicaciones disponibles sin stock.  |
| RN18       | Pedidos cuya dirección de envío no coincide con ninguna dirección del cliente.                    |
| RN19       | Pedidos confirmados o entregados sin pago aprobado, y pendientes o cancelados con uno.            |
| RN22       | Pagos cuyo importe difiere del total del pedido.                                                  |
| RN24       | Pedidos con dos pagos aprobados; nuevos intentos después de uno pendiente o aprobado.             |
| RN25       | Pagos aprobados sin fecha de acreditación, o no aprobados con ella.                               |
| RN28       | Pedidos realizados por un cliente después de su baja.                                             |
| —          | Pagos iniciados antes que su pedido.                                                              |

También se confirmó el escenario del precio histórico (RN26): 795 de los 1.290 renglones guardan un precio unitario distinto del precio actual de su publicación, entre ellos los dos del pedido 94.

Para una revisión visual, `sql/consultas/control/control-carga-datos.sql` muestra el contenido completo de cada tabla.

## 5. Restricciones de integridad

Para cada restricción se intentó una operación que la incumple, que debía rechazarse, y en los casos límite, una válida, que debía aceptarse. Antes, ocho inserciones correctas en las tablas probadas confirmaron que las filas de prueba son válidas, así que cada rechazo se debe solo al dato alterado.

| Integridad  | Casos | Resultado |
| ----------- | ----- | --------- |
| Controles   | 8     | 8 de 8    |
| De entidad  | 13    | 13 de 13  |
| Referencial | 11    | 11 de 11  |
| De dominio  | 27    | 27 de 27  |

En cada rechazo, el mensaje de error nombra la restricción incumplida. Por ejemplo, al dar de baja una publicación sin marcarla como no disponible:

```sql
UPDATE dbo.PUBLICACION SET fecha_eliminacion = GETDATE() WHERE publicacion_id = 1;
-- Msg 547: The UPDATE statement conflicted with the CHECK constraint
--          "chk_publicacion_eliminada_no_disponible".
```

### 5.1 De entidad

| Intento                                                         | Resultado | Lo controla                              |
| --------------------------------------------------------------- | --------- | ---------------------------------------- |
| Un usuario con un DNI ya registrado                             | Rechazado | `uq_usuario_dni`                         |
| Un email ya registrado, escrito en mayúsculas                   | Rechazado | `uq_usuario_email`                       |
| La categoría «novela», cuando ya existe «Novela»                | Rechazado | `uq_categoria_nombre`                    |
| La categoría «Poesia», cuando ya existe «Poesía»                | Aceptado  | La intercalación distingue tildes.       |
| Un ISBN o un ISNI ya registrados                                | Rechazado | `uq_libro_isbn`, `uq_autor_isni`         |
| Otro autor sin ISNI                                             | Aceptado  | El índice filtrado ignora los vacíos.    |
| Una segunda publicación vigente del mismo libro y condición     | Rechazado | `uq_publicacion_usuario_libro_condicion` |
| Volver a publicar un libro después de dar de baja la oferta     | Aceptado  | El índice filtrado ignora las bajas.     |
| La misma publicación dos veces en un pedido                     | Rechazado | `uq_pedido_detalle_pedido_publicacion`   |

También se rechazaron una clave primaria repetida, una ciudad repetida en su provincia y un autor repetido en un libro.

### 5.2 Referencial

| Intento                                   | Resultado | Lo controla                               |
| ----------------------------------------- | --------- | ----------------------------------------- |
| Un pedido de un cliente inexistente       | Rechazado | `fk_pedido_usuario`                       |
| Un renglón de una publicación inexistente | Rechazado | `fk_pedido_detalle_publicacion`           |
| Un autor sin nacionalidad                 | Aceptado  | La referencia es opcional.                |
| Un autor con una nacionalidad inexistente | Rechazado | `fk_autor_nacionalidad`                   |
| Borrar una categoría con libros           | Rechazado | `fk_libro_categoria`                      |
| Borrar una categoría sin libros           | Aceptado  | Nada la referencia.                       |
| Borrar una publicación ya vendida         | Rechazado | `fk_pedido_detalle_publicacion`           |
| Borrar un cliente con pedidos             | Rechazado | `fk_pedido_usuario`                       |
| Cambiar el ID de un libro                 | Rechazado | El motor no modifica columnas `IDENTITY`. |

Completan el grupo un pago con un método inexistente y el borrado de un pedido con renglones; ambos se rechazaron.

### 5.3 De dominio

Se probaron los 18 `CHECK`, cada uno con al menos un valor inválido, y tres columnas obligatorias con un valor vacío; todos se rechazaron. Los casos más reveladores son los de borde:

| Intento                                                        | Resultado             |
| -------------------------------------------------------------- | --------------------- |
| DNI con puntos, o de 6 dígitos                                 | Rechazado             |
| ISBN de 9 dígitos, o con guiones                               | Rechazado             |
| ISNI con una letra intermedia, o de 15 caracteres              | Rechazado             |
| Fecha de nacimiento de mañana                                  | Rechazado             |
| Año de publicación siguiente al actual / dos años después      | Aceptado / Rechazado  |
| Stock en cero / stock que quedaría negativo                    | Aceptado / Rechazado  |
| Baja de una publicación no disponible / que sigue disponible   | Aceptado / Rechazado  |
| Acreditación de un pago anterior a su inicio                   | Rechazado             |

**Valores por defecto.** Una publicación, un pedido y un pago insertados sin fecha recibieron el momento de la inserción, y la publicación quedó disponible.

## 6. Historial y bajas lógicas

Estas pruebas comprueban que los cambios posteriores no alteran las ventas ya registradas:

| Operación                                                  | Efecto sobre los pedidos                                         | Regla |
| ---------------------------------------------------------- | ---------------------------------------------------------------- | ----- |
| Subir el precio de la publicación 184 de $18.500 a $30.000 | El pedido 94 conserva su total: $39.900.                         | RN26  |
| Cambiar la calle de la dirección 1                         | El pedido 94 conserva la dirección original: Junín 1234.         | RN27  |
| Borrar la dirección 2                                      | El pedido 259 conserva su copia: Av. 3 de Abril 850.             | RN27  |
| Dar de baja al cliente 7 y a la publicación 202            | Los 18 renglones que los involucran siguen pudiendo consultarse. | RN28  |

## 7. Alcance de las pruebas

- **Reglas que dependen de otras filas.** Se verificó que los datos de prueba las cumplen, no que el motor impida violarlas: hoy, un pedido de un vendedor o un renglón sin stock suficiente se aceptarían. Su control y sus pruebas corresponden a la Etapa 5.
- **Versión del motor.** Las pruebas corrieron en SQL Server 2025. La compatibilidad con la versión 2012 surge de la sintaxis elegida, no de haberlas repetido en esa versión.
- **Mayúsculas y tildes.** Los resultados de unicidad de texto corresponden a la intercalación del servidor del equipo, `SQL_Latin1_General_CP1_CI_AS`; en un servidor con otra intercalación podrían variar.
