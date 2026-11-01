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
| Triggers    | Que se rechacen las operaciones directas inválidas y se propaguen los cambios.   | 26 casos, 3 controles   | 26 de 26        |

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

## 7. Triggers

Estas pruebas ejercitan los [triggers](restricciones-integridad.md#6-triggers) con sentencias directas sobre las tablas, sin pasar por los procedimientos. Cada caso corre en su propia transacción y se deshace al terminar, porque un error dentro de un trigger condena la transacción. En los rechazos se comprueba el número de error, y en las operaciones aceptadas, también el efecto que debía propagarse.

| Operación                                                                                                       | Resultado                                                        | Lo controla                 |
| --------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | --------------------------- |
| Cancelar el pedido de un pago pendiente y aprobar ese pago                                                      | Rechazado (50201)                                                | `trg_PAGO_ConfirmarPedido`  |
| Aprobar un pago rechazado de un pedido entregado                                                                | Rechazado (50222), no por `trg_PAGO_ConfirmarPedido`             | Orden de los triggers       |
| Dejar sin stock las publicaciones de un pago pendiente y aprobarlo                                              | Rechazado (50202)                                                | `trg_PAGO_ConfirmarPedido`  |
| Pasar a confirmado un pedido pendiente sin pago                                                                 | Rechazado (50216)                                                | `trg_PEDIDO_Transicion`     |
| Lo mismo, con sus publicaciones sin stock                                                                       | Rechazado (50216), no por `chk_publicacion_stock`                | Orden de los triggers       |
| Pasar de pendiente a entregado, de cancelado a pendiente, de entregado a confirmado y de confirmado a cancelado | Rechazado (50215), cada uno                                      | `trg_PEDIDO_Transicion`     |
| Cambiar el cliente, la ciudad, la calle, la altura, el código postal, el piso o el departamento                 | Rechazado (50214), cada uno                                      | `trg_PEDIDO_Transicion`     |
| Cambiar solo las mayúsculas de la calle                                                                         | Rechazado (50214)                                                | `trg_PEDIDO_Transicion`     |
| Cambiar la referencia de vacía a un texto, y de un texto a vacía                                                | Rechazado (50214), cada uno                                      | `trg_PEDIDO_Transicion`     |
| Aprobar un pago con stock justo                                                                                 | Aceptado: pedido confirmado, stock 0 y publicación no disponible | Los tres de la cadena       |
| Aprobar dos pagos en una sentencia, de 2 unidades de la misma publicación con stock 10                          | Aceptado: stock 6                                                | `trg_PEDIDO_DescontarStock` |
| Dar de alta una publicación con stock 0                                                                         | Aceptado: queda no disponible                                    | `trg_PUBLICACION_Agotada`   |
| Reponer stock de una publicación agotada                                                                        | Aceptado: sigue no disponible                                    | `trg_PUBLICACION_Agotada`   |
| Cancelar un pedido pendiente                                                                                    | Aceptado: stock sin cambios                                      | `trg_PEDIDO_Transicion`     |
| Pasar un pedido de confirmado a entregado                                                                       | Aceptado: stock sin cambios                                      | `trg_PEDIDO_Transicion`     |
| Mover la fecha de un pedido                                                                                     | Aceptado                                                         | `trg_PEDIDO_Transicion`     |
| Aprobar un pago pendiente sin fecha de acreditación                                                             | Rechazado (50223)                                                | `trg_PAGO_Transicion`       |
| Rechazar un pago pendiente con fecha, y poner fecha a un pago que sigue pendiente                               | Rechazado (50223), cada uno                                      | `trg_PAGO_Transicion`       |
| Pasar un pago aprobado a rechazado                                                                              | Rechazado (50222)                                                | `trg_PAGO_Transicion`       |
| Cambiar o quitar la fecha de un pago aprobado                                                                   | Rechazado (50222), cada uno                                      | `trg_PAGO_Transicion`       |
| Cambiar el importe, el pedido o el método de un pago                                                            | Rechazado (50221), cada uno                                      | `trg_PAGO_Transicion`       |
| Pasar un pago pendiente a rechazado sin fecha, y otro a cancelado con fecha                                     | Aceptado, cada uno                                               | `trg_PAGO_Transicion`       |
| Mover la fecha de creación de un pago pendiente                                                                 | Aceptado                                                         | `trg_PAGO_Transicion`       |
| Cambiar el precio unitario o la cantidad de un renglón, y borrar un renglón                                     | Rechazado (50251), cada uno                                      | `trg_DETALLE_Congelado`     |
| Dar de alta un pago aprobado, y uno pendiente con fecha                                                         | Rechazado (50231), cada uno                                      | `trg_PAGO_Alta`             |
| Dar de alta un pago sobre un pedido confirmado                                                                  | Rechazado (50232)                                                | `trg_PAGO_Alta`             |
| Dar de alta un segundo pago con uno pendiente, y dos pagos en una sentencia sobre un pedido sin pagos           | Rechazado (50233), cada uno                                      | `trg_PAGO_Alta`             |
| Dar de alta un pago con importe distinto del total, y uno sobre un pedido sin renglones                         | Rechazado (50234), cada uno                                      | `trg_PAGO_Alta`             |
| Dar de alta un pago con la reserva vencida, y uno sobre un pedido con fecha futura                              | Rechazado (50235), cada uno                                      | `trg_PAGO_Alta`             |
| Dar de alta un pago con la reserva vigente                                                                      | Aceptado                                                         | `trg_PAGO_Alta`             |
| Borrar un pago                                                                                                  | Rechazado (50241)                                                | `trg_PAGO_SinBorrado`       |
| Borrar sin afectar ninguna fila, en pagos y en renglones                                                        | Aceptado                                                         | Triggers de borrado         |
| Cambiar el libro, la condición o el vendedor de una publicación con renglones                                   | Rechazado (50274), cada uno                                      | `trg_PUBLICACION_Historial` |
| Revertir la baja de una publicación                                                                             | Rechazado (50275)                                                | `trg_PUBLICACION_Historial` |
| Cambiar el precio y el stock de una publicación vendida                                                         | Aceptado                                                         | `trg_PUBLICACION_Historial` |
| Dar de baja una publicación, y cambiar el libro de una publicación sin renglones                                | Aceptado, cada uno                                               | `trg_PUBLICACION_Historial` |
| Dar de alta un pedido entregado                                                                                 | Rechazado (50211)                                                | `trg_PEDIDO_Alta`           |
| Dar de alta un pedido de un vendedor, y uno de un cliente dado de baja                                          | Rechazado (50212), cada uno                                      | `trg_PEDIDO_Alta`           |
| Dar de alta un pedido con una dirección inventada, y uno con la dirección de otro cliente                       | Rechazado (50213), cada uno                                      | `trg_PEDIDO_Alta`           |
| Dar de alta un pedido con piso o departamento que la dirección no tiene, y uno sin el piso que sí tiene         | Rechazado (50213), cada uno                                      | `trg_PEDIDO_Alta`           |
| Dar de alta dos pedidos en una sentencia, uno de ellos con una dirección inventada                              | Rechazado (50213)                                                | `trg_PEDIDO_Alta`           |
| Dar de alta pedidos con la dirección del cliente, con piso y sin piso                                           | Aceptado, cada uno                                               | `trg_PEDIDO_Alta`           |
| Editar una dirección de un cliente con pedidos                                                                  | Aceptado: el pedido conserva su copia                            | `trg_PEDIDO_Alta`           |
| Publicar con un cliente, y pasarle a un cliente una publicación sin renglones                                   | Rechazado (50271), cada uno                                      | `trg_PUBLICACION_Vendedor`  |
| Publicar un libro sin autor, y pasar a ese libro una publicación sin renglones                                  | Rechazado (50272), cada uno                                      | `trg_PUBLICACION_Vendedor`  |
| Publicar con un vendedor dado de baja, y pasarle una publicación sin renglones                                  | Rechazado (50273), cada uno                                      | `trg_PUBLICACION_Vendedor`  |
| Dar de alta una publicación de un vendedor activo                                                               | Aceptado: queda disponible                                       | `trg_PUBLICACION_Vendedor`  |
| Pausar y reanudar una publicación                                                                               | Aceptado                                                         | `trg_PUBLICACION_Vendedor`  |
| Agotar una publicación de un vendedor dado de baja                                                              | Aceptado: queda no disponible                                    | `trg_PUBLICACION_Vendedor`  |
| Cambiar el rol de un cliente con pedidos, y el de un vendedor con publicaciones                                 | Rechazado (50281), cada uno                                      | `trg_USUARIO_CambioRol`     |
| Cambiar el rol de un usuario sin pedidos ni publicaciones                                                       | Aceptado                                                         | `trg_USUARIO_CambioRol`     |
| Reasignar el mismo rol a un cliente con pedidos                                                                 | Aceptado                                                         | `trg_USUARIO_CambioRol`     |

Los 84 casos dieron el resultado esperado. Para comprobar que las pruebas del orden no pasaban por casualidad, se invirtió el orden de los triggers de cada tabla. En PEDIDO, el caso falló con el error 547, y en PAGO, con el 50201, como se esperaba. Ambos volvieron a pasar al restaurar el orden. De la misma forma, al quitar de `trg_PUBLICACION_Vendedor` la condición `disponible = 1`, agotar una publicación de un vendedor dado de baja falló con el error 50273, y volvió a pasar al restaurarla.

**Altas simultáneas.** Se lanzaron dos `INSERT` directos sobre el mismo pedido desde sesiones distintas, cada una con su transacción abierta. Los dos se aceptaron y el pedido quedó con dos pagos pendientes: `trg_PAGO_Alta` no ve la fila sin confirmar de la otra sesión. Por el procedimiento, el mismo caso da un solo pago, como muestran las [pruebas de concurrencia](../../sql/tecnico/procedimientos_funciones/registrar_venta/evidencias/concurrencia.md). Es un límite conocido, descrito en [Restricciones de integridad](restricciones-integridad.md#6-triggers).

**Datos cargados.** Los triggers revisan solo las filas que cambian, así que los datos de prueba se comprobaron con consultas. Ninguna encontró casos:

| Reglas     | Se buscaron                                                    |
| ---------- | -------------------------------------------------------------- |
| RN19       | Pagos aprobados con el pedido fuera de confirmado o entregado. |
| RN19       | Pedidos confirmados o entregados sin pago aprobado.            |
| RN12, RN14 | Publicaciones sin stock que figuran como disponibles.          |
| RN25       | Pagos aprobados sin fecha de acreditación.                     |
| RN25       | Pagos pendientes o rechazados con fecha de acreditación.       |
| RN22       | Pagos con un importe distinto del total del pedido.            |
| RN24       | Pedidos con más de un pago pendiente o aprobado.               |
| RN15       | Pedidos sin renglones.                                         |
| RN10       | Publicaciones de un usuario sin rol de vendedor.               |
| RN08       | Publicaciones de un libro sin autor.                           |
| RN04       | Pedidos de un usuario sin rol de cliente.                      |
| RN18       | Pedidos cuya dirección no coincide con una del cliente.        |

**Instalación.** Con los triggers instalados después de la carga, `datos_prueba.sql` sigue cargando sus filas sin cambios. El script de triggers se detiene sin crear nada si la base no tiene datos o falta `fn_TotalPedido`, y `registrar_venta/script.sql` se detiene si falta `trg_PAGO_ConfirmarPedido`, `trg_PAGO_SinBorrado` o `trg_DETALLE_Congelado`. Repetir el script de triggers los reemplaza y conserva el orden.

**Flujo completo.** Con los triggers activos, la demostración de `registrar_venta/script.sql` dio 47 de 47 comprobaciones en dos ejecuciones seguidas, sin dejar filas ni triggers deshabilitados. La secuencia de la limpieza, con un error provocado después de deshabilitar los triggers, también los dejó habilitados. Las [pruebas de concurrencia](../../sql/tecnico/procedimientos_funciones/registrar_venta/evidencias/concurrencia.md) dieron los cinco casos correctos y ningún interbloqueo.

## 8. Alcance de las pruebas

- **Reglas que dependen de otras filas.** Se verificó que los datos de prueba las cumplen, no que el motor impida violarlas: hoy, un pedido de un vendedor o un renglón sin stock suficiente se aceptarían. Su control y sus pruebas corresponden a la Etapa 5.
- **Versión del motor.** Las pruebas corrieron en SQL Server 2025. La compatibilidad con la versión 2012 surge de la sintaxis elegida, no de haberlas repetido en esa versión.
- **Mayúsculas y tildes.** Los resultados de unicidad de texto corresponden a la intercalación del servidor del equipo, `SQL_Latin1_General_CP1_CI_AS`; en un servidor con otra intercalación podrían variar.
