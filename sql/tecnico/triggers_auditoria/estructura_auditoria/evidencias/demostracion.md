# Demostración de `estructura_auditoria/demostracion.sql`

- **Fecha:** 2026-11-03 15:13
- **Repetición:** 2026-11-03, enseguida y sobre la misma base, después de la demostración de `auditar_precio_publicacion`: los mismos resultados, con el usuario activo 506 en lugar del 501. Las dos corridas previas a las pruebas de mutación, sobre otra base recién creada, también dieron 9 de 9 con `filas_demo` en 0.
- **Base temporal:** `tmp_validacion_aud`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más `triggers_auditoria/estructura_auditoria/script.sql` y `auditar_precio_publicacion/script.sql`
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración. Los triggers se prueban en la demostración de su carpeta.

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 9              | 9         | 0        | 0          |

Tablas que escribe la demostración, antes y después de ejecutarla. El checksum es `CHECKSUM_AGG(BINARY_CHECKSUM(*))`:

| Tabla             | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| ----------------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| USUARIO           | 500         | 500           | -1321992964    | -1321992964      | 500                 | 502                   |
| AUDITORIA         | 0           | 0             | NULL           | NULL             | 1                   | 1                     |
| AUDITORIA_DETALLE | 0           | 0             | NULL           | NULL             | 1                   | 1                     |

`USUARIO` avanza 2, por los dos clientes de la demostración, que la limpieza borra. `AUDITORIA` no usó ningún valor: mientras una tabla no tuvo filas, `IDENT_CURRENT` devuelve la semilla, 1. La llamada del caso 5 falla antes de escribir. `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado`, que la limpieza deshabilita dentro de su transacción, quedan habilitados (`is_disabled = 0`) antes y después.

Datos de la demostración: el cliente activo 501 y el cliente 502, cargado con `fecha_eliminacion`, es decir, dado de baja.

## Caso 1: sesión sin usuario declarado

En una sesión nueva, `CONTEXT_INFO()` es NULL, y `fn_UsuarioSesion()` también.

| Comprobación                             | Esperado | Obtenido | Resultado |
| ---------------------------------------- | -------- | -------- | --------- |
| fn_UsuarioSesion() sin usuario declarado | NULL     | NULL     | OK        |

## Caso 2: usuario activo

`usp_EstablecerUsuarioSesion` declara al cliente 501.

| Comprobación                             | Esperado | Obtenido | Resultado |
| ---------------------------------------- | -------- | -------- | --------- |
| fn_UsuarioSesion() con el usuario activo | 501      | 501      | OK        |

## Caso 3: usuario inexistente y usuario dado de baja

Se intenta declarar el usuario 503 (`MAX(usuario_id) + 1`, calculado justo antes de la llamada) y después el cliente 502, dado de baja. Los dos fallan, y la sesión conserva el usuario del caso 2.

| Comprobación                          | Esperado | Obtenido | Resultado |
| ------------------------------------- | -------- | -------- | --------- |
| Usuario inexistente                   | 50401    | 50401    | OK        |
| Usuario dado de baja                  | 50401    | 50401    | OK        |
| Sigue declarado el usuario del caso 2 | 501      | 501      | OK        |

## Caso 4: limpiar con NULL

`usp_EstablecerUsuarioSesion @UsuarioId = NULL` ejecuta `SET CONTEXT_INFO 0x`.

| Comprobación                          | Esperado | Obtenido | Resultado |
| ------------------------------------- | -------- | -------- | --------- |
| fn_UsuarioSesion() después de limpiar | NULL     | NULL     | OK        |

## Caso 5: `usp_RegistrarAuditoria` fuera de un trigger

Se llama al procedimiento directamente, con un cambio inventado del email del cliente 501. `TRIGGER_NESTLEVEL()` es 0, así que falla antes de escribir.

| Comprobación    | Esperado | Obtenido | Resultado |
| --------------- | -------- | -------- | --------- |
| Llamada directa | 50402    | 50402    | OK        |
| Eventos nuevos  | 0        | 0        | OK        |

## Caso 6: transacciones abiertas

`@Abiertas` suma `@@TRANCOUNT` después de cada llamada a un procedimiento, también de las que fallaron.

| Comprobación                          | Esperado | Obtenido | Resultado |
| ------------------------------------- | -------- | -------- | --------- |
| Transacciones abiertas tras cada EXEC | 0        | 0        | OK        |
