# Transacciones - Etapa 5

## 1. Definición y objetivo

Una **transacción** es una unidad de trabajo: un conjunto de lecturas y escrituras que se confirma entero (`COMMIT`) o se revierte entero (`ROLLBACK`). Nunca queda aplicada una parte.

| Propiedad    | Qué garantiza                                    | Mecanismo en SQL Server                                                                                                   |
| ------------ | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Atomicidad   | Se aplican todos los cambios o ninguno           | `COMMIT` y `ROLLBACK`                                                                                                     |
| Consistencia | La base pasa de un estado válido a otro válido   | Restricciones (`CHECK`, `UNIQUE`, `FOREIGN KEY`) y triggers, que corren dentro de la transacción y la revierten si fallan |
| Aislamiento  | Las transacciones simultáneas no se pisan        | Bloqueos (`UPDLOCK`) y versiones de fila (`READ_COMMITTED_SNAPSHOT`)                                                      |
| Durabilidad  | Lo confirmado sobrevive a una caída del servidor | El registro de transacciones, que se escribe en disco antes de confirmar                                                  |

SQL Server tiene tres modos:

- **Automático** (por defecto): cada sentencia es su propia transacción. Alcanza para el alta de una categoría, que hace un solo `INSERT`.
- **Explícito:** `BEGIN TRANSACTION` abre la transacción y `COMMIT` o `ROLLBACK` la cierran. Es el que usan los procedimientos de varios pasos.
- **Implícito:** con `SET IMPLICIT_TRANSACTIONS ON`, la primera sentencia abre una transacción que sigue abierta hasta un `COMMIT`. El proyecto no lo usa.

El objetivo es que una operación de varios pasos no quede a medias, y que dos operaciones simultáneas sobre las mismas filas no se pisen.

## 2. Ventajas y aplicaciones

- **Atomicidad:** un libro sin autor o un pedido sin renglones no pueden quedar guardados, porque `LIBRO` y `AUTOR_LIBRO`, o `PEDIDO` y `PEDIDO_DETALLE`, se insertan en la misma transacción.
- **Los triggers forman parte de la transacción:** al aprobar un pago, los triggers confirman el pedido, descuentan el stock y ocultan la publicación agotada, y todo se confirma o se revierte junto. Además, un trigger ve las filas sin confirmar de su propia transacción, como la autoría recién insertada.
- **Aislamiento:** comprobar y escribir sin carreras. Entre leer que un pedido está Pendiente y cancelarlo, una aprobación no puede confirmarlo; entre comprobar que un ISBN no existe e insertarlo, otra alta no puede registrarlo.
- **Recuperación ante errores:** con `XACT_ABORT ON` y el `CATCH`, ninguna llamada, tampoco una que falla, deja una transacción abierta. Las demostraciones lo comprueban después de cada llamada.
- **Criterio del proyecto, transacciones breves:** una transacción no abarca esperas del usuario ni de la pasarela de pago, porque retendría sus bloqueos durante minutos. Por eso la venta son tres transacciones (crear el pedido, iniciar el pago y registrar su resultado), y la reserva de stock no es un bloqueo: se calcula al consultar.

## 3. Implementación en SQL Server Express

SQL Server Express usa el mismo T-SQL que las demás ediciones para transacciones y bloqueos. Todas las evidencias de la etapa se obtuvieron en SQL Server 2025 Express Edition.

```sql
-- Patrón de transacción del proyecto, resumido de cancelar_pedido/script.sql
SET XACT_ABORT ON;                      -- cualquier error revierte la transacción entera
-- validaciones que no dependen de otras sesiones, antes de abrirla
BEGIN TRY
    BEGIN TRANSACTION;
    SELECT @EstadoPedido = ...          -- leer el estado con la fila bloqueada
    FROM dbo.PEDIDO AS P WITH (UPDLOCK, ROWLOCK)
    WHERE P.pedido_id = @PedidoId;
    IF @EstadoPedido IS NULL OR @EstadoPedido <> 'Pendiente'
        THROW 50312, 'Solo se puede cancelar un pedido pendiente.', 1;
    UPDATE dbo.PEDIDO SET pedido_estado_id = ... WHERE pedido_id = @PedidoId;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;   -- 1: activa; -1: no confirmable
    THROW;                              -- relanza el error original
END CATCH;
```

Recursos que usan los scripts del proyecto:

- **`XACT_ABORT ON` y `XACT_STATE()`:** con `XACT_ABORT ON`, cualquier error, también el de una restricción, revierte la transacción entera y no solo la sentencia que falló. `@@TRANCOUNT` cuenta las transacciones abiertas; `XACT_STATE()` dice además si se pueden confirmar (1), si solo admiten `ROLLBACK` (-1) o si no hay ninguna (0). Un error dentro del `TRY`, también el de un trigger, deja la transacción no confirmable, y el `CATCH` la revierte.
- **Bloqueos para comprobar y escribir:** `UPDLOCK, ROWLOCK` bloquea la fila leída hasta el `COMMIT`, y otra sesión que quiera modificarla espera a que la primera termine. Para comprobar que algo no existe, como un ISBN antes del alta, `UPDLOCK, HOLDLOCK` bloquea el rango de la clave aunque no haya fila: la segunda alta del mismo ISBN espera y recibe el mensaje del procedimiento en lugar del error del índice único.
- **Orden fijo de bloqueo:** PEDIDO, PAGO y PUBLICACION. Primero se bloquea y se valida, después se escribe. Así dos sesiones no se esperan mutuamente.
- **`READ_COMMITTED_SNAPSHOT`:** lo activa [`triggers-consistencia.sql`](../../ddl/triggers-consistencia.sql) para que las lecturas usen la última versión confirmada y no esperen. La contracara es que una lectura sin bloqueo no ve un cambio en curso: por eso cada lectura que decide una escritura usa `UPDLOCK`.
- **Sin transacciones anidadas reales:** un `BEGIN TRANSACTION` dentro de otra solo sube el contador, el `COMMIT` interno solo lo baja, y un `ROLLBACK` revierte todo hasta la más externa. Por eso los procedimientos se llaman sin una transacción abierta.
- **IDENTITY no se revierte:** un alta revertida, o un `INSERT` que falla, consume igual su valor.
- **`DISABLE TRIGGER` es transaccional:** las limpiezas de las demostraciones deshabilitan triggers dentro de una transacción. Si algo falla, el `ROLLBACK` los vuelve a habilitar.

## 4. Casos concretos aplicados al sistema de ventas

- **[`alta_libro_con_autores`](alta_libro_con_autores/)**: un procedimiento registra en una sola transacción el libro, sus autores nuevos, la autoría y, si lo pide un vendedor, la primera publicación. Así cumple RN08, que todo libro tenga autor, algo que un trigger no puede exigir en el alta, y valida RN06, RN07, RN09 y RN10. La demostración provoca un fallo en el tercer paso y otro en el último: con la transacción no queda nada guardado, y las mismas sentencias sin transacción dejan un libro sin autor. Resultado: 28 de 28 comprobaciones.
  [`script.sql`](alta_libro_con_autores/script.sql) · [`demostracion.sql`](alta_libro_con_autores/demostracion.sql) · [`evidencias/demostracion.md`](alta_libro_con_autores/evidencias/demostracion.md)

- **[`cancelar_pedido`](cancelar_pedido/)**: un procedimiento cancela un pedido Pendiente del cliente dueño (RN20) y bloquea el pedido entre la lectura del estado y el cambio. No toca el stock, porque la reserva se libera sola (RN33), ni el pago abierto, que si se aprueba después queda como cobro sin venta (RN37). Resultado: 24 de 24 comprobaciones. En la concurrencia, frente a una aprobación simultánea gana quien bloquea primero, y en la carrera libre cada pedido terminó confirmado o cancelado, sin estados mixtos ni interbloqueos.
  [`script.sql`](cancelar_pedido/script.sql) · [`demostracion.sql`](cancelar_pedido/demostracion.sql) · [`evidencias/demostracion.md`](cancelar_pedido/evidencias/demostracion.md) · [`evidencias/concurrencia.md`](cancelar_pedido/evidencias/concurrencia.md)

- **[Ciclo de venta](../procedimientos_funciones/registrar_venta/)**, implementado en el tema anterior: tres transacciones breves que bloquean en el orden fijo. Un pago aprobado sin stock libre o con el pedido fuera de Pendiente se confirma sin error, con el pago Cancelado como rastro del cobro (RN37), porque un `ROLLBACK` lo perdería. En la concurrencia, cada carrera por la misma fila tuvo un solo ganador y no hubo interbloqueos. Resultado: 5 de 5 casos de concurrencia correctos.
  [`script.sql`](../procedimientos_funciones/registrar_venta/script.sql) · [`demostracion.sql`](../procedimientos_funciones/registrar_venta/demostracion.sql) · [`evidencias/concurrencia.md`](../procedimientos_funciones/registrar_venta/evidencias/concurrencia.md)
