# Procedimientos y funciones almacenadas - Etapa 5

## 1. Definición y objetivo

Un **procedimiento almacenado** es un bloque de T-SQL con nombre, guardado y compilado en la base. Recibe parámetros de entrada y de salida (`OUTPUT`), puede leer y modificar datos, abrir transacciones, lanzar errores y devolver conjuntos de resultados. Se ejecuta con `EXEC`.

Una **función definida por el usuario** recibe parámetros y devuelve un valor (función escalar) o una tabla. Se usa dentro de una expresión, como un `SELECT`, un `WHERE` u otra función, pero no puede modificar tablas, abrir transacciones ni lanzar errores con `THROW`.

| Aspecto                 | Procedimiento                                 | Función escalar                                   |
| ----------------------- | --------------------------------------------- | ------------------------------------------------- |
| Invocación              | `EXEC dbo.usp_...`                            | Dentro de una expresión: `SELECT dbo.fn_...(...)` |
| Resultado               | Parámetros `OUTPUT` y conjuntos de resultados | Un único valor con `RETURN`                       |
| Modifica datos          | Sí                                            | No                                                |
| Transacciones y errores | `BEGIN TRANSACTION`, `TRY...CATCH`, `THROW`   | No admite ninguno                                 |

El objetivo de ambos es guardar la lógica de negocio en el servidor: cada regla se escribe una vez y la aplica igual cualquier programa que use la base.

## 2. Ventajas y aplicaciones

- **Un solo lugar para cada regla:** un cálculo o una validación se escribe una vez y se reutiliza. Por ejemplo, el total del pedido lo usan los procedimientos de venta, otras funciones, un trigger y el comprobante.
- **Integridad:** las validaciones se ejecutan siempre antes de escribir, sin depender de que la aplicación las repita.
- **Atomicidad:** un procedimiento agrupa varias escrituras en una transacción que se confirma o se revierte entera.
- **Rendimiento:** el plan de ejecución queda en caché, y una sola llamada reemplaza varias sentencias enviadas por la red.
- **Mantenimiento y seguridad:** la lógica cambia sin tocar la aplicación, y se puede dar permiso para ejecutar un objeto sin darlo sobre las tablas.

Criterio de uso en el proyecto:

- **Procedimiento**, para operaciones que escriben datos, tienen varios pasos o necesitan transacción y mensajes de error: el ABM de categorías y el ciclo de venta.
- **Función escalar**, para cálculos que se repiten y deben poder usarse dentro de una consulta: el total, el descuento, la reserva y el stock libre. Como se evalúa una vez por fila, conviene para cálculos acotados y no para recorrer grandes volúmenes.

## 3. Implementación en SQL Server Express

SQL Server Express admite procedimientos y funciones con el mismo T-SQL que las demás ediciones: sus límites de tamaño, memoria y procesadores no restringen estos objetos. Las evidencias se obtuvieron en SQL Server 2025 Express.

```sql
-- Esquema general, resumido de los script.sql del tema
CREATE PROCEDURE dbo.usp_Nombre
    @Entrada INT,
    @Salida INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- validaciones, transacción y resultado
END;
GO
CREATE FUNCTION dbo.fn_Nombre (@Entrada INT)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    RETURN 0;  -- cálculo sin modificar tablas
END;
GO
-- Invocación de objetos del proyecto (el ID es de ejemplo)
EXEC dbo.usp_InsertarCategoria @Nombre = 'Narrativa breve';
SELECT dbo.fn_TotalPedido(1) AS total;
```

Recursos que usan los scripts del proyecto:

- **Validaciones con `THROW`:** cada rechazo lanza un error con número y mensaje propios. El ABM recibe el nombre sin límite de longitud: con un parámetro de 100 caracteres, SQL Server cortaría en silencio un nombre más largo antes de validarlo.
- **Transacciones:** `SET XACT_ABORT ON` y `TRY...CATCH` revierten la transacción ante cualquier error y lo relanzan. Los procedimientos de venta bloquean las filas siempre en el mismo orden, lo que evita interbloqueos; el tema [`transacciones`](../transacciones/investigacion.md) lo explica en detalle.
- **Parámetros:** un tipo de tabla pasa el carrito entero en un solo parámetro `READONLY`, y los parámetros `OUTPUT` devuelven los ID generados.
- **Funciones:** como no pueden lanzar errores, devuelven `NULL` o `0` ante datos faltantes o inválidos. Se componen entre sí: por ejemplo, el porcentaje de descuento parte del total del pedido.
- **Instalación:** cada objeto se recrea con `DROP` y `CREATE`, porque `CREATE OR ALTER` no existe en SQL Server 2012. El script de la venta se detiene sin crear nada si faltan los objetos de los que depende, y fija `QUOTED_IDENTIFIER ON`, que SQL Server exige para escribir en una tabla con índice filtrado.

## 4. Casos concretos aplicados al sistema de ventas

- **[`abm_categorias`](abm_categorias/)**: tres procedimientos dan de alta, modifican y dan de baja categorías con un nombre obligatorio, único y de hasta 100 caracteres, y no borran una categoría que use algún libro. Resuelve RN09 y protege RN07. Resultado: 6 llamadas correctas y 9 errores provocados, todos con el número esperado.
  [`script.sql`](abm_categorias/script.sql) · [`demostracion.sql`](abm_categorias/demostracion.sql) · [`evidencias/demostracion.md`](abm_categorias/evidencias/demostracion.md)

- **[`calcular_descuento_pedido`](calcular_descuento_pedido/)**: cuatro funciones calculan el total del pedido, el porcentaje de descuento por tramo, su importe y la parte de cada renglón para los reportes. El descuento se calcula y no se almacena. Resuelve RN17 y RN30 a RN32. Resultado: 7 de 7 consultas coinciden con lo esperado.
  [`script.sql`](calcular_descuento_pedido/script.sql) · [`demostracion.sql`](calcular_descuento_pedido/demostracion.sql) · [`evidencias/demostracion.md`](calcular_descuento_pedido/evidencias/demostracion.md)

- **[`registrar_venta`](registrar_venta/)**: tres procedimientos crean el pedido con el precio vigente, inician el pago por el total con descuento y registran su resultado, apoyados en dos funciones que calculan el vencimiento de la reserva y el stock libre. Resuelve la reserva y el stock libre (RN12, RN13 y RN33 a RN37), el precio y la dirección históricos (RN26 y RN27) y los pagos (RN22 y RN24). Resultado: 53 de 53 comprobaciones; en la prueba de concurrencia, 5 de 5 casos correctos, sin interbloqueos.
  [`script.sql`](registrar_venta/script.sql) · [`demostracion.sql`](registrar_venta/demostracion.sql) · [`evidencias/demostracion.md`](registrar_venta/evidencias/demostracion.md) · [`evidencias/concurrencia.md`](registrar_venta/evidencias/concurrencia.md)
