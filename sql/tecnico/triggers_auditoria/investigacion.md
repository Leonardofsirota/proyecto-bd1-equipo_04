# Triggers de auditoría - Etapa 5

## 1. Definición y objetivo

Un **trigger** es un bloque de T-SQL asociado a una tabla que SQL Server ejecuta solo cuando una sentencia `INSERT`, `UPDATE` o `DELETE` la modifica. Un trigger `AFTER` corre después de que la sentencia aplicó sus cambios, todavía dentro de su transacción, y una sola vez por sentencia, aunque afecte varias filas.

Un **trigger de auditoría** es un trigger `AFTER` que no valida ni rechaza nada: copia en una tabla aparte qué cambió, quién lo cambió y cuándo. Se diferencia de los triggers de [`triggers-consistencia.sql`](../../ddl/triggers-consistencia.sql), que rechazan cambios prohibidos o los propagan a otras tablas.

El trigger lee dos tablas virtuales, con las mismas columnas que la tabla auditada:

| Operación | `inserted`                       | `deleted`                                   | Qué registra la auditoría del proyecto                    |
| --------- | -------------------------------- | ------------------------------------------- | --------------------------------------------------------- |
| `INSERT`  | Las filas nuevas                 | Vacía                                       | Solo los valores nuevos                                   |
| `UPDATE`  | Las filas con sus valores nuevos | Las mismas filas con sus valores anteriores | Las dos versiones de las columnas cuyo valor cambió       |
| `DELETE`  | Vacía                            | Las filas borradas                          | Solo los valores anteriores: la última versión de la fila |

El objetivo es la **trazabilidad**: para cada cambio confirmado en una tabla importante para la venta, poder responder quién lo hizo, cuándo y qué valor había antes, aunque la tabla solo guarde el valor vigente.

## 2. Ventajas y aplicaciones

- **Automática y sin excepciones:** registra igual un cambio hecho por un procedimiento, por otro trigger o por una sentencia directa. Ningún procedimiento se modificó para auditar.
- **Completa lo que el esquema no guarda, sin cambiar el DDL:** el precio anterior de una publicación (cada renglón congela el suyo, RN26, pero la publicación solo guarda el vigente), la fecha de confirmación, entrega o cancelación de un pedido, la de un rechazo de pago y la fecha de alta de un usuario.
- **Distingue el origen de cada cambio:** separa los descuentos de stock por venta de los ajustes manuales del vendedor, que son los que hay que poder explicar, y las bajas en cascada de las que hace el propio vendedor.
- **Control de las acciones sensibles:** quién cambió un rol (RN02), quién dio de baja o reactivó a un usuario (RN28), quién resolvió cada intento de pago (RN23 a RN25) y qué cobros terminaron sin venta (RN37).
- **Coherente con la transacción:** el registro se confirma o se revierte junto con el cambio. Un cambio rechazado o revertido no deja eventos, y un evento siempre corresponde a un cambio que quedó en la base.
- **Criterio del proyecto, auditar lo que se pierde:** cada trigger audita solo las columnas cuyo historial no queda en otro lugar. `PEDIDO` no audita su alta, porque ya guarda el cliente y la fecha, y `PAGO` no audita el borrado, porque un trigger de consistencia lo rechaza siempre.

Límites:

- **Una escritura más por cambio:** cada fila auditada agrega un evento y una fila por columna cambiada, dentro de la misma transacción.
- **El usuario del sistema lo declara la aplicación:** el servidor verifica el login, pero no el usuario que la aplicación declara en la sesión.
- **La tabla de auditoría no está protegida por permisos propios:** los scripts no la restringen, así que un miembro de `db_owner` puede modificarla. Protegerla le corresponde al tema [`seguridad`](../seguridad/investigacion.md).

## 3. Implementación en SQL Server Express

SQL Server Express admite triggers DML con el mismo T-SQL que las demás ediciones. Todas las evidencias se obtuvieron en SQL Server 2025 Express Edition.

```sql
-- trg_PUBLICACION_AuditoriaPrecio, resumido de auditar_precio_publicacion/script.sql
CREATE TRIGGER dbo.trg_PUBLICACION_AuditoriaPrecio ON dbo.PUBLICACION AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(precio) RETURN;           -- la sentencia no menciona la columna
    DECLARE @Cambios dbo.AuditoriaCambioType;
    INSERT INTO @Cambios (registro_id, operacion, columna, valor_anterior, valor_nuevo)
    SELECT I.publicacion_id, 'U', 'precio', D.precio, I.precio   -- valores como texto
    FROM inserted AS I
    INNER JOIN deleted AS D ON D.publicacion_id = I.publicacion_id
    WHERE EXISTS (SELECT D.precio EXCEPT SELECT I.precio);       -- distintos, contando NULL
    IF EXISTS (SELECT 1 FROM @Cambios)      -- sin cambios reales, no hay evento
        EXEC dbo.usp_RegistrarAuditoria @Tabla = 'PUBLICACION', @Origen = NULL, @Cambios = @Cambios;
END;
```

`usp_RegistrarAuditoria` registra un evento por cada fila y sus columnas cambiadas, con la fecha, el login y el usuario del sistema. Los cinco triggers siguen el mismo patrón y cambian solo las columnas, las operaciones y el origen.

Recursos que usan los scripts del proyecto:

- **Encabezado y detalle, en 3FN:** una tabla guarda un evento por fila cambiada, con quién y cuándo, y otra un detalle por columna, con el valor anterior y el nuevo. Los valores se guardan como texto para que una sola tabla sirva a todas. La vista une ambas con el email actual del usuario, no el que tenía en el momento del evento.
- **Sin claves foráneas hacia las tablas auditadas:** el borrado de una fila auditada fallaría, y su evento no tendría a qué apuntar. Las tablas se crean solo si no existen, para no perder la auditoría al reinstalar.
- **Quién, con dos datos:** el login real, con `ORIGINAL_LOGIN()`, que no cambia con `EXECUTE AS`, y el usuario del sistema que declara la aplicación, porque se conecta con un login compartido. Ese usuario se guarda en `CONTEXT_INFO`, y no en `SESSION_CONTEXT`, por compatibilidad con SQL Server 2012. Se rechaza un usuario inexistente o dado de baja, y sin usuario declarado, como en un script de mantenimiento, el evento queda sin él.
- **`UPDATE()` frente al filtro `EXCEPT`:** `UPDATE(columna)` solo dice que la columna figura en el `SET`, y sirve para salir antes. El `EXCEPT` compara los valores: descarta `precio = precio`, cuenta como cambio el paso de NULL a un valor y, con una intercalación binaria, también un cambio solo de mayúsculas.
- **Origen de los cambios en cadena:** `TRIGGER_NESTLEVEL` indica qué trigger de consistencia provocó el cambio. Una venta que agota una publicación deja dos eventos, uno por el descuento de stock y otro por la publicación agotada. Requiere que existan esos triggers, que cada script comprueba antes, y `nested triggers` activo, su valor por defecto.
- **Dentro de la transacción de la sentencia:** el registro no abre una transacción propia, así que si la sentencia falla o se revierte, el evento también. El IDENTITY de los eventos sí deja un hueco.
- **Solo desde un trigger:** el procedimiento de registro rechaza una llamada directa, que registraría cambios que no ocurrieron.
- **Sin `sp_settriggerorder`:** la corrección no depende del orden. Una transición prohibida de un pedido o de un pago se rechaza antes de que corra la auditoría, y si la auditoría corre antes de otro error, el `ROLLBACK` la deshace igual.
- **Encadenamiento de propiedad:** los triggers, el procedimiento y las tablas son de `dbo`, así que un usuario sin permisos sobre la auditoría genera igual su evento. Los permisos se explican en [`seguridad`](../seguridad/investigacion.md).
- **Datos sensibles:** nunca se guarda la contraseña ni su hash. Un cambio de contraseña queda como `(oculto)` a `(cambiado)`.
- **Compatibilidad con SQL Server 2012:** cada trigger se recrea con `DROP` y `CREATE`, y fija `QUOTED_IDENTIFIER ON`, como en los demás temas de la etapa.

Alternativas del motor, y por qué no reemplazan a los triggers en este proyecto:

- **[Captura de datos modificados (CDC)](https://learn.microsoft.com/es-es/sql/relational-databases/track-changes/about-change-data-capture-sql-server):** guarda los valores anteriores y nuevos leyendo el registro de transacciones, pero la [tabla de ediciones](https://learn.microsoft.com/es-es/sql/sql-server/editions-and-components-of-sql-server-2025) la incluye solo en Enterprise y Standard, y su captura corre como trabajo del Agente SQL Server, que Express no tiene.
- **[Seguimiento de cambios](https://learn.microsoft.com/es-es/sql/relational-databases/track-changes/about-change-tracking-sql-server):** registra que una fila cambió y su clave primaria, sin los valores anteriores.
- **[Tablas temporales](https://learn.microsoft.com/es-es/sql/relational-databases/tables/temporal/overview):** desde SQL Server 2016 guardan cada versión anterior de la fila en una tabla de historial, pero no quién hizo el cambio, y no existen en SQL Server 2012.
- **[SQL Server Audit](https://learn.microsoft.com/es-es/sql/relational-databases/security/auditing/sql-server-audit-database-engine):** registra acciones y sentencias con el login que las ejecutó, pero no los valores de las filas ni el usuario del sistema.

## 4. Casos concretos aplicados al sistema de ventas

- **[`estructura_auditoria`](estructura_auditoria/)**: crea lo que comparten los cinco triggers: las tablas de auditoría, el usuario de la sesión, el procedimiento de registro y la vista. Resultado: 9 de 9 comprobaciones. Con la auditoría instalada, las demostraciones, los casos de los triggers de consistencia y las pruebas de concurrencia dieron lo mismo que sin ella: lo revertido no dejó eventos, cada pago tiene un solo evento de alta y no hubo interbloqueos.
  [`script.sql`](estructura_auditoria/script.sql) · [`demostracion.sql`](estructura_auditoria/demostracion.sql) · [`evidencias/demostracion.md`](estructura_auditoria/evidencias/demostracion.md) · [`evidencias/convivencia.md`](estructura_auditoria/evidencias/convivencia.md)

- **[`auditar_precio_publicacion`](auditar_precio_publicacion/)**: un trigger registra cada cambio del precio de una publicación con el valor anterior y el nuevo. Completa RN26: el renglón congela el precio de su venta, y el evento conserva los precios que la publicación tuvo entre ventas. Bajo suplantación, el evento guarda el login real. Resultado: 26 de 26 comprobaciones.
  [`script.sql`](auditar_precio_publicacion/script.sql) · [`demostracion.sql`](auditar_precio_publicacion/demostracion.sql) · [`evidencias/demostracion.md`](auditar_precio_publicacion/evidencias/demostracion.md)

- **[`auditar_stock_publicacion`](auditar_stock_publicacion/)**: un trigger registra los cambios de stock, disponibilidad y fecha de baja, y el borrado con la fila completa. El origen separa los ajustes del vendedor de los descuentos por venta, la publicación agotada y la baja en cascada de un vendedor (RN12 a RN14 y RN28). Resultado: 17 de 17 comprobaciones.
  [`script.sql`](auditar_stock_publicacion/script.sql) · [`demostracion.sql`](auditar_stock_publicacion/demostracion.sql) · [`evidencias/demostracion.md`](auditar_stock_publicacion/evidencias/demostracion.md)

- **[`auditar_pedidos`](auditar_pedidos/)**: un trigger registra los cambios de estado y de fecha de cada pedido. `PEDIDO` solo guarda cuándo se creó: el evento fecha la confirmación, la entrega y la cancelación (RN19, RN20 y RN37), y los cambios de fecha que acortan la reserva (RN34). Resultado: 18 de 18 comprobaciones.
  [`script.sql`](auditar_pedidos/script.sql) · [`demostracion.sql`](auditar_pedidos/demostracion.sql) · [`evidencias/demostracion.md`](auditar_pedidos/evidencias/demostracion.md)

- **[`auditar_pagos`](auditar_pagos/)**: un trigger registra el alta de cada pago y sus cambios de estado y de fechas. `PAGO` solo fecha la aprobación: el evento muestra quién inició cada intento y cuándo se rechazó, se aprobó o terminó como cobro sin venta (RN23 a RN25, RN29 y RN37). Resultado: 24 de 24 comprobaciones.
  [`script.sql`](auditar_pagos/script.sql) · [`demostracion.sql`](auditar_pagos/demostracion.sql) · [`evidencias/demostracion.md`](auditar_pagos/evidencias/demostracion.md)

- **[`auditar_usuarios`](auditar_usuarios/)**: un trigger registra el alta, los cambios y el borrado de cada usuario. El alta es la única fecha de registro de un cliente (RN03), y los eventos muestran quién cambió un rol (RN02), quién dio de baja o reactivó a un usuario (RN28) y los cambios de datos personales, sin guardar nunca la contraseña. Resultado: 22 de 22 comprobaciones.
  [`script.sql`](auditar_usuarios/script.sql) · [`demostracion.sql`](auditar_usuarios/demostracion.sql) · [`evidencias/demostracion.md`](auditar_usuarios/evidencias/demostracion.md)
