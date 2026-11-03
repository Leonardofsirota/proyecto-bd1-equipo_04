# Demostración: auditoría de los cambios de precio

Prueba `trg_PUBLICACION_AuditoriaPrecio`, que registra cada cambio del precio de una publicación con el valor anterior y el nuevo, el usuario del sistema, el login y la fecha. Los pedidos ya guardan el precio de cada renglón (RN26); el trigger agrega el historial de los cambios en la publicación. La demostración trabaja con usuarios y publicaciones propios, y los borra al terminar.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **26 de 26** comprobaciones correctas

## Resumen

| Caso | Qué se prueba                                 | Comprobaciones | Resultado |
| ---- | --------------------------------------------- | -------------- | --------- |
| 1    | El vendedor cambia un precio                  | 2              | OK        |
| 2    | El administrador cambia el mismo precio       | 1              | OK        |
| 3    | `UPDATE` que no cambia el precio              | 2              | OK        |
| 4    | Una sentencia sube un 10 % tres publicaciones | 4              | OK        |
| 5    | Cambio sin usuario de sesión                  | 2              | OK        |
| 6    | Cambio bajo `EXECUTE AS USER`                 | 5              | OK        |
| 7    | Cambio de precio revertido                    | 4              | OK        |
| 8    | Precio 0                                      | 2              | OK        |
| 9    | Cambio de precio y de vendedor a un cliente   | 3              | OK        |
| 10   | Transacciones abiertas tras cada llamada      | 1              | OK        |

Cada evento se lee `operación columna: anterior a nuevo; usuario; origen`. I es alta, U cambio y D borrado, `-` es un valor vacío, y el origen es el trigger que hizo el cambio, vacío si lo hizo una sentencia o un procedimiento. **Login y fecha** comprueba que el evento guarde el login real y una fecha dentro del paso.

La demostración usa un administrador, un vendedor y un cliente. El vendedor publica tres libros a 15000.00, 8000.00 y 12500.00.

## Caso 1: el vendedor cambia un precio

Con el vendedor declarado en la sesión, el precio de la primera publicación pasa de 15000.00 a 16500.00. El trigger registra un evento con el vendedor como usuario y sin origen, porque el cambio lo hizo una sentencia. El historial de la publicación en `vw_Auditoria`:

| fecha                   | operacion | columna | valor_anterior | valor_nuevo | login_bd     | usuario_id   | origen |
| ----------------------- | --------- | ------- | -------------- | ----------- | ------------ | ------------ | ------ |
| 2026-11-03 15:13:05.863 | U         | precio  | 15000.00       | 16500.00    | `admin\user` | vendedor 504 | NULL   |

| Comprobación      | Valor                                                 | Resultado |
| ----------------- | ----------------------------------------------------- | --------- |
| Evento del cambio | U precio: 15000.00 a 16500.00; vendedor 504; origen - | OK        |
| Login y fecha     | 1 evento; login real; fecha del paso                  | OK        |

## Caso 2: el administrador cambia el mismo precio

El administrador baja el precio de la misma publicación a 16000.00. El historial queda encadenado: el valor anterior del segundo evento es el nuevo del primero, y cada evento tiene su usuario. Una sola comprobación toma los dos eventos, en orden:

| Orden | Evento                                                     | Resultado |
| ----- | ---------------------------------------------------------- | --------- |
| 1     | U precio: 15000.00 a 16500.00; vendedor 504; origen -      | OK        |
| 2     | U precio: 16500.00 a 16000.00; administrador 503; origen - | OK        |

## Caso 3: `UPDATE` que no cambia el precio

Dos sentencias sobre la misma publicación: una cambia solo el stock y la otra asigna al precio su mismo valor. Ninguna deja eventos: el trigger ignora la primera, y en la segunda descarta la fila porque el valor no cambió.

| Comprobación         | Valor       | Resultado |
| -------------------- | ----------- | --------- |
| Solo cambia el stock | sin eventos | OK        |
| precio = precio      | sin eventos | OK        |

## Caso 4: una sentencia sube un 10 % las tres publicaciones

Una sola sentencia sube un 10 % el precio de las tres publicaciones del vendedor. El trigger registra un evento por fila, cada uno con sus valores.

| Comprobación                      | Valor                                                 | Resultado |
| --------------------------------- | ----------------------------------------------------- | --------- |
| Eventos de precio de la sentencia | 3                                                     | OK        |
| Publicación 1                     | U precio: 16000.00 a 17600.00; vendedor 504; origen - | OK        |
| Publicación 2                     | U precio: 8000.00 a 8800.00; vendedor 504; origen -   | OK        |
| Publicación 3                     | U precio: 12500.00 a 13750.00; vendedor 504; origen - | OK        |

## Caso 5: cambio sin usuario de sesión

Sin usuario declarado, como un script de mantenimiento, el precio de la segunda publicación pasa a 9000.00. El evento se registra sin usuario del sistema, y el login identifica igual quién se conectó.

| Comprobación                   | Valor                                            | Resultado |
| ------------------------------ | ------------------------------------------------ | --------- |
| Evento sin usuario del sistema | U precio: 8800.00 a 9000.00; usuario -; origen - | OK        |
| Login y fecha                  | 1 evento; login real; fecha del paso             | OK        |

## Caso 6: cambio bajo `EXECUTE AS USER`

Con el vendedor declarado en la sesión, un usuario de base de datos sin login, que solo tiene `SELECT` y `UPDATE` sobre `PUBLICACION`, cambia el precio de la tercera publicación a 13000.00. El evento se registra igual, aunque ese usuario no tiene permisos sobre `AUDITORIA` ni sobre `usp_RegistrarAuditoria`, por el encadenamiento de propiedad: el trigger, el procedimiento y la tabla son del mismo dueño. `login_bd` guarda el login real (`ORIGINAL_LOGIN()`), aunque `SUSER_SNAME()` cambie bajo la suplantación.

| Comprobación                   | Valor                                                                                                      | Resultado |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------- | --------- |
| Permisos del usuario sin login | UPDATE en PUBLICACION 1; SELECT en AUDITORIA 0; INSERT en AUDITORIA 0; EXECUTE en usp_RegistrarAuditoria 0 | OK        |
| Error del cambio de precio     | sin error                                                                                                  | OK        |
| SUSER_SNAME() bajo EXECUTE AS  | distinto del login real                                                                                    | OK        |
| Evento                         | U precio: 13750.00 a 13000.00; vendedor 504; origen -                                                      | OK        |
| Login y fecha                  | 1 evento; login real; fecha del paso                                                                       | OK        |

## Caso 7: cambio de precio revertido

Dentro de una transacción, el precio de la primera publicación pasa a 18000.00. El evento se ve dentro de la transacción, y el `ROLLBACK` lo deshace junto con el cambio. El número de evento se consumió, pero no quedó ninguna fila.

| Comprobación                | Valor                                                 | Resultado |
| --------------------------- | ----------------------------------------------------- | --------- |
| Dentro de la transacción    | U precio: 17600.00 a 18000.00; vendedor 504; origen - | OK        |
| Después del ROLLBACK        | sin eventos                                           | OK        |
| Precio después del ROLLBACK | 17600.00                                              | OK        |
| IDENTITY de AUDITORIA       | avanzó sin filas nuevas                               | OK        |

## Caso 8: precio 0

El precio debe ser mayor que cero (RN10). La restricción `chk_publicacion_precio` rechaza la sentencia antes de que corran los triggers, y no queda ningún evento.

| Comprobación | Valor                      | Resultado |
| ------------ | -------------------------- | --------- |
| Error        | 547 chk_publicacion_precio | OK        |
| Eventos      | sin eventos                | OK        |

## Caso 9: cambio de precio y de vendedor a un cliente

Una sentencia cambia el precio de la primera publicación a 20000.00 y le asigna como vendedor al cliente, que no puede publicar (RN10). `trg_PUBLICACION_Vendedor` la rechaza con el error 50271, y la sentencia se revierte entera: ni el precio ni el vendedor cambian, y no queda ningún evento.

| Comprobación                  | Valor                  | Resultado |
| ----------------------------- | ---------------------- | --------- |
| Error                         | 50271                  | OK        |
| Eventos                       | sin eventos            | OK        |
| Precio y vendedor sin cambios | 17600.00; vendedor 504 | OK        |

## Caso 10: transacciones abiertas

Después de cada llamada a un procedimiento, de la creación de las publicaciones, del cambio bajo `EXECUTE AS`, de las sentencias que fallan y del `ROLLBACK` del caso 7, no quedó ninguna transacción abierta (0).

## Conclusión

`trg_PUBLICACION_AuditoriaPrecio` deja un evento por cada fila cuyo precio cambia, también en una sentencia de varias filas, con el usuario de la sesión o NULL si no hay uno, y siempre con el login real, incluso bajo suplantación. Los `UPDATE` que no cambian el precio no dejan eventos, y un cambio revertido o rechazado (547 y 50271) tampoco. La limpieza dejó la base igual, sin el usuario sin login del caso 6, y los triggers que deshabilita mientras borra quedaron habilitados.
