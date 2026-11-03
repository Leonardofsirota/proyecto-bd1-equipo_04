# Transacciones - Etapa 5

## 1. Definición y objetivo

Una **transacción** es una unidad de trabajo: un conjunto de lecturas y escrituras que se confirma entero (`COMMIT`) o se revierte entero (`ROLLBACK`). Nunca queda aplicada una parte.

| Propiedad | Qué garantiza | Mecanismo en SQL Server |
| --- | --- | --- |
| Atomicidad | Se aplican todos los cambios o ninguno | `COMMIT` y `ROLLBACK` |
| Consistencia | La base pasa de un estado válido a otro válido | Restricciones (`CHECK`, `UNIQUE`, `FOREIGN KEY`) y triggers, que corren dentro de la transacción y la revierten si fallan |
| Aislamiento | Las transacciones simultáneas no se pisan | Bloqueos (`UPDLOCK`) y versiones de fila (`READ_COMMITTED_SNAPSHOT`) |
| Durabilidad | Lo confirmado sobrevive a una caída del servidor | El registro de transacciones, que se escribe en disco antes de confirmar |

SQL Server tiene tres modos:

- **Automático** (por defecto): cada sentencia es su propia transacción. Alcanza para `usp_InsertarCategoria`, que hace un solo `INSERT`.
- **Explícito:** `BEGIN TRANSACTION` abre la transacción y `COMMIT` o `ROLLBACK` la cierran. Es el que usan los procedimientos de varios pasos.
- **Implícito:** con `SET IMPLICIT_TRANSACTIONS ON`, la primera sentencia abre una transacción que sigue abierta hasta un `COMMIT`. El proyecto no lo usa.

El objetivo es que una operación de varios pasos no quede a medias, y que dos operaciones simultáneas sobre las mismas filas no se pisen.

## 2. Ventajas y aplicaciones

- **Atomicidad:** un libro sin autor o un pedido sin renglones no pueden quedar guardados, porque `LIBRO` y `AUTOR_LIBRO`, o `PEDIDO` y `PEDIDO_DETALLE`, se insertan en la misma transacción.
- **Los triggers forman parte de la transacción:** al aprobar un pago, `trg_PAGO_ConfirmarPedido` confirma el pedido, `trg_PEDIDO_DescontarStock` descuenta el stock y `trg_PUBLICACION_Agotada` oculta la publicación que llega a cero. Todo se confirma o se revierte junto. Un trigger también ve las filas sin confirmar de su transacción: `trg_PUBLICACION_Vendedor` acepta la publicación porque ve la autoría recién insertada.
- **Aislamiento:** comprobar y escribir sin carreras. Entre leer que un pedido está Pendiente y cancelarlo, una aprobación no puede confirmarlo; entre comprobar que un ISBN no existe e insertarlo, otra alta no puede registrarlo.
- **Recuperación ante errores:** con `XACT_ABORT ON` y el `CATCH`, una llamada que falla no deja ninguna transacción abierta. Las demostraciones suman `@@TRANCOUNT` después de cada llamada, también de las que fallan, y obtienen 0.
- **Criterio del proyecto, transacciones breves:** una transacción no abarca esperas del usuario ni de la pasarela de pago, porque retendría sus bloqueos durante minutos. Por eso la venta son tres transacciones (crear el pedido, iniciar el pago y registrar su resultado), y la reserva de stock no es un bloqueo: se calcula al consultar con `fn_VencimientoReserva` y `fn_StockLibre`.

## 3. Implementación en SQL Server Express

SQL Server Express usa el mismo T-SQL que las demás ediciones para transacciones y bloqueos. Todas las evidencias de la etapa se obtuvieron en SQL Server 2025 Express Edition.

```sql
-- Patrón de transacción del proyecto, resumido de usp_CancelarPedido
SET NOCOUNT ON;
SET XACT_ABORT ON;                      -- cualquier error revierte la transacción entera

-- Validaciones que no dependen de otras sesiones, antes de abrirla (50311)

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. Bloquear y leer: UPDLOCK retiene la fila hasta el COMMIT
    SELECT @EstadoPedido = PE.nombre
    FROM dbo.PEDIDO AS P WITH (UPDLOCK, ROWLOCK)
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.pedido_estado_id = P.pedido_estado_id
    WHERE P.pedido_id = @PedidoId;

    -- 2. Validar con la fila bloqueada
    IF @EstadoPedido IS NULL OR @EstadoPedido <> 'Pendiente'
        THROW 50312, 'Solo se puede cancelar un pedido pendiente.', 1;

    -- 3. Escribir
    UPDATE dbo.PEDIDO
    SET pedido_estado_id = (SELECT pedido_estado_id FROM dbo.PEDIDO_ESTADO WHERE nombre = 'Cancelado')
    WHERE pedido_id = @PedidoId;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0                -- 1: activa; -1: no confirmable
        ROLLBACK TRANSACTION;

    THROW;                              -- relanza el error original
END CATCH;

-- El SELECT del resultado va después del COMMIT
```

Recursos que usan los scripts del proyecto:

- **`XACT_ABORT ON`:** cualquier error, también el de una restricción (547 de `chk_publicacion_precio`, 2601 de `uq_autor_isni`), revierte la transacción entera y no solo la sentencia que falló.
- **`XACT_STATE()` frente a `@@TRANCOUNT`:** `@@TRANCOUNT` cuenta las transacciones abiertas; `XACT_STATE()` dice además si se pueden confirmar (1), si solo admiten `ROLLBACK` (-1) o si no hay ninguna (0). Un error dentro del `TRY`, incluido el `THROW` de un trigger como el 50215 de `trg_PEDIDO_Transicion`, deja la transacción en -1, y el `CATCH` la revierte.
- **`UPDLOCK, ROWLOCK`** para comprobar y escribir: el `SELECT` bloquea la fila hasta el `COMMIT`, y otra sesión que quiera el mismo bloqueo espera. **`UPDLOCK, HOLDLOCK`** para comprobar que algo no existe: bloquea el rango del ISBN en `uq_libro_isbn` aunque no haya fila, y otra alta del mismo ISBN espera y recibe 50306 en lugar del error 2627 del índice.
- **Orden fijo de bloqueo:** PEDIDO, PAGO y PUBLICACION, con las publicaciones de a una y por `publicacion_id` ascendente. Primero se bloquea y se valida, después se escribe. Así dos sesiones no esperan cada una lo que tiene la otra.
- **`READ_COMMITTED_SNAPSHOT`:** lo activa [`triggers-consistencia.sql`](../../ddl/triggers-consistencia.sql) para que las lecturas usen la última versión confirmada y no esperen. La contracara es que una lectura sin bloqueo no ve un cambio en curso: por eso cada validación que decide una escritura usa `UPDLOCK`. Sin él, la cancelación que pierde la carrera recibe 50215 del trigger en lugar de 50312.
- **Sin transacciones anidadas reales:** un `BEGIN TRANSACTION` dentro de otra solo sube `@@TRANCOUNT`, el `COMMIT` interno solo lo baja, y un `ROLLBACK` revierte todo hasta la más externa. Por eso los procedimientos se llaman sin una transacción abierta, y las demostraciones no usan una transacción externa.
- **IDENTITY no se revierte:** un alta revertida, o un `INSERT` que falla en un índice o un `CHECK`, consume igual su valor. En la demostración del alta, el `IDENT_CURRENT` de `LIBRO` pasó de 500 a 505 con las mismas 500 filas.
- **`DISABLE TRIGGER` es transaccional:** las limpiezas de las demostraciones deshabilitan `trg_AUTOR_LIBRO_UltimoAutor`, `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado` dentro de una transacción con `XACT_ABORT ON`. Si algo falla, el `ROLLBACK` los deja habilitados otra vez.

## 4. Casos concretos aplicados al sistema de ventas

- **[`alta_libro_con_autores`](alta_libro_con_autores/)**: `usp_RegistrarLibroConAutores` registra en una sola transacción el libro, sus autores nuevos, la autoría y, si lo pide un vendedor, la primera publicación. Resuelve RN08 (todo libro tiene autor), que un trigger no puede exigir en el alta, y valida RN06, RN07, RN09 y RN10 (errores 50301 a 50309). Un fallo en el tercer paso (2601) o en el último (547) no deja nada, mientras que las mismas sentencias sin transacción dejan un libro sin autor. Resultado: 28 de 28 comprobaciones.
  [`script.sql`](alta_libro_con_autores/script.sql) · [`demostracion.sql`](alta_libro_con_autores/demostracion.sql) · [`evidencias/demostracion.md`](alta_libro_con_autores/evidencias/demostracion.md)

- **[`cancelar_pedido`](cancelar_pedido/)**: `usp_CancelarPedido` cancela un pedido Pendiente del cliente dueño (RN20), con `UPDLOCK` sobre PEDIDO entre la lectura del estado y el `UPDATE`. No toca el stock, porque la reserva se libera sola (RN33), ni el pago abierto, que si se aprueba después queda como cobro sin venta (RN37). Resultado: 24 de 24 comprobaciones. Frente a una aprobación simultánea gana quien bloquea primero, y la carrera libre de 10 pedidos terminó con 5 confirmados y 5 cancelados, sin estados mixtos ni interbloqueos.
  [`script.sql`](cancelar_pedido/script.sql) · [`demostracion.sql`](cancelar_pedido/demostracion.sql) · [`evidencias/demostracion.md`](cancelar_pedido/evidencias/demostracion.md) · [`evidencias/concurrencia.md`](cancelar_pedido/evidencias/concurrencia.md)

- **[Ciclo de venta](../procedimientos_funciones/registrar_venta/)**, implementado en el tema anterior: `usp_CrearPedido`, `usp_IniciarPago` y `usp_RegistrarVenta` son tres transacciones breves que bloquean en el orden fijo. Un pago aprobado sin stock libre o con el pedido fuera de Pendiente termina en `COMMIT` y sin error, con el pago Cancelado y su fecha como rastro del cobro (RN37): un `ROLLBACK` lo perdería. En las pruebas de concurrencia (casos A a E), cada carrera por la misma fila tuvo un solo ganador entre 8 llamadas, y las cargas mixtas terminaron sin interbloqueos (0 errores 1205).
  [`script.sql`](../procedimientos_funciones/registrar_venta/script.sql) · [`evidencias/concurrencia.md`](../procedimientos_funciones/registrar_venta/evidencias/concurrencia.md)
