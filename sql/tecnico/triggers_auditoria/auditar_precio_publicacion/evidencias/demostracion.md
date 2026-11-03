# Demostración de `auditar_precio_publicacion/demostracion.sql`

- **Fecha:** 2026-11-03 15:13
- **Repetición:** 2026-11-03, enseguida y sobre la misma base, después de repetir la demostración de `estructura_auditoria`: los mismos resultados, con los usuarios 508 a 510, las publicaciones 795 a 797 y los eventos desde el 10, en lugar de 503 a 505, 792 a 794 y desde el 1. En el caso 9, `IDENT_CURRENT` pasó de 17 a 18. Las dos corridas previas a las pruebas de mutación, sobre otra base recién creada, también dieron 26 de 26 con `filas_demo` en 0.
- **Base temporal:** `tmp_validacion_aud`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más `triggers_auditoria/estructura_auditoria/script.sql` y `auditar_precio_publicacion/script.sql`. Antes se ejecutó la demostración de `estructura_auditoria`.
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración.

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 26             | 26        | 0        | 0          |

Tablas que escribe la demostración, antes y después de ejecutarla. El checksum es `CHECKSUM_AGG(BINARY_CHECKSUM(*))`:

| Tabla             | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| ----------------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| USUARIO           | 500         | 500           | -1321992964    | -1321992964      | 502                 | 505                   |
| PUBLICACION       | 791         | 791           | 1804080490     | 1804080490       | 791                 | 794                   |
| AUDITORIA         | 0           | 0             | NULL           | NULL             | 1                   | 9                     |
| AUDITORIA_DETALLE | 0           | 0             | NULL           | NULL             | 1                   | 9                     |

`AUDITORIA` usó 9 valores, del 1 al 9 (mientras la tabla no tuvo filas, `IDENT_CURRENT` devolvía la semilla, 1). Siete son los eventos confirmados de los casos 1, 2, 4 (tres), 5 y 6, que la limpieza borra junto con las filas de la demostración. Los otros dos son de cambios revertidos, que no dejaron filas: el 8, del `ROLLBACK` del caso 7, y el 9, del error del caso 9. `AUDITORIA_DETALLE` avanza igual, con un valor por evento. El usuario `demo_auditoria_sin_login` no existe antes ni después, y `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado`, que la limpieza deshabilita dentro de su transacción, quedan habilitados (`is_disabled = 0`).

Datos de la demostración: el administrador 503, el vendedor 504 y el cliente 505. El vendedor crea las publicaciones 792 (15000.00), 793 (8000.00) y 794 (12500.00), con stock 5, sobre libros con autor.

Las comprobaciones de eventos resumen los eventos de precio de una publicación posteriores al inicio del paso como `operación columna: anterior a nuevo; usuario; origen`, con `-` para un usuario u origen NULL, y separan los eventos con ` / `. **Login y fecha** comprueba que todos esos eventos tengan `login_bd = ORIGINAL_LOGIN()` y una fecha entre el inicio del paso y la comprobación.

## Caso 1: el vendedor cambia un precio

Con el vendedor 504 declarado en la sesión, el precio de la publicación 792 pasa de 15000.00 a 16500.00. El historial de la publicación en `vw_Auditoria`:

| auditoria_id | fecha                   | tabla       | operacion | registro_id | columna | valor_anterior | valor_nuevo | login_bd     | usuario_id | usuario_email                                           | origen |
| ------------ | ----------------------- | ----------- | --------- | ----------- | ------- | -------------- | ----------- | ------------ | ---------- | ------------------------------------------------------- | ------ |
| 1            | 2026-11-03 15:13:05.863 | PUBLICACION | U         | 792         | precio  | 15000.00       | 16500.00    | `admin\user` | 504        | demo.auditoria.auditar_precio_publicacion.2@example.com | NULL   |

| Comprobación      | Esperado                                             | Obtenido                                             | Resultado |
| ----------------- | ---------------------------------------------------- | ---------------------------------------------------- | --------- |
| Evento del cambio | U precio: 15000.00 a 16500.00; usuario 504; origen - | U precio: 15000.00 a 16500.00; usuario 504; origen - | OK        |
| Login y fecha     | 1 evento; login real; fecha del paso                 | 1 evento; login real; fecha del paso                 | OK        |

## Caso 2: el administrador cambia el mismo precio

El administrador 503 baja el precio de la publicación 792 a 16000.00. El historial desde el caso 1 tiene dos eventos, en orden: el valor anterior del segundo es el nuevo del primero, y cambia el usuario.

| Comprobación                           | Esperado                                                                                                    | Obtenido                                                                                                    | Resultado |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | --------- |
| Historial de los casos 1 y 2, en orden | U precio: 15000.00 a 16500.00; usuario 504; origen - / U precio: 16500.00 a 16000.00; usuario 503; origen - | U precio: 15000.00 a 16500.00; usuario 504; origen - / U precio: 16500.00 a 16000.00; usuario 503; origen - | OK        |

## Caso 3: `UPDATE` que no cambia el precio

Dos sentencias sobre la publicación 792: `stock = stock + 1`, que no menciona el precio, y `precio = precio`. En la segunda, `UPDATE(precio)` es verdadero y el filtro con `EXCEPT` descarta la fila.

| Comprobación         | Esperado    | Obtenido    | Resultado |
| -------------------- | ----------- | ----------- | --------- |
| Solo cambia el stock | sin eventos | sin eventos | OK        |
| precio = precio      | sin eventos | sin eventos | OK        |

## Caso 4: una sentencia sube un 10 % las tres publicaciones

`precio = ROUND(precio * 1.10, 2)` sobre las publicaciones del vendedor 504: un evento por fila, cada uno con sus valores.

| Comprobación                      | Esperado                                             | Obtenido                                             | Resultado |
| --------------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | --------- |
| Eventos de precio de la sentencia | 3                                                    | 3                                                    | OK        |
| Publicación 1                     | U precio: 16000.00 a 17600.00; usuario 504; origen - | U precio: 16000.00 a 17600.00; usuario 504; origen - | OK        |
| Publicación 2                     | U precio: 8000.00 a 8800.00; usuario 504; origen -   | U precio: 8000.00 a 8800.00; usuario 504; origen -   | OK        |
| Publicación 3                     | U precio: 12500.00 a 13750.00; usuario 504; origen - | U precio: 12500.00 a 13750.00; usuario 504; origen - | OK        |

## Caso 5: cambio sin usuario de sesión

Sin usuario declarado, como un script de mantenimiento, el precio de la publicación 793 pasa a 9000.00. `usuario_id` queda en NULL, y el login identifica igual quién se conectó.

| Comprobación                   | Esperado                                         | Obtenido                                         | Resultado |
| ------------------------------ | ------------------------------------------------ | ------------------------------------------------ | --------- |
| Evento sin usuario del sistema | U precio: 8800.00 a 9000.00; usuario -; origen - | U precio: 8800.00 a 9000.00; usuario -; origen - | OK        |
| Login y fecha                  | 1 evento; login real; fecha del paso             | 1 evento; login real; fecha del paso             | OK        |

## Caso 6: cambio bajo `EXECUTE AS USER`

La demostración crea `demo_auditoria_sin_login` (`CREATE USER ... WITHOUT LOGIN`), le concede `SELECT` y `UPDATE` sobre `PUBLICACION` y nada más, y con el vendedor 504 declarado en la sesión cambia el precio de la publicación 794 a 13000.00 bajo `EXECUTE AS USER`. Después ejecuta `REVERT` y borra el usuario. Bajo la suplantación, `SUSER_SNAME()` devuelve un valor distinto del login real, y `ORIGINAL_LOGIN()`, el que llena `login_bd`, no cambia. El usuario no tiene permisos sobre `AUDITORIA` ni sobre `usp_RegistrarAuditoria`, y el evento se registra igual: el trigger, el procedimiento y la tabla son de `dbo`, y el encadenamiento de propiedad evita revisar esos permisos.

| Comprobación                   | Esperado                                                                                                   | Obtenido                                                                                                   | Resultado |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | --------- |
| Permisos del usuario sin login | UPDATE en PUBLICACION 1; SELECT en AUDITORIA 0; INSERT en AUDITORIA 0; EXECUTE en usp_RegistrarAuditoria 0 | UPDATE en PUBLICACION 1; SELECT en AUDITORIA 0; INSERT en AUDITORIA 0; EXECUTE en usp_RegistrarAuditoria 0 | OK        |
| Error del cambio de precio     | sin error                                                                                                  | sin error                                                                                                  | OK        |
| SUSER_SNAME() bajo EXECUTE AS  | distinto del login real                                                                                    | distinto del login real                                                                                    | OK        |
| Evento                         | U precio: 13750.00 a 13000.00; usuario 504; origen -                                                       | U precio: 13750.00 a 13000.00; usuario 504; origen -                                                       | OK        |
| Login y fecha                  | 1 evento; login real; fecha del paso                                                                       | 1 evento; login real; fecha del paso                                                                       | OK        |

## Caso 7: cambio de precio revertido

Dentro de `BEGIN TRANSACTION`, el precio de la publicación 792 pasa a 18000.00. El evento se ve dentro de la transacción, y el `ROLLBACK` lo deshace junto con el cambio. El valor IDENTITY que usó (el 8) no vuelve.

| Comprobación                | Esperado                                             | Obtenido                                             | Resultado |
| --------------------------- | ---------------------------------------------------- | ---------------------------------------------------- | --------- |
| Dentro de la transacción    | U precio: 17600.00 a 18000.00; usuario 504; origen - | U precio: 17600.00 a 18000.00; usuario 504; origen - | OK        |
| Después del ROLLBACK        | sin eventos                                          | sin eventos                                          | OK        |
| Precio después del ROLLBACK | 17600.00                                             | 17600.00                                             | OK        |
| IDENTITY de AUDITORIA       | avanzó sin filas nuevas                              | avanzó sin filas nuevas                              | OK        |

## Caso 8: precio 0

`chk_publicacion_precio` rechaza la sentencia antes de que corran los triggers.

| Comprobación | Esperado                   | Obtenido                   | Resultado |
| ------------ | -------------------------- | -------------------------- | --------- |
| Error        | 547 chk_publicacion_precio | 547 chk_publicacion_precio | OK        |
| Eventos      | sin eventos                | sin eventos                | OK        |

## Caso 9: cambio de precio y de vendedor a un cliente

Una sentencia pasa el precio de la publicación 792 a 20000.00 y su vendedor al cliente 505. `trg_PUBLICACION_Vendedor` la rechaza con 50271 y se revierte entera. La demostración imprime `IDENT_CURRENT de AUDITORIA antes 8, después 9`: en esta corrida, el trigger de auditoría corrió antes del error, y su evento se revirtió con la sentencia. El orden de los triggers no está fijado: si `trg_PUBLICACION_Vendedor` corriera primero, la auditoría no llegaría a correr, y tampoco quedaría un evento.

| Comprobación                  | Esperado              | Obtenido              | Resultado |
| ----------------------------- | --------------------- | --------------------- | --------- |
| Error                         | 50271                 | 50271                 | OK        |
| Eventos                       | sin eventos           | sin eventos           | OK        |
| Precio y vendedor sin cambios | 17600.00; usuario 504 | 17600.00; usuario 504 | OK        |

## Caso 10: transacciones abiertas

`@Abiertas` suma `@@TRANCOUNT` después de las llamadas a `usp_EstablecerUsuarioSesion`, de la creación de las publicaciones, del cambio bajo `EXECUTE AS`, de las sentencias que fallan y del `ROLLBACK` del caso 7.

| Comprobación           | Esperado | Obtenido | Resultado |
| ---------------------- | -------- | -------- | --------- |
| Transacciones abiertas | 0        | 0        | OK        |
