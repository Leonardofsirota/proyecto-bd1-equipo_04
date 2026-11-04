# Control de carga de datos - Etapa 4

Este documento explica la consulta [`control/control-carga-datos.sql`](../../sql/consultas/control/control-carga-datos.sql). No corresponde a ningún caso de uso.

## 1. Qué hace

Muestra el contenido completo de las 21 tablas de la base, una por una y en orden alfabético.

## 2. Quién la usa

Ninguno de los roles del sistema. La usa el equipo de desarrollo después de la precarga, para revisar a simple vista que los datos se cargaron. Forma parte de las [pruebas de la Etapa 3](../etapa-03/pruebas-validacion.md#4-datos-de-prueba).

## 3. Cómo lo resuelve

Un `SELECT *` por tabla, sin uniones ni filtros.

## 4. Resultado esperado

Devuelve 21 resultados, uno por tabla, con 6.173 filas en total.
