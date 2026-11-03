# Demostración de `auditar_stock_publicacion/demostracion.sql`

- **Fecha:** 2026-11-03 15:31
- **Repetición:** 2026-11-03, enseguida y sobre la misma base, después de la demostración de `auditar_pedidos`: los mismos resultados, con los usuarios 507 a 510, las publicaciones 799 a 803 y los eventos desde el 25, en lugar de 501 a 504, 792 a 796 y desde el 1. En el caso 7, `IDENT_CURRENT` no cambió (34 y 34): ver el caso. Las corridas anteriores, sobre otra base, también dieron 17 de 17 con `filas_demo` en 0: las cuatro demostraciones de `triggers_auditoria` dos veces seguidas, antes de agregar la línea impresa del caso 7.
- **Base temporal:** `tmp_validacion_aud`, recién cargada en el orden de instalación del README (DDL, datos de prueba, `calcular_descuento_pedido/script.sql`, `triggers-consistencia.sql` y `registrar_venta/script.sql`), más los `script.sql` de `triggers_auditoria/estructura_auditoria`, `auditar_precio_publicacion`, `auditar_stock_publicacion` y `auditar_pedidos`.
- **Servidor:** Microsoft SQL Server 2025 (RTM) Express Edition (64-bit)
- **Método:** salida de `sqlcmd`, agrupada por caso. Los conteos de antes y después salen de una consulta aparte, ejecutada inmediatamente antes y después de la demostración.

## Resumen

| Comprobaciones | Correctas | Fallidas | filas_demo |
| -------------- | --------- | -------- | ---------- |
| 17             | 17        | 0        | 0          |

Tablas que escribe la demostración, antes y después de ejecutarla. El checksum es `CHECKSUM_AGG(BINARY_CHECKSUM(*))`:

| Tabla             | Filas antes | Filas después | Checksum antes | Checksum después | IDENT_CURRENT antes | IDENT_CURRENT después |
| ----------------- | ----------- | ------------- | -------------- | ---------------- | ------------------- | --------------------- |
| USUARIO           | 500         | 500           | -1321992964    | -1321992964      | 500                 | 504                   |
| DIRECCION         | 603         | 603           | -544889019     | -544889019       | 603                 | 604                   |
| PUBLICACION       | 791         | 791           | 1804080490     | 1804080490       | 791                 | 796                   |
| PEDIDO            | 600         | 600           | -2005910744    | -2005910744      | 600                 | 601                   |
| PEDIDO_DETALLE    | 1290        | 1290          | 417360875      | 417360875        | 1290                | 1291                  |
| PAGO              | 718         | 718           | -1763708289    | -1763708289      | 718                 | 719                   |
| AUDITORIA         | 0           | 0             | NULL           | NULL             | 1                   | 15                    |
| AUDITORIA_DETALLE | 0           | 0             | NULL           | NULL             | 1                   | 48                    |

`AUDITORIA` usó 15 valores, del 1 al 15 (mientras la tabla no tuvo filas, `IDENT_CURRENT` devolvía la semilla, 1). Diez son los eventos confirmados de los casos 1 a 6, entre ellos dos de los otros triggers instalados: la confirmación del pedido 601 en el caso 3 (`trg_PEDIDO_Auditoria`) y el cambio de precio del caso 4 (`trg_PUBLICACION_AuditoriaPrecio`). El 11 es del caso 7, que se revirtió sin dejar filas. Los otros cuatro, del 12 al 15, son los eventos D del borrado de las cuatro publicaciones que quedaban, en la limpieza, que después los borra junto con los demás. `AUDITORIA_DETALLE` avanza con un valor por columna registrada. `trg_PAGO_SinBorrado` y `trg_DETALLE_Congelado`, que la limpieza deshabilita dentro de su transacción, quedan habilitados (`is_disabled = 0`).

Datos de la demostración: el administrador 501, el vendedor A 502, el vendedor B 503 y el cliente 504, con la dirección 604. El vendedor A crea las publicaciones 792 (stock 5, 10000.00), 793 (stock 2, 7000.00) y 794 (stock 3, 9900.00). El vendedor B crea la 795 (stock 4, 5000.00) y la 796 (stock 4, 6000.00), pausada desde el alta. Todas son de libros con autor, en condición Nuevo.

Las comprobaciones de eventos resumen los eventos de una publicación posteriores al inicio del paso como `operación columna: anterior a nuevo; usuario; origen`, con `-` para un usuario u origen NULL. Las columnas de un evento van en orden alfabético y separadas por comas, y los eventos se separan con ` / `. Salvo en el caso 6, solo toman `stock`, `disponible` y `fecha_eliminacion`: el precio es de `trg_PUBLICACION_AuditoriaPrecio`. **Login y fecha** comprueba que todos esos eventos tengan `login_bd = ORIGINAL_LOGIN()` y una fecha entre el inicio del paso y la comprobación.

## Caso 1: el vendedor repone stock

Con el vendedor 502 declarado en la sesión, el stock de la publicación 792 pasa de 5 a 8. Es un ajuste manual: no tiene origen. El historial de la publicación en `vw_Auditoria`:

| auditoria_id | fecha                   | tabla       | operacion | registro_id | columna | valor_anterior | valor_nuevo | login_bd     | usuario_id | usuario_email                                          | origen |
| ------------ | ----------------------- | ----------- | --------- | ----------- | ------- | -------------- | ----------- | ------------ | ---------- | ------------------------------------------------------ | ------ |
| 1            | 2026-11-03 15:31:31.270 | PUBLICACION | U         | 792         | stock   | 5              | 8           | `admin\user` | 502        | demo.auditoria.auditar_stock_publicacion.2@example.com | NULL   |

| Comprobación            | Esperado                              | Obtenido                              | Resultado |
| ----------------------- | ------------------------------------- | ------------------------------------- | --------- |
| Evento de la reposición | U stock: 5 a 8; usuario 502; origen - | U stock: 5 a 8; usuario 502; origen - | OK        |
| Login y fecha           | 1 evento; login real; fecha del paso  | 1 evento; login real; fecha del paso  | OK        |

## Caso 2: el vendedor pausa y reanuda una publicación

Dos sentencias sobre la publicación 792: `disponible = 0` y `disponible = 1` (RN12). Dos eventos, en orden.

| Comprobación                  | Esperado                                                                                | Obtenido                                                                                | Resultado |
| ----------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | --------- |
| Pausa y reanudación, en orden | U disponible: 1 a 0; usuario 502; origen - / U disponible: 0 a 1; usuario 502; origen - | U disponible: 1 a 0; usuario 502; origen - / U disponible: 0 a 1; usuario 502; origen - | OK        |

## Caso 3: venta que agota la publicación

Con el cliente 504 declarado en la sesión, `usp_CrearPedido` crea el pedido 601 por las 2 unidades de la publicación 793, y `usp_IniciarPago` registra el pago 719 con tarjeta de crédito. La pasarela, sin usuario de sesión, lo aprueba con `usp_RegistrarVenta`, que devuelve `Venta registrada correctamente`. La cadena deja dos sentencias sobre la publicación: `trg_PEDIDO_DescontarStock` baja el stock de 2 a 0, y `trg_PUBLICACION_Agotada`, disparado por esa sentencia, la marca no disponible (RN14). Cada evento tiene su origen, y los dos tienen el usuario en NULL. El orden de los dos eventos depende del orden de los triggers, que no está fijado: cada columna se comprueba por separado.

| Comprobación                | Esperado                                                       | Obtenido                                                       | Resultado |
| --------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------- | --------- |
| Error de la venta           | sin error                                                      | sin error                                                      | OK        |
| Evento del stock            | U stock: 2 a 0; usuario -; origen trg_PEDIDO_DescontarStock    | U stock: 2 a 0; usuario -; origen trg_PEDIDO_DescontarStock    | OK        |
| Evento de la disponibilidad | U disponible: 1 a 0; usuario -; origen trg_PUBLICACION_Agotada | U disponible: 1 a 0; usuario -; origen trg_PUBLICACION_Agotada | OK        |
| Login y fecha               | 2 eventos; login real; fecha del paso                          | 2 eventos; login real; fecha del paso                          | OK        |

## Caso 4: solo cambia el precio

El vendedor 502 cambia el precio de la publicación 792 a 11000.00. El `SET` no menciona `stock`, `disponible` ni `fecha_eliminacion`, y el trigger sale enseguida. El cambio queda registrado por `trg_PUBLICACION_AuditoriaPrecio`.

| Comprobación                        | Esperado    | Obtenido    | Resultado |
| ----------------------------------- | ----------- | ----------- | --------- |
| Eventos de stock, disponible o baja | sin eventos | sin eventos | OK        |

## Caso 5: el administrador da de baja al vendedor B

Con el administrador 501 declarado en la sesión, la `fecha_eliminacion` del vendedor 503 pasa a `2026-11-03 15:31:31.560`. `trg_USUARIO_Baja` da de baja con esa fecha sus dos publicaciones vigentes (RN12, RN28): la 795 pasa además a no disponible, y la 796, que estaba pausada, solo cambia su fecha de baja. El usuario de los dos eventos es el administrador, que hizo la baja.

| Comprobación        | Esperado                                                                                                     | Obtenido                                                                                                     | Resultado |
| ------------------- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ | --------- |
| Publicación vigente | U disponible: 1 a 0, fecha_eliminacion: NULL a 2026-11-03 15:31:31.560; usuario 501; origen trg_USUARIO_Baja | U disponible: 1 a 0, fecha_eliminacion: NULL a 2026-11-03 15:31:31.560; usuario 501; origen trg_USUARIO_Baja | OK        |
| Publicación pausada | U fecha_eliminacion: NULL a 2026-11-03 15:31:31.560; usuario 501; origen trg_USUARIO_Baja                    | U fecha_eliminacion: NULL a 2026-11-03 15:31:31.560; usuario 501; origen trg_USUARIO_Baja                    | OK        |
| Login y fecha       | 1 evento; login real; fecha del paso                                                                         | 1 evento; login real; fecha del paso                                                                         | OK        |

## Caso 6: el vendedor borra una publicación sin renglones

El vendedor 502 borra la publicación 794. El evento D guarda la última versión de la fila: todas sus columnas como valor anterior, también el precio, y ningún valor nuevo. `fecha_eliminacion` valía NULL y no aparece. La comprobación toma las ocho columnas.

| Comprobación              | Esperado                                                                                                                                                                                                    | Obtenido                                                                                                                                                                                                    | Resultado |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| Evento del borrado        | D condicion: Nuevo a NULL, disponible: 1 a NULL, fecha_creacion: 2026-11-03 15:31:31.240 a NULL, libro_id: 3 a NULL, precio: 9900.00 a NULL, stock: 3 a NULL, usuario_id: 502 a NULL; usuario 502; origen - | D condicion: Nuevo a NULL, disponible: 1 a NULL, fecha_creacion: 2026-11-03 15:31:31.240 a NULL, libro_id: 3 a NULL, precio: 9900.00 a NULL, stock: 3 a NULL, usuario_id: 502 a NULL; usuario 502; origen - | OK        |
| Valores nuevos del evento | 0                                                                                                                                                                                                           | 0                                                                                                                                                                                                           | OK        |

## Caso 7: revertir la baja de una publicación

El administrador 501 intenta volver a NULL la `fecha_eliminacion` de la publicación 795. `trg_PUBLICACION_Historial` rechaza la sentencia con 50275 (RN28), y se revierte entera. La demostración imprime `IDENT_CURRENT de AUDITORIA antes 10, después 11`: en esta corrida, el trigger de auditoría corrió antes del error, y su evento se revirtió con la sentencia. En la repetición imprimió `antes 34, después 34`: el error llegó primero, y la auditoría no corrió. El orden de los triggers no está fijado, y en los dos casos no queda evento.

| Comprobación              | Esperado                | Obtenido                | Resultado |
| ------------------------- | ----------------------- | ----------------------- | --------- |
| Error                     | 50275                   | 50275                   | OK        |
| Eventos                   | sin eventos             | sin eventos             | OK        |
| Fecha de baja sin cambios | 2026-11-03 15:31:31.560 | 2026-11-03 15:31:31.560 | OK        |

## Caso 8: transacciones abiertas

`@Abiertas` suma `@@TRANCOUNT` después de las llamadas a `usp_EstablecerUsuarioSesion`, de la creación de las publicaciones, de los procedimientos de la venta y de la sentencia que falla.

| Comprobación           | Esperado | Obtenido | Resultado |
| ---------------------- | -------- | -------- | --------- |
| Transacciones abiertas | 0        | 0        | OK        |
