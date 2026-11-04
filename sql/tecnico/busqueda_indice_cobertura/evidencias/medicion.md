# Demostración: búsqueda por período con índice de cobertura sobre la fecha

[`script.sql`](../script.sql) crea en `dbo.VENTA_HISTORICA` un índice no agrupado sobre `fecha_venta` que incluye `cliente_id` e `importe_total`, mide la misma búsqueda de las ventas del segundo trimestre de 2024 y borra el índice al terminar. La tabla sigue siendo un heap y el índice es una estructura aparte, ordenada por fecha, que guarda las tres columnas de la consulta: la cubre sin volver a la tabla. La consulta se ejecuta cinco veces, cada una con la caché de datos y la de planes vacías.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba con 1.000.000 de ventas históricas · 5 corridas con caché fría

## Resumen

| Medida                  | Valor                             |
| ----------------------- | --------------------------------- |
| Operador principal      | Index Seek, sin *Lookup*          |
| CPU (mediana)           | 16 ms                             |
| Tiempo total (mediana)  | 10 ms                             |
| Lecturas lógicas        | 220                               |
| Filas del período       | 49847                             |
| Páginas del índice      | 4346, además de las 5210 del heap |
| Duración de la creación | 517 ms                            |

El índice no reemplaza a la tabla, se suma a ella: ocupa 4346 páginas, 83 % del tamaño del heap. Es más chico que la tabla porque cada fila del índice lleva solo la fecha, las dos columnas incluidas y la dirección de la fila en el heap (RID), no el vendedor ni el método de pago.

## Corridas

Las lecturas no cambian entre corridas. La búsqueda baja por el árbol del índice hasta la primera venta del 2024-04-01 y recorre sus páginas hoja hasta el final del trimestre: unas 217 páginas más las del camino desde la raíz. Las 3 lecturas físicas son esas páginas del camino, que se leen de a una; las del rango se piden por adelantado (*read-ahead*).

| Corrida | CPU (ms) | Total (ms) | Lecturas lógicas | Lecturas físicas | Read-ahead |
| ------- | -------- | ---------- | ---------------- | ---------------- | ---------- |
| 1       | 15       | 24         | 220              | 3                | 217        |
| 2       | 32       | 22         | 220              | 3                | 217        |
| 3       | 0        | 10         | 220              | 3                | 217        |
| 4       | 16       | 9          | 220              | 3                | 217        |
| 5       | 16       | 9          | 220              | 3                | 217        |
| Mediana | 16       | 10         | 220              | 3                | 217        |

El tiempo de CPU sale en múltiplos de unos 15,6 ms, el intervalo con que Windows cuenta el tiempo de procesador. Un trabajo tan corto queda en 0, uno o dos intervalos según cuándo empiece, y por eso la mediana de CPU (16 ms) puede superar a la del tiempo total (10 ms). Las dos primeras corridas tardaron más que las otras tres, que se estabilizaron en unos 10 ms.

**Repetición.** En la primera ejecución del script, la corrida 2 tardó 70 ms contra 9 ms de las dos últimas, y se repitió el escenario completo una vez, como prevé el procedimiento. Las tablas muestran la repetición. La primera ejecución dio las mismas lecturas, una mediana de 0 ms de CPU y de 16 ms de tiempo total, y 524 ms para crear el índice.

## Plan de ejecución

El plan real tiene un solo operador:

1. **Index Seek** sobre `ix_venta_historica_fecha_cobertura`, con el rango de fechas como predicado de búsqueda (`SeekPredicates`) y recorrido hacia adelante en el orden del índice. Devolvió 49847 filas, con una estimación de 49878.

No aparece ningún **RID Lookup** ni **Key Lookup**: la consulta no vuelve al heap a buscar ninguna fila, porque la fecha, el cliente y el importe ya están en el índice. El plan completo está en [`plan.sqlplan`](plan.sqlplan) y se abre en SSMS. Es serial: SQL Server Express no genera planes paralelos. Nombra a `tmp_validacion_opt`, la base de prueba donde se ejecutó.

## Salida de STATISTICS

```text
Corrida 1
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 220, physical reads 3, page server reads 0, read-ahead reads 217, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 15 ms,  elapsed time = 24 ms.
Corrida 2
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 220, physical reads 3, page server reads 0, read-ahead reads 217, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 32 ms,  elapsed time = 22 ms.
Corrida 3
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 220, physical reads 3, page server reads 0, read-ahead reads 217, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 0 ms,  elapsed time = 10 ms.
Corrida 4
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 220, physical reads 3, page server reads 0, read-ahead reads 217, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 16 ms,  elapsed time = 9 ms.
Corrida 5
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 220, physical reads 3, page server reads 0, read-ahead reads 217, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 16 ms,  elapsed time = 9 ms.
```

## Conclusión

El índice de cobertura resuelve la búsqueda por sí solo: va directo al principio del trimestre, lee 220 páginas en cada corrida y no toca la tabla. Con la caché fría tarda unos 10 ms, y el tiempo de CPU queda por debajo de lo que Windows puede medir con precisión. A cambio, el índice ocupa 4346 páginas más, que se mantienen en cada alta o cambio de una venta, y tardó 517 ms en crearse. Al borrarlo, la tabla volvió a quedar como heap sin índices.
