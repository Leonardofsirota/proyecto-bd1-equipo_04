# Demostración de `auditar_usuarios/demostracion.sql`

- **Fecha:** 2026-11-03 15:47
- **Repetición:** 2026-11-03, enseguida y sobre la misma base, después de repetir la demostración de `auditar_pagos`: los mismos resultados, con los usuarios 510 a 514, la publicación 795, el pedido 608 y los eventos del 55 al 74, en lugar de 503 a 507, 793, 604 y del 18 al 37. Las corridas anteriores, sobre otra base, también dieron 22 de 22 con `filas_demo` en 0: las seis demostraciones de `triggers_auditoria` dos veces seguidas.
- **Base temporal:** `tmp_validacion_aud`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más los `script.sql` de las seis carpetas de `triggers_auditoria`: `estructura_auditoria`, `auditar_precio_publicacion`, `auditar_stock_publicacion`, `auditar_pedidos`, `auditar_pagos` y `auditar_usuarios`. Antes se ejecutó la demostración de `auditar_pagos`.
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración. El desglose de los valores IDENTITY de AUDITORIA se comprobó con una copia de la demostración que lista AUDITORIA antes de la limpieza final, ejecutada después sobre la misma base. El caso 3 usa dos contraseñas de ejemplo que esta evidencia no reproduce.

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 22             | 22        | 0        | 0          |

Tablas que escribe la demostración, antes y después de ejecutarla. El checksum es `CHECKSUM_AGG(BINARY_CHECKSUM(*))`:

| Tabla             | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| ----------------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| USUARIO           | 500         | 500           | -1321992964    | -1321992964      | 502                 | 507                   |
| DIRECCION         | 603         | 603           | -544889019     | -544889019       | 604                 | 605                   |
| PUBLICACION       | 791         | 791           | 1804080490     | 1804080490       | 792                 | 793                   |
| PEDIDO            | 600         | 600           | -2005910744    | -2005910744      | 603                 | 604                   |
| PEDIDO_DETALLE    | 1290        | 1290          | 417360875      | 417360875        | 1293                | 1294                  |
| PAGO              | 718         | 718           | -1763708289    | -1763708289      | 722                 | 722                   |
| AUDITORIA         | 0           | 0             | NULL           | NULL             | 17                  | 37                    |
| AUDITORIA_DETALLE | 0           | 0             | NULL           | NULL             | 61                  | 149                   |

`AUDITORIA` usó 20 valores, del 18 al 37:

- 13 eventos confirmados, todos de `trg_USUARIO_Auditoria`: el alta de los cuatro usuarios iniciales, uno por cada caso del 1 al 4, dos del caso 6, dos del caso 7 y el borrado del caso 9.
- Dos valores de eventos revertidos: el del caso 5, que la auditoría registró antes del error de `trg_USUARIO_CambioRol`, y el del `ROLLBACK` del caso 8.
- Cinco eventos D de la limpieza: el borrado de la publicación y de los usuarios 503, 504, 505 y 507, que la limpieza después borra junto con los demás eventos.

`AUDITORIA_DETALLE` avanza con un valor por columna registrada: 88, del 62 al 149. Cada alta o borrado de un usuario tiene siete detalles, porque `password_hash` nunca se registra y `fecha_eliminacion` era NULL. `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado`, que la limpieza deshabilita dentro de su transacción, quedan habilitados (`is_disabled = 0`).

Datos de la demostración, cargados sin usuario de sesión: el administrador 503, el vendedor 504 y dos clientes, el comprador 505 y el visitante 506. El comprador tiene la dirección 605 y el pedido 604, creado con `usp_CrearPedido` en su sesión, por 1 unidad de la publicación 793 del vendedor. El visitante no tiene relaciones. Cada usuario tiene un teléfono distinto: `3794` y los últimos seis dígitos de su DNI. El tercer cliente, 507, se registra en el caso 1.

Las comprobaciones de eventos resumen los eventos de un usuario posteriores al inicio del paso como `operación columna: anterior a nuevo; usuario; origen`, con `-` para un usuario u origen NULL, y solo toman `apellido`, `dni`, `email`, `fecha_eliminacion`, `fecha_nacimiento`, `nombre`, `password_hash`, `rol` y `telefono`. **Login y fecha** comprueba que todos esos eventos tengan `login_bd = ORIGINAL_LOGIN()` y una fecha entre el inicio del paso y la comprobación.

## Caso 1: alta de un cliente sin usuario de sesión

Un `INSERT` sin usuario de sesión, como el autorregistro, crea al cliente 507. USUARIO no tiene fecha de alta: el evento I registra cuándo se registró (RN03), con todos sus datos salvo la contraseña. `fecha_eliminacion` es NULL y tampoco tiene detalle.

| Comprobación              | Esperado                                                                                                                                                                                                                                     | Obtenido                                                                                                                                                                                                                                     | Resultado |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Evento del alta           | I apellido: NULL a Demo, dni: NULL a 99106105, email: NULL a demo.auditoria.auditar_usuarios.5@example.com, fecha_nacimiento: NULL a 1995-05-20, nombre: NULL a Nuevo, rol: NULL a Cliente, telefono: NULL a 3794106105; usuario -; origen - | I apellido: NULL a Demo, dni: NULL a 99106105, email: NULL a demo.auditoria.auditar_usuarios.5@example.com, fecha_nacimiento: NULL a 1995-05-20, nombre: NULL a Nuevo, rol: NULL a Cliente, telefono: NULL a 3794106105; usuario -; origen - | OK        |
| Login y fecha             | 1 evento; login real; fecha del paso                                                                                                                                                                                                         | 1 evento; login real; fecha del paso                                                                                                                                                                                                         | OK        |
| Detalles de password_hash | 0                                                                                                                                                                                                                                            | 0                                                                                                                                                                                                                                            | OK        |

## Caso 2: el cliente cambia su email, su teléfono y su apellido

Con el cliente 507 en la sesión, una sentencia cambia su email y su teléfono, y su apellido solo de `Demo` a `DEMO`. La intercalación de la base no distingue mayúsculas, y la comparación con `Latin1_General_BIN2` sí: el evento tiene los tres detalles.

| Comprobación               | Esperado                                                                                                                                                                                      | Obtenido                                                                                                                                                                                      | Resultado |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Evento del cambio de datos | U apellido: Demo a DEMO, email: demo.auditoria.auditar_usuarios.5@example.com a demo.auditoria.auditar_usuarios.5.nuevo@example.com, telefono: 3794106105 a 3794999105; usuario 507; origen - | U apellido: Demo a DEMO, email: demo.auditoria.auditar_usuarios.5@example.com a demo.auditoria.auditar_usuarios.5.nuevo@example.com, telefono: 3794106105 a 3794999105; usuario 507; origen - | OK        |

## Caso 3: el cliente cambia su contraseña

El cliente 507 cambia su `password_hash`. El evento solo deja constancia de que cambió, con `(oculto)` como valor anterior y `(cambiado)` como nuevo. La segunda comprobación busca el hash anterior y el nuevo en todo `AUDITORIA_DETALLE`, como valor anterior o nuevo, y no los encuentra.

| Comprobación                    | Esperado                                                      | Obtenido                                                      | Resultado |
| ------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------- | --------- |
| Evento del cambio de contraseña | U password_hash: (oculto) a (cambiado); usuario 507; origen - | U password_hash: (oculto) a (cambiado); usuario 507; origen - | OK        |
| Hashes en AUDITORIA_DETALLE     | 0                                                             | 0                                                             | OK        |

## Caso 4: el administrador cambia a Vendedor el rol del cliente nuevo

El administrador 503 cambia a Vendedor el rol del cliente 507, que no tiene pedidos ni publicaciones (RN02). El historial del usuario en `vw_Auditoria`, con los eventos de los casos 1 a 4:

| auditoria_id | fecha                   | tabla   | operacion | registro_id | columna          | valor_anterior                                | valor_nuevo                                         | login_bd     | usuario_id | usuario_email                                       | origen |
| ------------ | ----------------------- | ------- | --------- | ----------- | ---------------- | --------------------------------------------- | --------------------------------------------------- | ------------ | ---------- | --------------------------------------------------- | ------ |
| 22           | 2026-11-03 15:47:29.377 | USUARIO | I         | 507         | apellido         | NULL                                          | Demo                                                | `admin\user` | NULL       | NULL                                                | NULL   |
| 22           | 2026-11-03 15:47:29.377 | USUARIO | I         | 507         | dni              | NULL                                          | 99106105                                            | `admin\user` | NULL       | NULL                                                | NULL   |
| 22           | 2026-11-03 15:47:29.377 | USUARIO | I         | 507         | email            | NULL                                          | demo.auditoria.auditar_usuarios.5@example.com       | `admin\user` | NULL       | NULL                                                | NULL   |
| 22           | 2026-11-03 15:47:29.377 | USUARIO | I         | 507         | fecha_nacimiento | NULL                                          | 1995-05-20                                          | `admin\user` | NULL       | NULL                                                | NULL   |
| 22           | 2026-11-03 15:47:29.377 | USUARIO | I         | 507         | nombre           | NULL                                          | Nuevo                                               | `admin\user` | NULL       | NULL                                                | NULL   |
| 22           | 2026-11-03 15:47:29.377 | USUARIO | I         | 507         | rol              | NULL                                          | Cliente                                             | `admin\user` | NULL       | NULL                                                | NULL   |
| 22           | 2026-11-03 15:47:29.377 | USUARIO | I         | 507         | telefono         | NULL                                          | 3794106105                                          | `admin\user` | NULL       | NULL                                                | NULL   |
| 23           | 2026-11-03 15:47:29.423 | USUARIO | U         | 507         | apellido         | Demo                                          | DEMO                                                | `admin\user` | 507        | demo.auditoria.auditar_usuarios.5.nuevo@example.com | NULL   |
| 23           | 2026-11-03 15:47:29.423 | USUARIO | U         | 507         | email            | demo.auditoria.auditar_usuarios.5@example.com | demo.auditoria.auditar_usuarios.5.nuevo@example.com | `admin\user` | 507        | demo.auditoria.auditar_usuarios.5.nuevo@example.com | NULL   |
| 23           | 2026-11-03 15:47:29.423 | USUARIO | U         | 507         | telefono         | 3794106105                                    | 3794999105                                          | `admin\user` | 507        | demo.auditoria.auditar_usuarios.5.nuevo@example.com | NULL   |
| 24           | 2026-11-03 15:47:29.450 | USUARIO | U         | 507         | password_hash    | (oculto)                                      | (cambiado)                                          | `admin\user` | 507        | demo.auditoria.auditar_usuarios.5.nuevo@example.com | NULL   |
| 25           | 2026-11-03 15:47:29.457 | USUARIO | U         | 507         | rol              | Cliente                                       | Vendedor                                            | `admin\user` | 503        | demo.auditoria.auditar_usuarios.1@example.com       | NULL   |

Del 18 al 21 son las altas de los cuatro usuarios iniciales. `usuario_email` sale de la fila actual de USUARIO, no del momento del evento: el evento 23 muestra el email nuevo del cliente, aunque es el que lo cambió. El email que tenía está en `valor_anterior`.

| Comprobación             | Esperado                                         | Obtenido                                         | Resultado |
| ------------------------ | ------------------------------------------------ | ------------------------------------------------ | --------- |
| Evento del cambio de rol | U rol: Cliente a Vendedor; usuario 503; origen - | U rol: Cliente a Vendedor; usuario 503; origen - | OK        |

## Caso 5: cambiar el rol del cliente que tiene un pedido

El administrador 503 intenta cambiar a Vendedor el rol del comprador 505, que tiene el pedido 604: `trg_USUARIO_CambioRol` lo rechaza con 50281 (RN04, RN10). El orden de los triggers de UPDATE de USUARIO no está fijado. La demostración imprimió `Caso 5: IDENT_CURRENT de AUDITORIA antes 25, después 26`: la auditoría corrió antes del error y su evento se revirtió con la sentencia. En la repetición pasó lo mismo, con 62 y 63.

| Comprobación    | Esperado    | Obtenido    | Resultado |
| --------------- | ----------- | ----------- | --------- |
| Error           | 50281       | 50281       | OK        |
| Eventos         | sin eventos | sin eventos | OK        |
| Rol sin cambios | Cliente     | Cliente     | OK        |

## Caso 6: el administrador da de baja a un cliente y lo reactiva

El administrador 503 da de baja al comprador 505 y después lo reactiva, con dos sentencias (RN28). Después de reactivarlo, USUARIO ya no guarda la fecha de baja: solo queda en el historial.

| Comprobación                         | Esperado                                                                                                                                                | Obtenido                                                                                                                                                | Resultado |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Eventos de la baja y la reactivación | U fecha_eliminacion: NULL a 2026-11-03 15:47:29.470; usuario 503; origen - / U fecha_eliminacion: 2026-11-03 15:47:29.470 a NULL; usuario 503; origen - | U fecha_eliminacion: NULL a 2026-11-03 15:47:29.470; usuario 503; origen - / U fecha_eliminacion: 2026-11-03 15:47:29.470 a NULL; usuario 503; origen - | OK        |

## Caso 7: una sentencia cambia el teléfono de dos clientes

Sin usuario de sesión, como un script de mantenimiento, una sentencia cambia el prefijo del teléfono del comprador 505 y del visitante 506. Hay un evento por fila, cada uno con sus valores.

| Comprobación            | Esperado                                                 | Obtenido                                                 | Resultado |
| ----------------------- | -------------------------------------------------------- | -------------------------------------------------------- | --------- |
| Eventos de la sentencia | 2                                                        | 2                                                        | OK        |
| Evento del comprador    | U telefono: 3794106103 a 3795106103; usuario -; origen - | U telefono: 3794106103 a 3795106103; usuario -; origen - | OK        |
| Evento del visitante    | U telefono: 3794106104 a 3795106104; usuario -; origen - | U telefono: 3794106104 a 3795106104; usuario -; origen - | OK        |

## Caso 8: cambio de email revertido

Con el visitante 506 en la sesión: `BEGIN TRANSACTION`, cambio de su email y `ROLLBACK`. Dentro de la transacción el evento se ve. El `ROLLBACK` lo deshace junto con el cambio, y el valor IDENTITY que usó no vuelve.

| Comprobación               | Esperado                                                                                                                            | Obtenido                                                                                                                            | Resultado |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Dentro de la transacción   | U email: demo.auditoria.auditar_usuarios.4@example.com a demo.auditoria.auditar_usuarios.4.nuevo@example.com; usuario 506; origen - | U email: demo.auditoria.auditar_usuarios.4@example.com a demo.auditoria.auditar_usuarios.4.nuevo@example.com; usuario 506; origen - | OK        |
| Después del ROLLBACK       | sin eventos                                                                                                                         | sin eventos                                                                                                                         | OK        |
| Email después del ROLLBACK | demo.auditoria.auditar_usuarios.4@example.com                                                                                       | demo.auditoria.auditar_usuarios.4@example.com                                                                                       | OK        |
| IDENTITY de AUDITORIA      | avanzó sin filas nuevas                                                                                                             | avanzó sin filas nuevas                                                                                                             | OK        |

## Caso 9: borrado físico del cliente sin relaciones

El administrador 503 borra al visitante 506. El evento D guarda la última versión de la fila, con el teléfono del caso 7, sin la contraseña y sin `fecha_eliminacion`, que era NULL. La demostración anotó al visitante en `#FilasDemoAuditoria` al crearlo: la limpieza, que busca los usuarios por su email, ya no lo encuentra, y sus eventos quedarían sueltos.

| Comprobación            | Esperado                                                                                                                                                                                                                                           | Obtenido                                                                                                                                                                                                                                           | Resultado |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Evento del borrado      | D apellido: Demo a NULL, dni: 99106104 a NULL, email: demo.auditoria.auditar_usuarios.4@example.com a NULL, fecha_nacimiento: 1990-01-01 a NULL, nombre: Visitante a NULL, rol: Cliente a NULL, telefono: 3795106104 a NULL; usuario 503; origen - | D apellido: Demo a NULL, dni: 99106104 a NULL, email: demo.auditoria.auditar_usuarios.4@example.com a NULL, fecha_nacimiento: 1990-01-01 a NULL, nombre: Visitante a NULL, rol: Cliente a NULL, telefono: 3795106104 a NULL; usuario 503; origen - | OK        |
| Login y fecha           | 1 evento; login real; fecha del paso                                                                                                                                                                                                               | 1 evento; login real; fecha del paso                                                                                                                                                                                                               | OK        |
| El usuario ya no existe | 0                                                                                                                                                                                                                                                  | 0                                                                                                                                                                                                                                                  | OK        |

## Caso 10: transacciones abiertas

`@Abiertas` suma `@@TRANCOUNT` después de las llamadas a `usp_EstablecerUsuarioSesion`, de la creación de la publicación y del pedido, del `ROLLBACK` del caso 8 y de la sentencia que falla.

| Comprobación           | Esperado | Obtenido | Resultado |
| ---------------------- | -------- | -------- | --------- |
| Transacciones abiertas | 0        | 0        | OK        |
