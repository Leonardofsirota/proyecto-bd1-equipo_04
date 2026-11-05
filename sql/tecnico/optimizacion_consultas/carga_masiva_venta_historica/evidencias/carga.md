# Demostración: carga masiva de ventas históricas

[`script.sql`](../script.sql) crea `dbo.VENTA_HISTORICA`, la tabla de pruebas de las mediciones de índices, y la llena con un millón de ventas fechadas entre 2021 y 2025. La tabla es un heap, sin PK ni índices, para que la primera medición recorra la tabla entera; por eso no se usa `PAGO`, cuya PK `CLUSTERED` ya ordena las filas por su ID. Las filas salen de un único `INSERT` con un generador de seis `CROSS JOIN` de diez dígitos, sin bucles, y cada fila toma su fecha, su cliente, su vendedor, su método de pago y su importe de un hash de su número: cada carga da los mismos datos.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **8 de 8** comprobaciones correctas

## Resumen

| Comprobación                                             | Valor               | Resultado |
| -------------------------------------------------------- | ------------------- | --------- |
| Filas cargadas                                           | 1000000             | OK        |
| Primera fecha, desde el 2021-01-01                       | 2021-01-01 00:06:44 | OK        |
| Última fecha, hasta el 2025-12-31                        | 2025-12-31 23:59:17 | OK        |
| Ventas sin cliente activo con rol Cliente                | 0                   | OK        |
| Ventas sin vendedor activo con rol Vendedor              | 0                   | OK        |
| Ventas sin método de pago                                | 0                   | OK        |
| FK habilitadas y verificadas                             | 3                   | OK        |
| Filas en `sys.indexes` (un heap tiene una, `index_id` 0) | 1, `index_id` 0     | OK        |

## Datos cargados

Cliente y vendedor son usuarios con ese rol, porque en el modelo una venta es un pago aprobado y no tiene tabla propia. Solo se eligieron usuarios activos, para no fechar ventas de usuarios dados de baja: las ventas se reparten entre 434 clientes, 38 vendedores y los 3 métodos de pago.

Las ventas quedan repartidas casi por igual entre los cinco años, con unas 200.000 cada uno:

| Año  | Ventas | Importe total  |
| ---- | ------ | -------------- |
| 2021 | 199165 | 15437574914.42 |
| 2022 | 200951 | 15547004965.14 |
| 2023 | 199949 | 15523971089.50 |
| 2024 | 200905 | 15562105130.70 |
| 2025 | 199030 | 15433580356.56 |

El trimestre que buscan las mediciones, del 2024-04-01 al 2024-06-30, tiene unas 50.000 ventas, el 5 % de la tabla. Sus importes cubren el rango de la carga, de 5.000 a 150.000:

| Trimestre               | Ventas | Importe mínimo | Importe máximo |
| ----------------------- | ------ | -------------- | -------------- |
| 2024-04-01 a 2024-06-30 | 49847  | 5005.29        | 150000.00      |

La tabla ocupa 5210 páginas de 8 KB, 40,70 MB. Es lo que lee entera una búsqueda sin índice.

| Filas   | Páginas | Tamaño (MB) | Duración de la carga |
| ------- | ------- | ----------- | -------------------- |
| 1000000 | 5210    | 40.70       | 10,6 s               |

## Conclusión

El script carga el millón de ventas en unos diez segundos, con un solo `INSERT`, y todas las filas respetan las claves foráneas: cada venta tiene un cliente y un vendedor activos con su rol y un método de pago existente. La tabla sigue siendo un heap, sin ningún índice que adelante el trabajo de las mediciones. Al ejecutarlo dos veces sobre la misma base dio los mismos resultados, salvo la duración (10,6 y 10,5 s): la carga se puede repetir y los tres escenarios miden los mismos datos.
