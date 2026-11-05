# Demostración: búsqueda por período con índice agrupado sobre la fecha

[`script.sql`](../script.sql) crea un índice agrupado sobre `fecha_venta` en `dbo.VENTA_HISTORICA`, mide la misma búsqueda de las ventas del segundo trimestre de 2024 y borra el índice al terminar. Un índice agrupado ordena físicamente la tabla por su clave: su nivel hoja son las propias filas, con todas las columnas, así que las ventas del trimestre quedan juntas. La consulta se ejecuta cinco veces, cada una con la caché de datos y la de planes vacías.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba con 1.000.000 de ventas históricas · 5 corridas con caché fría

## Resumen

| Medida                  | Valor                |
| ----------------------- | -------------------- |
| Operador principal      | Clustered Index Seek |
| CPU (mediana)           | 15 ms                |
| Tiempo total (mediana)  | 11 ms                |
| Lecturas lógicas        | 264                  |
| Filas del período       | 49847                |
| Páginas del índice      | 5222                 |
| Duración de la creación | 692 ms               |

El índice ocupa 12 páginas más que el heap de 5210. Son los niveles superiores del árbol, que llevan desde la raíz hasta cada página hoja, y el *uniquifier*: como el índice no es único, SQL Server agrega un valor interno de 4 bytes a las filas que repiten fecha y hora de otra. Crear el índice reescribe la tabla completa en el orden de la fecha.

## Corridas

Las lecturas no cambian entre corridas. La búsqueda baja por el árbol hasta la primera venta del 2024-04-01 y recorre las páginas hoja hasta la última del trimestre: unas 260 páginas, el 5 % de la tabla, más las del camino desde la raíz. Las 2 lecturas físicas son esas páginas del camino, que se leen de a una porque cada una indica cuál sigue; las del rango se piden por adelantado (*read-ahead*).

| Corrida | CPU (ms) | Total (ms) | Lecturas lógicas | Lecturas físicas | Read-ahead |
| ------- | -------- | ---------- | ---------------- | ---------------- | ---------- |
| 1       | 15       | 27         | 264              | 2                | 261        |
| 2       | 16       | 24         | 264              | 2                | 261        |
| 3       | 0        | 11         | 264              | 2                | 261        |
| 4       | 0        | 9          | 264              | 2                | 261        |
| 5       | 16       | 9          | 264              | 2                | 261        |
| Mediana | 15       | 11         | 264              | 2                | 261        |

El tiempo de CPU sale en múltiplos de unos 15,6 ms, el intervalo con que Windows cuenta el tiempo de procesador. Un trabajo tan corto queda en 0 o en un intervalo según cuándo empiece, y por eso la mediana de CPU (15 ms) puede superar a la del tiempo total (11 ms). Las dos primeras corridas tardaron más que las otras tres, que se estabilizaron en unos 10 ms.

**Repetición.** En la primera ejecución del script, la corrida 1 tardó 42 ms contra 9 ms de las tres últimas, y se repitió el escenario completo una vez, como prevé el procedimiento. Las tablas muestran la repetición. La primera ejecución dio las mismas lecturas, una mediana de 0 ms de CPU y de 9 ms de tiempo total, y 1193 ms para crear el índice.

## Plan de ejecución

El plan real tiene un solo operador:

1. **Clustered Index Seek** sobre `ix_venta_historica_fecha`, con el rango de fechas como predicado de búsqueda (`SeekPredicates`) y recorrido hacia adelante en el orden del índice. Devolvió 49847 filas, con una estimación de 49878.

El plan completo está en [`plan.sqlplan`](plan.sqlplan) y se abre en SSMS. Es serial: SQL Server Express no genera planes paralelos. Nombra a `tmp_validacion_opt`, la base de prueba donde se ejecutó.

## Salida de STATISTICS

```text
Corrida 1
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 264, physical reads 2, page server reads 0, read-ahead reads 261, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 15 ms,  elapsed time = 27 ms.
Corrida 2
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 264, physical reads 2, page server reads 0, read-ahead reads 261, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 16 ms,  elapsed time = 24 ms.
Corrida 3
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 264, physical reads 2, page server reads 0, read-ahead reads 261, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 0 ms,  elapsed time = 11 ms.
Corrida 4
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 264, physical reads 2, page server reads 0, read-ahead reads 261, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 0 ms,  elapsed time = 9 ms.
Corrida 5
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 264, physical reads 2, page server reads 0, read-ahead reads 261, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 16 ms,  elapsed time = 9 ms.
```

## Conclusión

Con la tabla ordenada por fecha, la consulta va directo al principio del trimestre y lee solo las páginas que contienen sus ventas: 264 lecturas lógicas en cada corrida. Con la caché fría tarda unos 10 ms, y el tiempo de CPU queda por debajo de lo que Windows puede medir con precisión. A cambio, el índice tardó 692 ms en crearse, porque reordena la tabla completa. Al borrarlo, la tabla volvió a ser un heap sin índices.
