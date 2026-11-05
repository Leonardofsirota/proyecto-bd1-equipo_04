# Optimización de consultas - Etapa 5

## 1. Definición y objetivo

**Optimizar una consulta** es lograr que SQL Server la resuelva leyendo la menor cantidad posible de datos. La herramienta principal es el **índice**: una estructura de árbol balanceado (*B-tree*) ordenada por una o más columnas, la **clave**. La raíz y los niveles intermedios guían la búsqueda y el nivel hoja guarda las entradas en el orden de la clave, de modo que para encontrar un valor o un rango basta bajar por el árbol en lugar de revisar toda la tabla.

Una tabla sin índice agrupado es un **heap**: sus filas se guardan en páginas de 8 KB sin ningún orden. Para encontrar las filas que cumplen un filtro, SQL Server tiene que leer todas las páginas.

Antes de ejecutar una consulta, el **optimizador** arma un **plan de ejecución**: decide qué estructura leer, si la recorre entera (*scan*) o va directo a un rango (*seek*), y cómo combinar los resultados. Para elegir usa las estadísticas de distribución de los datos y estima cuántas filas devuelve cada paso.

El objetivo es reducir las páginas que se leen para responder una consulta. Cada página leída cuesta memoria, CPU y, si no está en caché, una lectura del disco.

## 2. Ventajas y aplicaciones

SQL Server ofrece tres variantes que importan para una búsqueda por período:

| Tipo        | Qué es                                                                                                                                                | Aplicación típica                                                   |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Agrupado    | Los datos mismos, ordenados por la clave. Su nivel hoja son las filas completas. Hay uno solo por tabla                                               | Búsquedas por rango sobre la columna que más se filtra o se ordena  |
| No agrupado | Una estructura aparte, con la clave y un puntero a la fila: la dirección física (RID) en un heap o la clave agrupada en una tabla con índice agrupado | Búsquedas selectivas por columnas que no son la clave agrupada      |
| Cobertura   | Un no agrupado que suma columnas con `INCLUDE` en su nivel hoja, de modo que contiene todo lo que la consulta lee                                     | Consultas frecuentes que leen pocas columnas: no vuelven a la tabla |

Ventajas:

- **Búsqueda en lugar de recorrido:** con un índice sobre la columna del filtro, el plan cambia un *scan* de toda la tabla por un *seek* al principio del rango, y lee solo las páginas que contienen las filas buscadas.
- **Menos lecturas, menos tiempo y menos CPU:** cada página que no se lee es una página que no se trae del disco, no ocupa la caché ni se evalúa contra el filtro.
- **Sin vuelta a la tabla:** un índice de cobertura evita el *Lookup*, el salto a la tabla que hace un no agrupado por cada fila para traer las columnas que no tiene.

Costos:

- **Espacio:** un índice agrupado reordena la tabla y apenas la agranda; un no agrupado es una copia parcial que se suma a ella. En la prueba, el agrupado ocupa 5222 páginas contra las 5210 del heap, y el de cobertura agrega 4346 páginas a la tabla.
- **Escrituras más lentas:** cada `INSERT`, `UPDATE` o `DELETE` actualiza también cada índice de la tabla que contenga las columnas afectadas. Cuantos más índices, más trabajo por escritura y más bloqueos.
- **Creación y mantenimiento:** crear el índice recorre y ordena la tabla completa. Con el tiempo, las inserciones fuera de orden fragmentan las páginas, y el índice se reorganiza o se reconstruye (`ALTER INDEX ... REORGANIZE | REBUILD`).

Por eso conviene tener pocos índices, pensados para las consultas que se ejecutan con más frecuencia, y no uno por columna.

## 3. Implementación en SQL Server Express

SQL Server Express tiene el mismo motor de índices y el mismo T-SQL que las demás ediciones. Todas las evidencias se obtuvieron en SQL Server 2025 Express Edition.

```sql
-- Índices de los dos escenarios, resumido de busqueda_indice_agrupado y busqueda_indice_cobertura
CREATE CLUSTERED INDEX ix_venta_historica_fecha
    ON dbo.VENTA_HISTORICA (fecha_venta);
DROP INDEX ix_venta_historica_fecha ON dbo.VENTA_HISTORICA;

CREATE NONCLUSTERED INDEX ix_venta_historica_fecha_cobertura
    ON dbo.VENTA_HISTORICA (fecha_venta)
    INCLUDE (cliente_id, importe_total);    -- columnas que lee la consulta

-- Medición, repetida 5 veces con la caché fría
CHECKPOINT;
DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS;
DBCC FREEPROCCACHE WITH NO_INFOMSGS;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
SELECT @fecha = fecha_venta, @cliente = cliente_id, @importe = importe_total
FROM dbo.VENTA_HISTORICA
WHERE fecha_venta >= '20240401' AND fecha_venta < '20240701';
```

Recursos que usan los scripts del proyecto:

- **`CREATE [CLUSTERED | NONCLUSTERED] INDEX ... INCLUDE (...)` y `DROP INDEX`:** crean y borran los índices de cada escenario. Una `PRIMARY KEY` crea por defecto un índice agrupado, y por eso `PAGO` no sirve como tabla de pruebas: sus filas ya están ordenadas por su ID.
- **`SET STATISTICS IO`:** informa por tabla las lecturas lógicas (páginas leídas de la caché), las físicas y las *read-ahead* (páginas pedidas al disco por adelantado). Las lecturas lógicas son la medida más estable: no dependen de la caché ni de la carga de la máquina.
- **`SET STATISTICS TIME`:** informa el tiempo de CPU y el tiempo total de cada sentencia. La consulta asigna las columnas a variables, para medir el trabajo del servidor y no el envío de 50.000 filas al cliente.
- **Plan real:** `SET STATISTICS XML ON` devuelve el plan con las filas reales de cada operador, y SSMS lo muestra con «Incluir plan de ejecución real». Cada escenario guarda el suyo como `.sqlplan`.
- **Caché fría:** `CHECKPOINT` escribe las páginas modificadas, `DBCC DROPCLEANBUFFERS` vacía la caché de datos y `DBCC FREEPROCCACHE`, la de planes. Así cada corrida lee del disco y compila de nuevo. Exigen permisos de servidor (`sysadmin` en la validación) y afectan a toda la instancia: son solo para entornos de prueba.
- **Límites de Express que influyen:** la caché de datos llega a unos 1,4 GB, cada base a 10 GB (50 GB desde SQL Server 2025) y el motor usa hasta 4 núcleos. La tabla de prueba ocupa unos 41 MB, así que entra cómoda en la caché. Express nunca genera planes paralelos, y los planes guardados lo registran.

## 4. Casos concretos aplicados al sistema de ventas

El modelo no tiene una tabla de ventas: una venta es un `PAGO` en estado `Aprobado`, y el cliente y el vendedor son usuarios con ese rol. La tabla de pruebas `dbo.VENTA_HISTORICA` sigue ese criterio: guarda la fecha, el cliente, el vendedor, el método de pago y el importe, con FK a `USUARIO` y a `PAGO_METODO`. Es un heap sin PK, porque una PK crea un índice; las FK sí se declaran, porque no lo crean.

Los tres escenarios miden la misma consulta: las ventas del segundo trimestre de 2024, con su fecha, su cliente y su importe. Cada uno la ejecuta cinco veces con la caché fría y anota la mediana.

- **[`carga_masiva_venta_historica`](carga_masiva_venta_historica/)**: crea la tabla y la llena con un millón de ventas entre 2021 y 2025, con un único `INSERT` que genera las filas con seis `CROSS JOIN` de diez dígitos, sin bucles. Cada fila toma su fecha, sus FK y su importe de un hash de su número, así que cada carga da los mismos datos. Resultado: 8 de 8 comprobaciones correctas, 1.000.000 de filas en unos 10 s y 49847 ventas en el trimestre de prueba.
  [`script.sql`](carga_masiva_venta_historica/script.sql) · [`evidencias/carga.md`](carga_masiva_venta_historica/evidencias/carga.md)

- **[`busqueda_sin_indice`](busqueda_sin_indice/)**: mide la consulta sobre el heap. El plan es un **Table Scan** que recorre el millón de filas para quedarse con el 5 %.
  [`script.sql`](busqueda_sin_indice/script.sql) · [`evidencias/medicion.md`](busqueda_sin_indice/evidencias/medicion.md) · [`evidencias/plan.sqlplan`](busqueda_sin_indice/evidencias/plan.sqlplan)

- **[`busqueda_indice_agrupado`](busqueda_indice_agrupado/)**: crea un índice agrupado sobre la fecha, mide la consulta y lo borra. El plan es un **Clustered Index Seek** sobre el rango del trimestre.
  [`script.sql`](busqueda_indice_agrupado/script.sql) · [`evidencias/medicion.md`](busqueda_indice_agrupado/evidencias/medicion.md) · [`evidencias/plan.sqlplan`](busqueda_indice_agrupado/evidencias/plan.sqlplan)

- **[`busqueda_indice_cobertura`](busqueda_indice_cobertura/)**: crea un índice no agrupado sobre la fecha que incluye el cliente y el importe, mide la consulta y lo borra. El plan es un **Index Seek** sin *RID Lookup* ni *Key Lookup*: la consulta no vuelve al heap.
  [`script.sql`](busqueda_indice_cobertura/script.sql) · [`evidencias/medicion.md`](busqueda_indice_cobertura/evidencias/medicion.md) · [`evidencias/plan.sqlplan`](busqueda_indice_cobertura/evidencias/plan.sqlplan)

### Por qué el «agrupado con columnas incluidas» es no agrupado

La consigna pide un índice agrupado con columnas incluidas, pero se implementa como no agrupado. El nivel hoja de un índice agrupado ya es la fila completa, con todas sus columnas: no hay nada que incluir, y SQL Server no admite `INCLUDE` en un `CLUSTERED`. La cobertura se logra con un no agrupado cuya clave es la fecha y que incluye las columnas que la consulta selecciona.

### Comparación

| Escenario  | Operador principal   | CPU (ms) | Tiempo total (ms) | Lecturas lógicas | Páginas de la estructura |
| ---------- | -------------------- | -------- | ----------------- | ---------------- | ------------------------ |
| Sin índice | Table Scan           | 94       | 209               | 5209             | 5210 (heap)              |
| Agrupado   | Clustered Index Seek | 15       | 11                | 264              | 5222 (reemplaza al heap) |
| Cobertura  | Index Seek           | 16       | 10                | 220              | 4346 (además del heap)   |

### Conclusiones

- **Las lecturas bajan unas 20 veces.** El heap obliga a leer sus 5209 páginas de datos. El índice agrupado lee 264, 20 veces menos, y el de cobertura 220, 24 veces menos. Las lecturas son idénticas en las cinco corridas de cada escenario: son la medida más confiable de la comparación.
- **El tiempo total baja en la misma proporción.** De 209 ms a 11 y 10 ms, unas 20 veces. Sin índice, casi todo el tiempo es traer del disco la tabla entera; con índice, solo el rango del trimestre.
- **La cobertura lee menos que el agrupado** porque sus filas son más angostas. Una página hoja del agrupado guarda filas completas, con las seis columnas; una del índice de cobertura guarda solo la fecha, las dos columnas incluidas y el RID. Entran más filas por página y el mismo trimestre ocupa 217 páginas en lugar de 261.
- **Entre los dos índices, el tiempo no marca diferencia.** 11 y 10 ms están dentro de la variación entre corridas, que en ambos escenarios fue de 9 a 27 ms. Lo que los distingue son las lecturas.
- **La CPU con índice supera al tiempo total.** Windows cuenta la CPU en intervalos de unos 15,6 ms, así que un trabajo de 10 ms queda en 0, 15 o 16 ms según cuándo empiece. Las medianas de 15 y 16 ms no son más precisas que eso; lo que sí se ve es la caída desde los 94 ms del recorrido completo. Por la misma razón, la CPU sin índice varió de 47 a 125 ms entre corridas iguales.
- **No hubo planes paralelos ni Lookup inesperados.** Los tres planes son seriales porque Express no paraleliza, y el de cobertura no tiene ningún *Lookup*. Los escenarios con índice se repitieron una vez por una corrida atípica, y la repetición dio las mismas lecturas.
- **Cada índice tiene su costo.** El agrupado tardó 692 ms en crearse, porque reescribe la tabla en orden, pero no ocupa espacio extra. El de cobertura tardó 517 ms y agrega 4346 páginas, el 83 % del heap, que se mantienen en cada escritura.

### Aplicación al sistema real

Los reportes por período del proyecto filtran las ventas por `PAGO.fecha_pago`. Un índice no agrupado sobre esa fecha, que incluya las columnas que leen los reportes, seguiría el mismo criterio que el de cobertura. Hoy no hace falta: la tabla tiene 718 pagos, que entran en pocas páginas, y un recorrido completo cuesta menos que mantener un índice más. La medición muestra el punto en que conviene crearlo: cuando el período buscado es una fracción chica de una tabla grande.
