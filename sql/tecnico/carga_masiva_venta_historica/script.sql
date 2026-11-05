/* ============================================================================
   Optimización de consultas - Carga masiva de ventas históricas

   Crea dbo.VENTA_HISTORICA, una tabla de pruebas para medir búsquedas por
   período, y la llena con 1.000.000 de ventas fechadas entre el 2021-01-01 y el
   2025-12-31. Al final verifica la carga.

   Requisito:  la base con sql/ddl/sistema-venta-libros.sql y
               sql/dml/datos_prueba.sql cargados.
   Uso:        ejecutar completo (F5). Se puede repetir: borra la tabla, la vuelve
               a crear y carga siempre los mismos datos.

   - La tabla se crea como heap, sin PK ni índices: así la primera medición recorre
     la tabla entera. No se usa PAGO porque su PK es CLUSTERED y ya ordena la tabla.
   - En el modelo, una venta es un PAGO en estado Aprobado, y cliente y vendedor son
     usuarios con rol Cliente o Vendedor: por eso las dos columnas son FK a USUARIO.
     Las FK se declaran porque, a diferencia de una PK, no crean índices.
   - Los valores salen de HASHBYTES sobre el número de fila y no de NEWID(): cada
     carga da los mismos datos y las mediciones se pueden repetir.
   ============================================================================ */

USE [sistema-venta-libros];
GO

SET NOCOUNT ON;
GO

-- ----------------------------------------------------------------------------
-- 1. Tabla de pruebas
-- ----------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.VENTA_HISTORICA', N'U') IS NOT NULL
    DROP TABLE dbo.VENTA_HISTORICA;
GO

-- Tipos tomados de PAGO y USUARIO. venta_historica_id no es PK: una PK, incluso
-- NONCLUSTERED, crea un índice.
CREATE TABLE dbo.VENTA_HISTORICA (
    venta_historica_id INT IDENTITY(1,1) NOT NULL,
    fecha_venta        DATETIME          NOT NULL,
    cliente_id         INT               NOT NULL,
    vendedor_id        INT               NOT NULL,
    pago_metodo_id     INT               NOT NULL,
    importe_total      DECIMAL(18, 2)    NOT NULL,
    CONSTRAINT chk_venta_historica_importe    CHECK (importe_total > 0),
    CONSTRAINT fk_venta_historica_cliente     FOREIGN KEY (cliente_id)     REFERENCES dbo.USUARIO (usuario_id),
    CONSTRAINT fk_venta_historica_vendedor    FOREIGN KEY (vendedor_id)    REFERENCES dbo.USUARIO (usuario_id),
    CONSTRAINT fk_venta_historica_pago_metodo FOREIGN KEY (pago_metodo_id) REFERENCES dbo.PAGO_METODO (pago_metodo_id)
);
GO

-- ----------------------------------------------------------------------------
-- 2. Carga masiva
-- ----------------------------------------------------------------------------

DECLARE @Filas INT = 1000000;
-- Seis copias de una tabla de 10 dígitos combinadas con CROSS JOIN: 10^6 filas.
DECLARE @CapacidadGenerador INT = 1000000;
DECLARE @Inicio DATETIME = '20210101';
DECLARE @Clientes INT, @Vendedores INT, @Metodos INT;
DECLARE @Desde DATETIME2(3), @Hasta DATETIME2(3), @Insertadas INT;

IF @Filas > @CapacidadGenerador
    THROW 50501, N'El generador de filas no alcanza para la cantidad pedida.', 1;

-- Catálogos numerados de 1 a N, para elegir un valor por posición. Solo usuarios
-- activos: no se fechan ventas de usuarios ya dados de baja. Los roles se buscan por
-- nombre, nunca por ID.
IF OBJECT_ID(N'tempdb..#clientes') IS NOT NULL DROP TABLE #clientes;
IF OBJECT_ID(N'tempdb..#vendedores') IS NOT NULL DROP TABLE #vendedores;
IF OBJECT_ID(N'tempdb..#metodos') IS NOT NULL DROP TABLE #metodos;

CREATE TABLE #clientes   (fila INT PRIMARY KEY, usuario_id INT NOT NULL);
CREATE TABLE #vendedores (fila INT PRIMARY KEY, usuario_id INT NOT NULL);
CREATE TABLE #metodos    (fila INT PRIMARY KEY, pago_metodo_id INT NOT NULL);

INSERT INTO #clientes (fila, usuario_id)
SELECT ROW_NUMBER() OVER (ORDER BY U.usuario_id), U.usuario_id
FROM dbo.USUARIO AS U
INNER JOIN dbo.USUARIO_ROL AS R ON R.usuario_rol_id = U.usuario_rol_id
WHERE R.nombre = 'Cliente'
  AND U.fecha_eliminacion IS NULL;
SET @Clientes = @@ROWCOUNT;

INSERT INTO #vendedores (fila, usuario_id)
SELECT ROW_NUMBER() OVER (ORDER BY U.usuario_id), U.usuario_id
FROM dbo.USUARIO AS U
INNER JOIN dbo.USUARIO_ROL AS R ON R.usuario_rol_id = U.usuario_rol_id
WHERE R.nombre = 'Vendedor'
  AND U.fecha_eliminacion IS NULL;
SET @Vendedores = @@ROWCOUNT;

INSERT INTO #metodos (fila, pago_metodo_id)
SELECT ROW_NUMBER() OVER (ORDER BY pago_metodo_id), pago_metodo_id
FROM dbo.PAGO_METODO;
SET @Metodos = @@ROWCOUNT;

IF @Clientes = 0 OR @Vendedores = 0 OR @Metodos = 0
    THROW 50502, N'Faltan clientes activos, vendedores activos o métodos de pago: cargar antes sql/dml/datos_prueba.sql.', 1;

SET @Desde = SYSDATETIME();

-- Un solo INSERT, sin bucles. TABLOCK sobre un heap permite el registro mínimo en
-- el modelo de recuperación SIMPLE.
-- Cada atributo toma 4 bytes distintos del hash. El % va antes que ABS: ABS del INT
-- mínimo desborda, y el resto de una división por m nunca llega a ese valor.
WITH Digitos (d) AS (
    SELECT d FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9)) AS V (d)
),
Numeros (n) AS (
    SELECT D1.d + 10 * D2.d + 100 * D3.d + 1000 * D4.d + 10000 * D5.d + 100000 * D6.d + 1
    FROM Digitos AS D1
    CROSS JOIN Digitos AS D2
    CROSS JOIN Digitos AS D3
    CROSS JOIN Digitos AS D4
    CROSS JOIN Digitos AS D5
    CROSS JOIN Digitos AS D6
)
INSERT INTO dbo.VENTA_HISTORICA WITH (TABLOCK)
    (fecha_venta, cliente_id, vendedor_id, pago_metodo_id, importe_total)
SELECT
    DATEADD(SECOND, A.segundo, DATEADD(DAY, A.dia, @Inicio)),
    C.usuario_id,
    V.usuario_id,
    M.pago_metodo_id,
    -- Entre 5.000,00 y 150.000,00.
    CAST(5000 + A.centavos / 100.0 AS DECIMAL(18, 2))
FROM Numeros AS N
CROSS APPLY (SELECT HASHBYTES('SHA2_256', CAST(N.n AS VARCHAR(10))) AS h) AS H
CROSS APPLY (
    SELECT
        -- 1826 días: del 2021-01-01 al 2025-12-31, con el 29 de febrero de 2024.
        ABS(CAST(SUBSTRING(H.h,  1, 4) AS INT) % 1826)        AS dia,
        ABS(CAST(SUBSTRING(H.h,  5, 4) AS INT) % 86400)       AS segundo,
        ABS(CAST(SUBSTRING(H.h,  9, 4) AS INT) % @Clientes)   AS cliente,
        ABS(CAST(SUBSTRING(H.h, 13, 4) AS INT) % @Vendedores) AS vendedor,
        ABS(CAST(SUBSTRING(H.h, 17, 4) AS INT) % @Metodos)    AS metodo,
        ABS(CAST(SUBSTRING(H.h, 21, 4) AS INT) % 14500001)    AS centavos
) AS A
INNER JOIN #clientes   AS C ON C.fila = 1 + A.cliente
INNER JOIN #vendedores AS V ON V.fila = 1 + A.vendedor
INNER JOIN #metodos    AS M ON M.fila = 1 + A.metodo
WHERE N.n <= @Filas;

SET @Insertadas = @@ROWCOUNT;
SET @Hasta = SYSDATETIME();

SELECT
    @Insertadas                           AS filas_insertadas,
    @Clientes                             AS clientes_activos,
    @Vendedores                           AS vendedores_activos,
    @Metodos                              AS metodos_pago,
    DATEDIFF(MILLISECOND, @Desde, @Hasta) AS duracion_ms;

DROP TABLE #clientes;
DROP TABLE #vendedores;
DROP TABLE #metodos;
GO

-- ----------------------------------------------------------------------------
-- 3. Verificaciones
-- ----------------------------------------------------------------------------

DECLARE @Comprobaciones TABLE (
    orden        INT          NOT NULL,
    comprobacion VARCHAR(100) NOT NULL,
    valor        VARCHAR(30)  NOT NULL,
    resultado    VARCHAR(5)   NOT NULL
);
DECLARE @Total INT, @Primera DATETIME, @Ultima DATETIME;
DECLARE @SinCliente INT, @SinVendedor INT, @SinMetodo INT, @FkConfiables INT;
DECLARE @Indices INT, @IndiceId INT;

SELECT @Total = COUNT(*), @Primera = MIN(fecha_venta), @Ultima = MAX(fecha_venta)
FROM dbo.VENTA_HISTORICA;

-- Cada venta debe tener un cliente y un vendedor activos con su rol.
SELECT @SinCliente = COUNT(*)
FROM dbo.VENTA_HISTORICA AS VH
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.USUARIO AS U
    INNER JOIN dbo.USUARIO_ROL AS R ON R.usuario_rol_id = U.usuario_rol_id
    WHERE U.usuario_id = VH.cliente_id
      AND R.nombre = 'Cliente'
      AND U.fecha_eliminacion IS NULL
);

SELECT @SinVendedor = COUNT(*)
FROM dbo.VENTA_HISTORICA AS VH
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.USUARIO AS U
    INNER JOIN dbo.USUARIO_ROL AS R ON R.usuario_rol_id = U.usuario_rol_id
    WHERE U.usuario_id = VH.vendedor_id
      AND R.nombre = 'Vendedor'
      AND U.fecha_eliminacion IS NULL
);

SELECT @SinMetodo = COUNT(*)
FROM dbo.VENTA_HISTORICA AS VH
WHERE NOT EXISTS (SELECT 1 FROM dbo.PAGO_METODO AS PM WHERE PM.pago_metodo_id = VH.pago_metodo_id);

-- Las FK se comprobaron durante el INSERT: ninguna quedó deshabilitada ni sin verificar.
SELECT @FkConfiables = COUNT(*)
FROM sys.foreign_keys
WHERE parent_object_id = OBJECT_ID(N'dbo.VENTA_HISTORICA')
  AND is_disabled = 0
  AND is_not_trusted = 0;

-- Un heap tiene una sola fila en sys.indexes, con index_id = 0.
SELECT @Indices = COUNT(*), @IndiceId = MAX(index_id)
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'dbo.VENTA_HISTORICA');

INSERT INTO @Comprobaciones (orden, comprobacion, valor, resultado)
VALUES
    (1, 'Filas cargadas', CAST(@Total AS VARCHAR(30)),
        CASE WHEN @Total = 1000000 THEN 'OK' ELSE 'FALLO' END),
    (2, 'Primera fecha, desde el 2021-01-01', CONVERT(VARCHAR(19), @Primera, 120),
        CASE WHEN @Primera >= '20210101' AND @Primera < '20220101' THEN 'OK' ELSE 'FALLO' END),
    (3, 'Última fecha, hasta el 2025-12-31', CONVERT(VARCHAR(19), @Ultima, 120),
        CASE WHEN @Ultima >= '20250101' AND @Ultima < '20260101' THEN 'OK' ELSE 'FALLO' END),
    (4, 'Ventas sin cliente activo con rol Cliente', CAST(@SinCliente AS VARCHAR(30)),
        CASE WHEN @SinCliente = 0 THEN 'OK' ELSE 'FALLO' END),
    (5, 'Ventas sin vendedor activo con rol Vendedor', CAST(@SinVendedor AS VARCHAR(30)),
        CASE WHEN @SinVendedor = 0 THEN 'OK' ELSE 'FALLO' END),
    (6, 'Ventas sin método de pago', CAST(@SinMetodo AS VARCHAR(30)),
        CASE WHEN @SinMetodo = 0 THEN 'OK' ELSE 'FALLO' END),
    (7, 'FK habilitadas y verificadas', CAST(@FkConfiables AS VARCHAR(30)),
        CASE WHEN @FkConfiables = 3 THEN 'OK' ELSE 'FALLO' END),
    (8, 'Filas en sys.indexes (heap: una, index_id 0)',
        CAST(@Indices AS VARCHAR(10)) + ', index_id ' + CAST(@IndiceId AS VARCHAR(10)),
        CASE WHEN @Indices = 1 AND @IndiceId = 0 THEN 'OK' ELSE 'FALLO' END);

SELECT comprobacion, valor, resultado
FROM @Comprobaciones
ORDER BY orden;

SELECT
    COUNT(*)                                          AS comprobaciones,
    SUM(CASE WHEN resultado = 'OK' THEN 1 ELSE 0 END) AS correctas,
    SUM(CASE WHEN resultado = 'OK' THEN 0 ELSE 1 END) AS fallidas
FROM @Comprobaciones;

-- Información, no se compara: ventas por año (cerca de 200.000 cada uno) y del
-- trimestre que buscan las mediciones (cerca de 50.000).
SELECT YEAR(fecha_venta) AS anio, COUNT(*) AS ventas, SUM(importe_total) AS importe
FROM dbo.VENTA_HISTORICA
GROUP BY YEAR(fecha_venta)
ORDER BY anio;

SELECT
    '2024-04-01 a 2024-06-30' AS trimestre,
    COUNT(*)                  AS ventas,
    MIN(importe_total)        AS importe_minimo,
    MAX(importe_total)        AS importe_maximo
FROM dbo.VENTA_HISTORICA
WHERE fecha_venta >= '20240401'
  AND fecha_venta <  '20240701';

-- Tamaño de la tabla: páginas de 8 KB en uso.
SELECT
    SUM(row_count)                                            AS filas,
    SUM(used_page_count)                                      AS paginas,
    CAST(SUM(used_page_count) * 8 / 1024.0 AS DECIMAL(10, 2)) AS tamanio_mb
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'dbo.VENTA_HISTORICA');
GO
