# Demostración: búsqueda por período sin índice

[`script.sql`](../script.sql) mide la búsqueda de las ventas del segundo trimestre de 2024 en `dbo.VENTA_HISTORICA` cuando la tabla es un heap: un millón de filas guardadas sin ningún orden y sin ningún índice. La consulta trae la fecha, el cliente y el importe de las ventas con fecha desde el 2024-04-01 y anterior al 2024-07-01, y las asigna a variables para medir solo el trabajo del servidor. Se ejecuta cinco veces, cada una con la caché de datos y la de planes vacías.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba con 1.000.000 de ventas históricas · 5 corridas con caché fría

## Resumen

| Medida                  | Valor                 |
| ----------------------- | --------------------- |
| Operador principal      | Table Scan            |
| CPU (mediana)           | 94 ms                 |
| Tiempo total (mediana)  | 209 ms                |
| Lecturas lógicas        | 5209                  |
| Filas del período       | 49847                 |
| Páginas del heap        | 5210                  |
| Duración de la creación | — (no se crea índice) |

## Corridas

Las lecturas son las mismas en las cinco corridas: la consulta lee siempre las 5209 páginas de datos del heap. La página que falta para llegar a 5210 es la de asignación (IAM), que indica qué partes del archivo pertenecen a la tabla y no guarda filas. Todas las lecturas del disco son *read-ahead*: como un recorrido completo sabe de antemano qué páginas va a necesitar, SQL Server las pide en bloques grandes antes de procesarlas, y ninguna queda para leerse de a una (lecturas físicas en 0).

| Corrida | CPU (ms) | Total (ms) | Lecturas lógicas | Lecturas físicas | Read-ahead |
| ------- | -------- | ---------- | ---------------- | ---------------- | ---------- |
| 1       | 47       | 224        | 5209             | 0                | 5209       |
| 2       | 47       | 226        | 5209             | 0                | 5209       |
| 3       | 94       | 209        | 5209             | 0                | 5209       |
| 4       | 110      | 184        | 5209             | 0                | 5209       |
| 5       | 125      | 184        | 5209             | 0                | 5209       |
| Mediana | 94       | 209        | 5209             | 0                | 5209       |

El tiempo de CPU sale en múltiplos de unos 15,6 ms, el intervalo con que Windows cuenta el tiempo de procesador; por eso varía de 47 a 125 ms entre corridas que hacen el mismo trabajo. El tiempo total es más estable, entre 184 y 226 ms, y en su mayor parte es la espera de la lectura del disco.

## Plan de ejecución

El plan real tiene un solo operador:

1. **Table Scan** sobre `VENTA_HISTORICA` (`IndexKind="Heap"`), con el filtro de fecha como predicado: recorre el millón de filas y descarta las que no son del trimestre. Devolvió 49847 filas, con una estimación de 50083.

El plan completo está en [`plan.sqlplan`](plan.sqlplan) y se abre en SSMS. Es serial: SQL Server Express no genera planes paralelos (`NonParallelPlanReason="NoParallelPlansInDesktopOrExpressEdition"`). Nombra a `tmp_validacion_opt`, la base de prueba donde se ejecutó.

## Salida de STATISTICS

```text
Corrida 1
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 5209, physical reads 0, page server reads 0, read-ahead reads 5209, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 47 ms,  elapsed time = 224 ms.
Corrida 2
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 5209, physical reads 0, page server reads 0, read-ahead reads 5209, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 47 ms,  elapsed time = 226 ms.
Corrida 3
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 5209, physical reads 0, page server reads 0, read-ahead reads 5209, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 94 ms,  elapsed time = 209 ms.
Corrida 4
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 5209, physical reads 0, page server reads 0, read-ahead reads 5209, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 110 ms,  elapsed time = 184 ms.
Corrida 5
Table 'VENTA_HISTORICA'. Scan count 1, logical reads 5209, physical reads 0, page server reads 0, read-ahead reads 5209, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
 SQL Server Execution Times:
   CPU time = 125 ms,  elapsed time = 184 ms.
```

## Conclusión

Sin un índice, SQL Server no tiene forma de saber dónde están las ventas del trimestre y lee la tabla entera para encontrar el 5 % de las filas: 5209 lecturas lógicas en cada corrida. Con la caché fría, la búsqueda tarda unos 200 ms, casi todo en traer las páginas del disco, y usa alrededor de 94 ms de CPU para evaluar el filtro en el millón de filas. La tabla terminó como empezó, como heap y sin índices.
