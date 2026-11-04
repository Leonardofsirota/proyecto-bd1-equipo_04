# Demostración: auditoría del stock, la disponibilidad y la baja de las publicaciones

Prueba `trg_PUBLICACION_AuditoriaStock`, que registra los cambios del stock, de la disponibilidad y de la fecha de baja de una publicación, y su borrado. Los cambios pueden venir de un usuario o de otro trigger, como la venta que descuenta stock (RN14) o la baja de un vendedor (RN28), y el evento guarda ese origen. La demostración trabaja con usuarios, publicaciones y un pedido propios, y los borra al terminar.

**Ejecución:** 2026-11-03 · SQL Server 2025 Express · base de prueba recién cargada · **17 de 17** comprobaciones correctas

## Resumen

| Caso | Qué se prueba                                   | Comprobaciones | Resultado |
| ---- | ----------------------------------------------- | -------------- | --------- |
| 1    | El vendedor repone stock                        | 2              | OK        |
| 2    | El vendedor pausa y reanuda una publicación     | 1              | OK        |
| 3    | Venta que agota la publicación                  | 4              | OK        |
| 4    | Solo cambia el precio                           | 1              | OK        |
| 5    | El administrador da de baja a un vendedor       | 3              | OK        |
| 6    | El vendedor borra una publicación sin renglones | 2              | OK        |
| 7    | Revertir la baja de una publicación             | 3              | OK        |
| 8    | Transacciones abiertas tras cada llamada        | 1              | OK        |

Cada evento se lee `operación columna: anterior a nuevo; usuario; origen`. I es alta, U cambio y D borrado, `-` es un valor vacío, y el origen es el trigger que hizo el cambio, vacío si lo hizo una sentencia o un procedimiento. **Login y fecha** comprueba que el evento guarde el login real y una fecha dentro del paso. Salvo en el caso 6, las comprobaciones solo toman `stock`, `disponible` y `fecha_eliminacion`, porque el precio lo audita `trg_PUBLICACION_AuditoriaPrecio`.

La demostración usa un administrador, dos vendedores (A y B) y un cliente. El vendedor A publica tres libros, con stock 5, 2 y 3, y el vendedor B dos, con stock 4, uno de ellos pausado desde el alta.

## Caso 1: el vendedor repone stock

Con el vendedor A declarado en la sesión, el stock de su primera publicación pasa de 5 a 8. Es un ajuste manual, así que el evento no tiene origen. El historial de la publicación en `vw_Auditoria`:

| fecha                   | operacion | columna | valor_anterior | valor_nuevo | login_bd     | usuario_id     | origen |
| ----------------------- | --------- | ------- | -------------- | ----------- | ------------ | -------------- | ------ |
| 2026-11-03 15:31:31.270 | U         | stock   | 5              | 8           | `admin\user` | vendedor A 502 | NULL   |

| Comprobación            | Valor                                    | Resultado |
| ----------------------- | ---------------------------------------- | --------- |
| Evento de la reposición | U stock: 5 a 8; vendedor A 502; origen - | OK        |
| Login y fecha           | 1 evento; login real; fecha del paso     | OK        |

## Caso 2: el vendedor pausa y reanuda una publicación

El vendedor A pausa la misma publicación y la vuelve a activar (RN12): dos sentencias y dos eventos. Una sola comprobación toma los dos eventos, en orden:

| Orden | Evento                                        | Resultado |
| ----- | --------------------------------------------- | --------- |
| 1     | U disponible: 1 a 0; vendedor A 502; origen - | OK        |
| 2     | U disponible: 0 a 1; vendedor A 502; origen - | OK        |

## Caso 3: venta que agota la publicación

El cliente compra las 2 unidades de la segunda publicación del vendedor A, y la pasarela, sin usuario de sesión, aprueba el pago: «Venta registrada correctamente». La venta deja dos eventos, cada uno con el trigger que hizo el cambio como origen y sin usuario: `trg_PEDIDO_DescontarStock` baja el stock de 2 a 0, y `trg_PUBLICACION_Agotada` marca la publicación como no disponible porque llegó a cero (RN14).

| Comprobación                | Valor                                                          | Resultado |
| --------------------------- | -------------------------------------------------------------- | --------- |
| Error de la venta           | sin error                                                      | OK        |
| Evento del stock            | U stock: 2 a 0; usuario -; origen trg_PEDIDO_DescontarStock    | OK        |
| Evento de la disponibilidad | U disponible: 1 a 0; usuario -; origen trg_PUBLICACION_Agotada | OK        |
| Login y fecha               | 2 eventos; login real; fecha del paso                          | OK        |

## Caso 4: solo cambia el precio

El vendedor A cambia el precio de su primera publicación a 11000.00. El trigger de stock no deja eventos, porque la sentencia no toca sus columnas; el cambio lo registra `trg_PUBLICACION_AuditoriaPrecio`.

| Comprobación                        | Valor       | Resultado |
| ----------------------------------- | ----------- | --------- |
| Eventos de stock, disponible o baja | sin eventos | OK        |

## Caso 5: el administrador da de baja al vendedor B

Con su usuario declarado en la sesión, el administrador da de baja al vendedor B. `trg_USUARIO_Baja` da de baja con la misma fecha sus dos publicaciones vigentes (RN12, RN28): la activa pasa además a no disponible, y la pausada solo recibe la fecha de baja. Los eventos tienen al administrador como usuario, porque hizo la baja, y a `trg_USUARIO_Baja` como origen.

| Comprobación        | Valor                                                                                                              | Resultado |
| ------------------- | ------------------------------------------------------------------------------------------------------------------ | --------- |
| Publicación vigente | U disponible: 1 a 0, fecha_eliminacion: NULL a 2026-11-03 15:31:31.560; administrador 501; origen trg_USUARIO_Baja | OK        |
| Publicación pausada | U fecha_eliminacion: NULL a 2026-11-03 15:31:31.560; administrador 501; origen trg_USUARIO_Baja                    | OK        |
| Login y fecha       | 1 evento; login real; fecha del paso                                                                               | OK        |

## Caso 6: el vendedor borra una publicación sin renglones

El vendedor A borra su tercera publicación, que no está en ningún pedido. El evento D, con el vendedor A como usuario y sin origen, guarda la última versión de la fila: todas sus columnas como valor anterior, también el precio, y ningún valor nuevo. `fecha_eliminacion` valía NULL y no aparece.

| Columna        | Anterior                |
| -------------- | ----------------------- |
| condicion      | Nuevo                   |
| disponible     | 1                       |
| fecha_creacion | 2026-11-03 15:31:31.240 |
| libro_id       | 3                       |
| precio         | 9900.00                 |
| stock          | 3                       |
| usuario_id     | 502 (vendedor A)        |

| Comprobación              | Valor                                                    | Resultado |
| ------------------------- | -------------------------------------------------------- | --------- |
| Evento del borrado        | D con las columnas de la tabla; vendedor A 502; origen - | OK        |
| Valores nuevos del evento | 0                                                        | OK        |

## Caso 7: revertir la baja de una publicación

El administrador intenta quitar la fecha de baja de la publicación activa del vendedor B. Una baja no se revierte (RN28): `trg_PUBLICACION_Historial` rechaza la sentencia con el error 50275, se revierte entera y no queda ningún evento.

| Comprobación              | Valor                   | Resultado |
| ------------------------- | ----------------------- | --------- |
| Error                     | 50275                   | OK        |
| Eventos                   | sin eventos             | OK        |
| Fecha de baja sin cambios | 2026-11-03 15:31:31.560 | OK        |

## Caso 8: transacciones abiertas

Después de cada llamada a un procedimiento, de la creación de las publicaciones, de los procedimientos de la venta y de la sentencia que falla, no quedó ninguna transacción abierta (0).

## Conclusión

`trg_PUBLICACION_AuditoriaStock` registra los ajustes manuales con el usuario de la sesión y los cambios en cadena con el trigger que los hizo: la venta deja el descuento y la publicación agotada, y la baja de un vendedor, la baja de sus publicaciones a nombre del administrador. Un cambio solo de precio no deja eventos de stock, el borrado guarda la fila completa y un cambio rechazado (50275) no deja nada. La limpieza dejó la base igual, y los triggers que deshabilita mientras borra quedaron habilitados.
