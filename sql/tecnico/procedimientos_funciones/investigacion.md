# Procedimientos y funciones almacenadas - Etapa 5

## 1. Definición y objetivo

Un **procedimiento almacenado** es un bloque de T-SQL con nombre, guardado y compilado en la base. Recibe parámetros de entrada y de salida (`OUTPUT`), puede leer y modificar datos, abrir transacciones, lanzar errores y devolver conjuntos de resultados. Se ejecuta con `EXEC`.

Una **función definida por el usuario** recibe parámetros y devuelve un valor (función escalar) o una tabla. Se usa dentro de una expresión, como un `SELECT`, un `WHERE` u otra función, pero no puede modificar tablas de la base, abrir transacciones ni lanzar errores con `THROW`.

| Aspecto | Procedimiento | Función escalar |
| --- | --- | --- |
| Invocación | `EXEC dbo.usp_...` | Dentro de una expresión: `SELECT dbo.fn_...(...)` |
| Resultado | Parámetros `OUTPUT` y conjuntos de resultados | Un único valor con `RETURN` |
| Modifica datos | Sí | No |
| Transacciones y errores | `BEGIN TRANSACTION`, `TRY...CATCH`, `THROW` | No admite ninguno |

El objetivo de ambos es guardar la lógica de negocio en el servidor: cada regla se escribe una vez y la aplica igual cualquier programa que use la base.

## 2. Ventajas y aplicaciones

- **Un solo lugar para cada regla:** un cálculo o una validación se escribe una vez y se reutiliza. Por ejemplo, `fn_TotalPedido` la usan los procedimientos de venta, otras funciones, un trigger de consistencia y el comprobante de venta.
- **Integridad:** las validaciones se ejecutan siempre antes de escribir, sin depender de que la aplicación las repita.
- **Atomicidad:** un procedimiento agrupa varias escrituras en una transacción que se confirma o se revierte entera.
- **Rendimiento:** el plan de ejecución queda en caché, y una sola llamada reemplaza varias sentencias enviadas por la red.
- **Mantenimiento y seguridad:** la lógica cambia sin tocar la aplicación, y se puede dar permiso para ejecutar un objeto sin darlo sobre las tablas.

Criterio de uso en el proyecto:

- **Procedimiento**, para operaciones que escriben datos, tienen varios pasos o necesitan transacción y mensajes de error: el ABM de categorías y el ciclo de venta.
- **Función escalar**, para cálculos que se repiten y deben poder usarse dentro de una consulta: el total, el descuento, la reserva y el stock libre. Como se evalúa una vez por fila, conviene para cálculos acotados y no para recorrer grandes volúmenes.

## 3. Implementación en SQL Server Express

SQL Server Express admite procedimientos y funciones con el mismo T-SQL que las demás ediciones: sus límites de tamaño, memoria y procesadores no restringen estos objetos.

```sql
-- Creación (esquema general)
CREATE PROCEDURE dbo.usp_Nombre
    @Entrada INT,
    @Salida INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- validaciones, transacción y SELECT del resultado
END;
GO

CREATE FUNCTION dbo.fn_Nombre (@Entrada INT)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    RETURN 0;
END;
GO

-- Invocación de objetos del proyecto (los ID son de ejemplo)
EXEC dbo.usp_InsertarCategoria @Nombre = 'Narrativa breve';

DECLARE @Carrito dbo.DetalleVentaType;
INSERT INTO @Carrito (publicacion_id, cantidad) VALUES (1, 2);

DECLARE @PedidoId INT;
EXEC dbo.usp_CrearPedido
    @UsuarioId = 5,
    @DireccionId = 3,
    @Carrito = @Carrito,
    @PedidoId = @PedidoId OUTPUT;

SELECT dbo.fn_TotalPedido(@PedidoId) AS total;  -- la función se invoca con su esquema
```

Recursos que usan los scripts del proyecto:

- **Compatibilidad con SQL Server 2012:** cada procedimiento y función se recrea con `IF OBJECT_ID(...) IS NOT NULL DROP` y `CREATE`, en lugar de `CREATE OR ALTER`, que existe desde SQL Server 2016 SP1.
- **Validaciones con `THROW`:** cada error tiene un número propio (50001 a 50009 en el ABM, 50101 a 50123 en la venta) y un mensaje que explica el rechazo.
- **Transacciones con manejo de errores:** `SET XACT_ABORT ON` y `BEGIN TRY` con `BEGIN TRANSACTION` y `COMMIT`. El `CATCH` revierte si `XACT_STATE() <> 0` y relanza el error con `THROW`.
- **Bloqueos en orden fijo:** `UPDLOCK, ROWLOCK` sobre PEDIDO, PAGO y PUBLICACION, siempre en ese orden y con las publicaciones por ID ascendente. Así se serializan las operaciones sobre las mismas filas sin interbloqueos.
- **Parámetros:** un tipo de tabla (`dbo.DetalleVentaType`) pasa el carrito como parámetro `READONLY`, y los parámetros `OUTPUT` devuelven los ID generados con `SCOPE_IDENTITY()`.
- **Funciones sin errores:** como una función no puede lanzar errores, las del proyecto devuelven `NULL` o `0` ante datos faltantes o inválidos.
- **Composición:** las funciones se llaman entre sí; por ejemplo, `fn_StockLibre` usa `fn_VencimientoReserva`, y `fn_PorcentajeDescuentoPedido` usa `fn_TotalPedido`.
- **Dependencias controladas:** `registrar_venta/script.sql` comprueba que existan las funciones de descuento y los triggers de consistencia; si falta alguno, se detiene con `RAISERROR` y `SET NOEXEC ON` sin crear nada. También fija `QUOTED_IDENTIFIER ON` en cada objeto: `sqlcmd` lo trae en `OFF`, y un objeto que escribe en una tabla con índice filtrado, como PUBLICACION, falla con el error 1934.
- **Parámetros sin truncar:** el ABM recibe el nombre como `VARCHAR(MAX)`, porque con `VARCHAR(100)` SQL Server cortaría en silencio un nombre más largo antes de validarlo.

## 4. Casos concretos aplicados al sistema de ventas

- **[`abm_categorias`](abm_categorias/)**: tres procedimientos (`usp_InsertarCategoria`, `usp_ModificarCategoria` y `usp_EliminarCategoria`) mantienen la lista de categorías con un nombre obligatorio, único y de hasta 100 caracteres, y no borran una categoría que use algún libro. Resuelve RN09 y protege RN07.
  [`script.sql`](abm_categorias/script.sql) · [`demostracion.sql`](abm_categorias/demostracion.sql) · [`evidencias/demostracion.md`](abm_categorias/evidencias/demostracion.md)

- **[`calcular_descuento_pedido`](calcular_descuento_pedido/)**: cuatro funciones calculan el total del pedido (`fn_TotalPedido`), el porcentaje por tramo (`fn_PorcentajeDescuentoPedido`), el importe del descuento (`fn_ImporteDescuento`) y la parte de cada renglón para los reportes (`fn_DescuentoRenglon`). Resuelve RN17 y RN30 a RN32: el descuento se calcula y no se almacena.
  [`script.sql`](calcular_descuento_pedido/script.sql) · [`demostracion.sql`](calcular_descuento_pedido/demostracion.sql) · [`evidencias/demostracion.md`](calcular_descuento_pedido/evidencias/demostracion.md)

- **[`registrar_venta`](registrar_venta/)**: tres procedimientos crean el pedido con el precio vigente (`usp_CrearPedido`), inician el pago por el total con descuento (`usp_IniciarPago`) y registran su resultado (`usp_RegistrarVenta`), apoyados en `fn_VencimientoReserva` y `fn_StockLibre`. Resuelve la reserva y el stock libre (RN12, RN13 y RN33 a RN37), el precio y la dirección históricos (RN26 y RN27) y los pagos (RN22 y RN24).
  [`script.sql`](registrar_venta/script.sql) · [`demostracion.sql`](registrar_venta/demostracion.sql) · [`evidencias/demostracion.md`](registrar_venta/evidencias/demostracion.md) · [`evidencias/concurrencia.md`](registrar_venta/evidencias/concurrencia.md)
