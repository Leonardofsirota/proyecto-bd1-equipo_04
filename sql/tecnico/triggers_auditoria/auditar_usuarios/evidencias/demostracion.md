# Demostración: auditoría de los usuarios

Prueba `trg_USUARIO_Auditoria`, que registra el alta, los cambios y el borrado de cada usuario. USUARIO no guarda cuándo se registró nadie ni quién cambió sus datos, su rol o su baja (RN02, RN03, RN28): lo guarda el evento, sin registrar nunca la contraseña. La demostración trabaja con usuarios, una publicación y un pedido propios, y los borra al terminar.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **22 de 22** comprobaciones correctas

## Resumen

| Caso | Qué se prueba                                          | Comprobaciones | Resultado |
| ---- | ------------------------------------------------------ | -------------- | --------- |
| 1    | Alta de un cliente sin usuario de sesión               | 3              | OK        |
| 2    | El cliente cambia su email, su teléfono y su apellido  | 1              | OK        |
| 3    | El cliente cambia su contraseña                        | 2              | OK        |
| 4    | El administrador cambia a Vendedor el rol del cliente  | 1              | OK        |
| 5    | Cambiar el rol del cliente que tiene un pedido         | 3              | OK        |
| 6    | El administrador da de baja a un cliente y lo reactiva | 1              | OK        |
| 7    | Una sentencia cambia el teléfono de dos clientes       | 3              | OK        |
| 8    | Cambio de email revertido                              | 4              | OK        |
| 9    | Borrado físico del cliente sin relaciones              | 3              | OK        |
| 10   | Transacciones abiertas tras cada llamada               | 1              | OK        |

Cada evento se lee `operación columna: anterior a nuevo; usuario; origen`. I es alta, U cambio y D borrado, `-` es un valor vacío, y el origen es el trigger que hizo el cambio, vacío si lo hizo una sentencia o un procedimiento. **Login y fecha** comprueba que el evento guarde el login real y una fecha dentro del paso. Las comprobaciones toman todas las columnas de USUARIO salvo el ID.

La demostración usa un administrador, un vendedor y dos clientes: el comprador, que tiene un pedido de una publicación del vendedor, y el visitante, sin relaciones. En el caso 1 se registra un tercer cliente, el cliente nuevo.

## Caso 1: alta de un cliente sin usuario de sesión

Un `INSERT` sin usuario de sesión, como el autorregistro, crea al cliente nuevo. USUARIO no tiene fecha de alta: el evento I es la única constancia de cuándo se registró (RN03). Guarda todos sus datos, sin usuario de sesión y sin origen, salvo la contraseña y `fecha_eliminacion`, que es NULL:

| Columna          | Nuevo                                         |
| ---------------- | --------------------------------------------- |
| apellido         | Demo                                          |
| dni              | 99106105                                      |
| email            | demo.auditoria.auditar_usuarios.5@example.com |
| fecha_nacimiento | 1995-05-20                                    |
| nombre           | Nuevo                                         |
| rol              | Cliente                                       |
| telefono         | 3794106105                                    |

| Comprobación              | Valor                                         | Resultado |
| ------------------------- | --------------------------------------------- | --------- |
| Evento del alta           | I con las siete columnas; usuario -; origen - | OK        |
| Login y fecha             | 1 evento; login real; fecha del paso          | OK        |
| Detalles de password_hash | 0                                             | OK        |

## Caso 2: el cliente cambia su email, su teléfono y su apellido

Con el cliente nuevo en la sesión, una sentencia cambia su email y su teléfono, y su apellido solo de minúsculas a mayúsculas. La intercalación de la base no distingue mayúsculas, pero la comparación del trigger usa `Latin1_General_BIN2`, que sí las distingue: el evento tiene los tres cambios, con el cliente como usuario y sin origen.

| Columna  | Anterior                                      | Nuevo                                               |
| -------- | --------------------------------------------- | --------------------------------------------------- |
| apellido | Demo                                          | DEMO                                                |
| email    | demo.auditoria.auditar_usuarios.5@example.com | demo.auditoria.auditar_usuarios.5.nuevo@example.com |
| telefono | 3794106105                                    | 3794999105                                          |

| Comprobación               | Valor                                               | Resultado |
| -------------------------- | --------------------------------------------------- | --------- |
| Evento del cambio de datos | U apellido, email y telefono; cliente 507; origen - | OK        |

## Caso 3: el cliente cambia su contraseña

El cliente nuevo cambia su `password_hash`. El evento solo deja constancia de que cambió, con `(oculto)` como valor anterior y `(cambiado)` como nuevo. Ni el hash anterior ni el nuevo aparecen en ninguna fila de AUDITORIA_DETALLE.

| Comprobación                    | Valor                                                         | Resultado |
| ------------------------------- | ------------------------------------------------------------- | --------- |
| Evento del cambio de contraseña | U password_hash: (oculto) a (cambiado); cliente 507; origen - | OK        |
| Hashes en AUDITORIA_DETALLE     | 0                                                             | OK        |

## Caso 4: el administrador cambia a Vendedor el rol del cliente nuevo

El administrador cambia a Vendedor el rol del cliente nuevo, que no tiene pedidos ni publicaciones (RN02). `vw_Auditoria` reúne en orden los eventos de los casos 1 a 4 del usuario, con quién hizo cada cambio: nadie en el alta, el propio cliente en sus datos y su contraseña, y el administrador en el rol.

| Comprobación             | Valor                                                  | Resultado |
| ------------------------ | ------------------------------------------------------ | --------- |
| Evento del cambio de rol | U rol: Cliente a Vendedor; administrador 503; origen - | OK        |

## Caso 5: cambiar el rol del cliente que tiene un pedido

El administrador intenta cambiar a Vendedor el rol del comprador, que tiene un pedido. `trg_USUARIO_CambioRol` rechaza la sentencia con el error 50281 (RN04, RN10), se revierte entera y no queda ningún evento.

| Comprobación    | Valor       | Resultado |
| --------------- | ----------- | --------- |
| Error           | 50281       | OK        |
| Eventos         | sin eventos | OK        |
| Rol sin cambios | Cliente     | OK        |

## Caso 6: el administrador da de baja a un cliente y lo reactiva

El administrador da de baja al comprador y después lo reactiva, con dos sentencias (RN28). Después de reactivarlo, USUARIO ya no guarda la fecha de baja: solo queda en el historial. Una sola comprobación toma los dos eventos, en orden:

| Orden | Evento                                                                           | Resultado |
| ----- | -------------------------------------------------------------------------------- | --------- |
| 1     | U fecha_eliminacion: NULL a 2026-11-03 15:47:29.470; administrador 503; origen - | OK        |
| 2     | U fecha_eliminacion: 2026-11-03 15:47:29.470 a NULL; administrador 503; origen - | OK        |

## Caso 7: una sentencia cambia el teléfono de dos clientes

Sin usuario de sesión, como un script de mantenimiento, una sentencia cambia el prefijo del teléfono del comprador y del visitante. Hay un evento por fila, cada uno con sus valores.

| Comprobación            | Valor                                                    | Resultado |
| ----------------------- | -------------------------------------------------------- | --------- |
| Eventos de la sentencia | 2                                                        | OK        |
| Evento del comprador    | U telefono: 3794106103 a 3795106103; usuario -; origen - | OK        |
| Evento del visitante    | U telefono: 3794106104 a 3795106104; usuario -; origen - | OK        |

## Caso 8: cambio de email revertido

Con el visitante en la sesión, una transacción cambia su email y termina con `ROLLBACK`. Dentro de la transacción el evento se ve; el `ROLLBACK` lo deshace junto con el cambio. El número de evento se consumió, pero no quedó ninguna fila.

| Comprobación               | Valor                                                                                                                                 | Resultado |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Dentro de la transacción   | U email: demo.auditoria.auditar_usuarios.4@example.com a demo.auditoria.auditar_usuarios.4.nuevo@example.com; visitante 506; origen - | OK        |
| Después del ROLLBACK       | sin eventos                                                                                                                           | OK        |
| Email después del ROLLBACK | demo.auditoria.auditar_usuarios.4@example.com                                                                                         | OK        |
| IDENTITY de AUDITORIA      | avanzó sin filas nuevas                                                                                                               | OK        |

## Caso 9: borrado físico del cliente sin relaciones

El administrador borra al visitante, que no tiene relaciones. El evento D, con el administrador como usuario y sin origen, guarda la última versión de la fila, con el teléfono del caso 7: todas sus columnas como valor anterior y ningún valor nuevo. La contraseña no se registra, y `fecha_eliminacion` valía NULL y no aparece.

| Columna          | Anterior                                      |
| ---------------- | --------------------------------------------- |
| apellido         | Demo                                          |
| dni              | 99106104                                      |
| email            | demo.auditoria.auditar_usuarios.4@example.com |
| fecha_nacimiento | 1990-01-01                                    |
| nombre           | Visitante                                     |
| rol              | Cliente                                       |
| telefono         | 3795106104                                    |

| Comprobación            | Valor                                                       | Resultado |
| ----------------------- | ----------------------------------------------------------- | --------- |
| Evento del borrado      | D con las columnas de la tabla; administrador 503; origen - | OK        |
| Login y fecha           | 1 evento; login real; fecha del paso                        | OK        |
| El usuario ya no existe | 0                                                           | OK        |

## Caso 10: transacciones abiertas

Después de cada llamada a un procedimiento, de la creación de la publicación y del pedido, del `ROLLBACK` del caso 8 y de la sentencia que falla, no quedó ninguna transacción abierta (0).

## Conclusión

`trg_USUARIO_Auditoria` deja el historial de cada usuario: el alta, que es la única fecha de registro, los cambios de datos con quién los hizo, incluso los que solo cambian mayúsculas, la baja y la reactivación, y el borrado con la fila completa. La contraseña nunca se registra: un cambio de contraseña queda como `(oculto)` a `(cambiado)`. Una sentencia sobre varias filas deja un evento por fila, y un cambio rechazado (50281) o revertido no deja eventos. La limpieza no dejó filas de la demostración y dejó la base igual, y los triggers que deshabilita mientras borra quedaron habilitados.
