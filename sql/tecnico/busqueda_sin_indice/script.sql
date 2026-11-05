/* ============================================================================
   Optimización de consultas - Búsqueda por período sin índice

   Mide la búsqueda de las ventas del segundo trimestre de 2024 en
   dbo.VENTA_HISTORICA cuando la tabla es un heap, sin ningún índice. Ejecuta la
   consulta 5 veces con la caché fría y muestra STATISTICS IO y TIME de cada
   corrida; al final obtiene el plan de ejecución real.

   Requisito:  dbo.VENTA_HISTORICA cargada con
               carga_masiva_venta_historica/script.sql (1.000.000 de filas).
   Uso:        ejecutar completo (F5) en un entorno de pruebas: DBCC
               DROPCLEANBUFFERS y DBCC FREEPROCCACHE vacían las cachés de toda la
               instancia y exigen el rol sysadmin. Se puede repetir.

   - La consulta asigna las columnas a variables en lugar de devolverlas: así se
     mide el trabajo del servidor y no el envío de unas 50.000 filas al cliente. El
     plan de acceso es el mismo.
   - El script empieza y termina con la tabla como heap, sin índices: los tres
     escenarios se pueden ejecutar en cualquier orden.
   ============================================================================ */

USE [sistema-venta-libros];
GO

SET NOCOUNT ON;
GO

-- ----------------------------------------------------------------------------
-- 1. Preparación
-- ----------------------------------------------------------------------------

-- SET NOEXEC ON hace que los lotes siguientes se compilen sin ejecutarse.
IF OBJECT_ID(N'dbo.VENTA_HISTORICA', N'U') IS NULL
   OR (SELECT COUNT(*) FROM dbo.VENTA_HISTORICA) <> 1000000
BEGIN
    RAISERROR(N'dbo.VENTA_HISTORICA no existe o no tiene 1.000.000 de filas: ejecutar antes carga_masiva_venta_historica/script.sql. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Índices que pueden haber quedado de otro escenario interrumpido.
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID(N'dbo.VENTA_HISTORICA') AND name = N'ix_venta_historica_fecha')
    DROP INDEX ix_venta_historica_fecha ON dbo.VENTA_HISTORICA;

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID(N'dbo.VENTA_HISTORICA') AND name = N'ix_venta_historica_fecha_cobertura')
    DROP INDEX ix_venta_historica_fecha_cobertura ON dbo.VENTA_HISTORICA;
GO

-- ----------------------------------------------------------------------------
-- 2. Índice del escenario
-- ----------------------------------------------------------------------------

-- Ninguno: la tabla queda como heap y la búsqueda debe recorrerla entera.
PRINT 'Escenario: sin índice (heap).';
GO

-- ----------------------------------------------------------------------------
-- 3. Estado de la tabla
-- ----------------------------------------------------------------------------

SELECT 'indice' AS dato, ISNULL(name, '(heap)') AS nombre, type_desc AS tipo
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.VENTA_HISTORICA')
ORDER BY index_id;

-- Páginas de 8 KB por estructura: el heap o cada índice.
SELECT
    'paginas'                   AS dato,
    ISNULL(I.name, '(heap)')    AS estructura,
    PS.used_page_count          AS paginas,
    PS.row_count                AS filas
FROM sys.dm_db_partition_stats AS PS
INNER JOIN sys.indexes AS I
    ON I.object_id = PS.object_id AND I.index_id = PS.index_id
WHERE PS.object_id = OBJECT_ID(N'dbo.VENTA_HISTORICA')
ORDER BY PS.index_id;

-- Filas que devuelve la búsqueda. No se mide.
SELECT 'filas_periodo' AS dato, COUNT(*) AS filas
FROM dbo.VENTA_HISTORICA
WHERE fecha_venta >= '20240401' AND fecha_venta < '20240701';
GO

-- ----------------------------------------------------------------------------
-- 4. Cinco corridas medidas, con la caché fría
-- ----------------------------------------------------------------------------

IF OBJECT_ID(N'tempdb..#corrida') IS NOT NULL DROP TABLE #corrida;
CREATE TABLE #corrida (n INT NOT NULL);
GO

-- GO 5 repite el lote cinco veces, en SSMS y en sqlcmd. Antes de cada corrida,
-- CHECKPOINT escribe las páginas modificadas, DROPCLEANBUFFERS vacía la caché de
-- datos y FREEPROCCACHE la de planes: la consulta lee del disco y se compila de
-- nuevo. Solo en un entorno de pruebas: afectan a toda la instancia.
-- Las STATISTICS se activan solo alrededor de la consulta, para no medir los DBCC.
INSERT INTO #corrida (n) SELECT ISNULL(MAX(n), 0) + 1 FROM #corrida;
DECLARE @corrida INT = (SELECT MAX(n) FROM #corrida);
CHECKPOINT;
DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;
DBCC FREEPROCCACHE WITH NO_INFOMSGS;
PRINT 'Corrida ' + CAST(@corrida AS VARCHAR(10));
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
DECLARE @fecha DATETIME, @cliente INT, @importe DECIMAL(18, 2);
SELECT @fecha = fecha_venta, @cliente = cliente_id, @importe = importe_total
FROM dbo.VENTA_HISTORICA
WHERE fecha_venta >= '20240401' AND fecha_venta < '20240701';
SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;
GO 5

DROP TABLE #corrida;
GO

-- ----------------------------------------------------------------------------
-- 5. Plan de ejecución real
-- ----------------------------------------------------------------------------

-- Con la caché caliente y fuera de la medición. SSMS muestra el plan como un enlace
-- que se puede guardar como .sqlplan.
PRINT 'Plan de ejecución real';
SET STATISTICS XML ON;
DECLARE @fecha DATETIME, @cliente INT, @importe DECIMAL(18, 2);
SELECT @fecha = fecha_venta, @cliente = cliente_id, @importe = importe_total
FROM dbo.VENTA_HISTORICA
WHERE fecha_venta >= '20240401' AND fecha_venta < '20240701';
SET STATISTICS XML OFF;
GO

-- ----------------------------------------------------------------------------
-- 6. Cierre
-- ----------------------------------------------------------------------------

-- No se creó ningún índice: solo se comprueba que la tabla siga como heap.
SELECT
    'cierre'                                                             AS dato,
    COUNT(*)                                                             AS filas_sys_indexes,
    MAX(index_id)                                                        AS index_id,
    CASE WHEN COUNT(*) = 1 AND MAX(index_id) = 0 THEN 'OK' ELSE 'FALLO' END AS resultado
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.VENTA_HISTORICA');
GO
