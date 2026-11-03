# Demostración: usuario de sesión y registro de la auditoría

Prueba los objetos que comparten los triggers de auditoría: `usp_EstablecerUsuarioSesion`, que declara qué usuario del sistema opera en la sesión; `fn_UsuarioSesion`, que lo devuelve; y `usp_RegistrarAuditoria`, que escribe los eventos en `AUDITORIA` y `AUDITORIA_DETALLE` y solo puede llamarse desde un trigger. Cada trigger se prueba en la demostración de su carpeta. La demostración trabaja con clientes propios y los borra al terminar.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **9 de 9** comprobaciones correctas

## Resumen

| Caso | Qué se prueba                                        | Comprobaciones | Resultado |
| ---- | ---------------------------------------------------- | -------------- | --------- |
| 1    | Sesión sin usuario declarado                         | 1              | OK        |
| 2    | Usuario activo                                       | 1              | OK        |
| 3    | Usuario inexistente y usuario dado de baja           | 3              | OK        |
| 4    | Limpiar el usuario con NULL                          | 1              | OK        |
| 5    | `usp_RegistrarAuditoria` llamado fuera de un trigger | 2              | OK        |
| 6    | Transacciones abiertas tras cada llamada             | 1              | OK        |

La demostración usa un cliente activo y un cliente dado de baja.

## Caso 1: sesión sin usuario declarado

En una sesión nueva nadie declaró un usuario, y `fn_UsuarioSesion()` devuelve NULL. Así quedan los eventos que hace un script de mantenimiento: sin usuario del sistema, aunque con el login de quien se conectó.

| Comprobación                             | Valor | Resultado |
| ---------------------------------------- | ----- | --------- |
| fn_UsuarioSesion() sin usuario declarado | NULL  | OK        |

## Caso 2: usuario activo

`usp_EstablecerUsuarioSesion` declara al cliente activo, y la función lo devuelve.

| Comprobación                             | Valor       | Resultado |
| ---------------------------------------- | ----------- | --------- |
| fn_UsuarioSesion() con el usuario activo | cliente 501 | OK        |

## Caso 3: usuario inexistente y usuario dado de baja

Se intenta declarar un usuario inexistente y después al cliente dado de baja. El procedimiento rechaza los dos con el error 50401, y la sesión conserva el usuario del caso 2: un intento fallido no la deja sin usuario.

| Comprobación                          | Valor       | Resultado |
| ------------------------------------- | ----------- | --------- |
| Usuario inexistente                   | 50401       | OK        |
| Usuario dado de baja                  | 50401       | OK        |
| Sigue declarado el usuario del caso 2 | cliente 501 | OK        |

## Caso 4: limpiar con NULL

`usp_EstablecerUsuarioSesion` con NULL borra el usuario declarado, y la función vuelve a devolver NULL.

| Comprobación                          | Valor | Resultado |
| ------------------------------------- | ----- | --------- |
| fn_UsuarioSesion() después de limpiar | NULL  | OK        |

## Caso 5: `usp_RegistrarAuditoria` fuera de un trigger

Se llama al procedimiento directamente, con un cambio inventado del email del cliente. Como no corre dentro de un trigger, falla con el error 50402 antes de escribir: nadie puede cargar un evento falso a mano.

| Comprobación    | Valor | Resultado |
| --------------- | ----- | --------- |
| Llamada directa | 50402 | OK        |
| Eventos nuevos  | 0     | OK        |

## Caso 6: transacciones abiertas

Después de cada llamada a un procedimiento, también de las que fallaron, no quedó ninguna transacción abierta (0).

## Conclusión

Sin un usuario declarado, la auditoría registra NULL como usuario del sistema. `usp_EstablecerUsuarioSesion` solo acepta usuarios existentes y activos (50401), y un rechazo no cambia el usuario de la sesión. `usp_RegistrarAuditoria` solo escribe desde un trigger (50402), y ninguna llamada dejó una transacción abierta. La limpieza dejó la base igual, y los triggers que deshabilita mientras borra quedaron habilitados.
