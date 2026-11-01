/* ============================================================================
   Sistema de venta de libros - Triggers de consistencia

   Motor:      SQL Server 2012 o superior (T-SQL)
   Uso:        abrir este archivo en SSMS y ejecutarlo completo (F5).

   - Hacen cumplir las reglas que dependen de otras filas o de otras tablas, aunque
     los datos se modifiquen fuera de los procedimientos almacenados.
   - Orden de instalación: sistema-venta-libros.sql, datos_prueba.sql,
     calcular_descuento_pedido/script.sql, este script y registrar_venta/script.sql.
   - No forman parte de sistema-venta-libros.sql porque controlan el ciclo de vida
     de las filas, y los datos históricos no pasaron por ese ciclo: se cargan con
     pedidos Entregados y pagos Aprobados. Por eso se instalan después de la carga.
   - dbo.fn_StockLibre la crea registrar_venta/script.sql, que se ejecuta después.
     No importa: el nombre se resuelve al ejecutarse el trigger.
   - La cadena pago, pedido y publicación necesita la opción de servidor
     nested triggers en 1, su valor por defecto. Con 0 se corta sin dar error.
   - Se puede ejecutar varias veces: cada trigger se elimina y se vuelve a crear.
   ============================================================================ */

USE [sistema-venta-libros];
GO

-- Quedan registradas en cada trigger. Sin QUOTED_IDENTIFIER, el UPDATE sobre
-- PUBLICACION falla con el error 1934, porque la tabla tiene un índice filtrado.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- dbo.fn_TotalPedido se crea en calcular_descuento_pedido/script.sql.
-- SET NOEXEC ON hace que los lotes siguientes se compilen sin ejecutarse.
IF OBJECT_ID(N'dbo.fn_TotalPedido', N'FN') IS NULL
   OR NOT EXISTS (SELECT 1 FROM dbo.PEDIDO)
BEGIN
    RAISERROR(N'Faltan datos: ejecutar antes datos_prueba.sql y calcular_descuento_pedido/script.sql. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Un trigger AFTER lee después de escribir, lo contrario de la regla de los
-- procedimientos: primero bloquear y validar, después escribir. Con el aislamiento
-- por defecto, dbo.fn_StockLibre y las lecturas de PAGO esperan las filas sin
-- confirmar de otra sesión, y dos sesiones pueden bloquearse mutuamente. Con esta
-- opción, esas lecturas usan la última versión confirmada y no esperan.
-- ROLLBACK IMMEDIATE revierte las transacciones abiertas en otras conexiones de la
-- base: conviene ejecutar el script sin actividad.
IF (SELECT is_read_committed_snapshot_on FROM sys.databases WHERE database_id = DB_ID()) = 0
    ALTER DATABASE [sistema-venta-libros] SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO

-- ----------------------------------------------------------------------------
-- 1. Ciclo de venta
--
-- Forman una cadena: aprobar un pago confirma su pedido, confirmar un pedido
-- descuenta el stock y el stock en cero oculta la publicación. Van juntos, porque
-- trg_PEDIDO_Transicion impide llegar al descuento sin un pago aprobado.
-- ----------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.trg_PAGO_ConfirmarPedido', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PAGO_ConfirmarPedido;
GO

-- Al aprobarse un pago, confirma su pedido si está Pendiente y hay stock libre para
-- todos sus renglones (RN19, RN37). usp_RegistrarVenta comprueba lo mismo antes de
-- escribir, para no perder el rastro del cobro: este control cubre el DML directo.
CREATE TRIGGER dbo.trg_PAGO_ConfirmarPedido
ON dbo.PAGO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Pedidos TABLE (pedido_id INT NOT NULL PRIMARY KEY);

    INSERT INTO @Pedidos (pedido_id)
    SELECT DISTINCT I.pedido_id
    FROM inserted AS I
    INNER JOIN deleted AS D
        ON D.pago_id = I.pago_id
    INNER JOIN dbo.PAGO_ESTADO AS NUEVO
        ON NUEVO.pago_estado_id = I.pago_estado_id
    INNER JOIN dbo.PAGO_ESTADO AS ANTERIOR
        ON ANTERIOR.pago_estado_id = D.pago_estado_id
    WHERE NUEVO.nombre = 'Aprobado'
      AND ANTERIOR.nombre <> 'Aprobado';

    IF NOT EXISTS (SELECT 1 FROM @Pedidos)
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM @Pedidos AS X
        INNER JOIN dbo.PEDIDO AS P
            ON P.pedido_id = X.pedido_id
        INNER JOIN dbo.PEDIDO_ESTADO AS PE
            ON PE.pedido_estado_id = P.pedido_estado_id
        WHERE PE.nombre <> 'Pendiente'
    )
        THROW 50201, 'trg_PAGO_ConfirmarPedido: pago aprobado con el pedido fuera de Pendiente (RN19, RN37).', 1;

    IF EXISTS (
        SELECT 1
        FROM @Pedidos AS X
        INNER JOIN dbo.PEDIDO_DETALLE AS PD
            ON PD.pedido_id = X.pedido_id
        WHERE dbo.fn_StockLibre(PD.publicacion_id, PD.pedido_id) < PD.cantidad
    )
        THROW 50202, 'trg_PAGO_ConfirmarPedido: pago aprobado sin stock libre para todo el pedido (RN19, RN37).', 1;

    UPDATE P
    SET P.pedido_estado_id = PE.pedido_estado_id
    FROM dbo.PEDIDO AS P
    INNER JOIN @Pedidos AS X
        ON X.pedido_id = P.pedido_id
    INNER JOIN dbo.PEDIDO_ESTADO AS PE
        ON PE.nombre = 'Confirmado';
END;
GO

IF OBJECT_ID(N'dbo.trg_PEDIDO_DescontarStock', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PEDIDO_DescontarStock;
GO

-- Al confirmarse un pedido, descuenta del stock la cantidad vendida (RN14). Suma por
-- publicación porque UPDATE ... FROM aplica un solo cruce por fila: dos pedidos
-- confirmados en una sentencia descontarían una sola vez. FORCESEEK evita un
-- recorrido de PUBLICACION, que chocaría con las filas tomadas por otros pedidos.
CREATE TRIGGER dbo.trg_PEDIDO_DescontarStock
ON dbo.PEDIDO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(pedido_estado_id)
        RETURN;

    UPDATE PUB
    SET PUB.stock = PUB.stock - VENDIDO.cantidad
    FROM dbo.PUBLICACION AS PUB WITH (ROWLOCK, FORCESEEK)
    INNER JOIN (
        SELECT PD.publicacion_id, SUM(PD.cantidad) AS cantidad
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.pedido_id = I.pedido_id
        INNER JOIN dbo.PEDIDO_ESTADO AS NUEVO
            ON NUEVO.pedido_estado_id = I.pedido_estado_id
        INNER JOIN dbo.PEDIDO_ESTADO AS ANTERIOR
            ON ANTERIOR.pedido_estado_id = D.pedido_estado_id
        INNER JOIN dbo.PEDIDO_DETALLE AS PD
            ON PD.pedido_id = I.pedido_id
        WHERE NUEVO.nombre = 'Confirmado'
          AND ANTERIOR.nombre = 'Pendiente'
        GROUP BY PD.publicacion_id
    ) AS VENDIDO
        ON VENDIDO.publicacion_id = PUB.publicacion_id;
END;
GO

IF OBJECT_ID(N'dbo.trg_PUBLICACION_Agotada', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PUBLICACION_Agotada;
GO

-- Una publicación sin stock deja de estar disponible (RN12, RN14). Reponer stock no
-- la reactiva: disponible no distingue una publicación agotada de una pausada, así
-- que reanudarla es una decisión del vendedor.
CREATE TRIGGER dbo.trg_PUBLICACION_Agotada
ON dbo.PUBLICACION
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE PUB
    SET PUB.disponible = 0
    FROM dbo.PUBLICACION AS PUB WITH (ROWLOCK, FORCESEEK)
    INNER JOIN inserted AS I
        ON I.publicacion_id = PUB.publicacion_id
    WHERE I.stock = 0
      AND I.disponible = 1;
END;
GO

IF OBJECT_ID(N'dbo.trg_PEDIDO_Transicion', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PEDIDO_Transicion;
GO

-- Protege el ciclo del pedido y sus datos copiados (RN19, RN20, RN27). Los
-- procedimientos controlan el estado por su cuenta: este control cubre el DML directo.
-- fecha_pedido queda libre porque la demostración la mueve para simular el tiempo.
-- Cancelar un pedido no cancela sus pagos: el rastro del cobro lo maneja RN37.
CREATE TRIGGER dbo.trg_PEDIDO_Transicion
ON dbo.PEDIDO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Los CHECK no admiten texto vacío en las columnas opcionales, así que COALESCE
    -- no confunde NULL con un valor. BIN2 hace que un cambio de mayúsculas cuente.
    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.pedido_id = I.pedido_id
        WHERE I.usuario_id <> D.usuario_id
           OR I.ciudad_id <> D.ciudad_id
           OR I.envio_altura <> D.envio_altura
           OR I.envio_calle <> D.envio_calle COLLATE Latin1_General_BIN2
           OR I.envio_codigo_postal <> D.envio_codigo_postal COLLATE Latin1_General_BIN2
           OR COALESCE(I.envio_piso, '') <> COALESCE(D.envio_piso, '') COLLATE Latin1_General_BIN2
           OR COALESCE(I.envio_departamento, '') <> COALESCE(D.envio_departamento, '') COLLATE Latin1_General_BIN2
           OR COALESCE(I.envio_referencia, '') <> COALESCE(D.envio_referencia, '') COLLATE Latin1_General_BIN2
    )
        THROW 50214, 'trg_PEDIDO_Transicion: el cliente y la direccion de un pedido no cambian (RN27).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.pedido_id = I.pedido_id
        INNER JOIN dbo.PEDIDO_ESTADO AS NUEVO
            ON NUEVO.pedido_estado_id = I.pedido_estado_id
        INNER JOIN dbo.PEDIDO_ESTADO AS ANTERIOR
            ON ANTERIOR.pedido_estado_id = D.pedido_estado_id
        WHERE I.pedido_estado_id <> D.pedido_estado_id
          AND NOT (
                  (ANTERIOR.nombre = 'Pendiente' AND NUEVO.nombre IN ('Confirmado', 'Cancelado'))
               OR (ANTERIOR.nombre = 'Confirmado' AND NUEVO.nombre = 'Entregado')
              )
    )
        THROW 50215, 'trg_PEDIDO_Transicion: cambio de estado no permitido (RN19, RN20).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.pedido_id = I.pedido_id
        INNER JOIN dbo.PEDIDO_ESTADO AS NUEVO
            ON NUEVO.pedido_estado_id = I.pedido_estado_id
        WHERE I.pedido_estado_id <> D.pedido_estado_id
          AND NUEVO.nombre = 'Confirmado'
          AND NOT EXISTS (
                  SELECT 1
                  FROM dbo.PAGO AS PG
                  INNER JOIN dbo.PAGO_ESTADO AS PGE
                      ON PGE.pago_estado_id = PG.pago_estado_id
                  WHERE PG.pedido_id = I.pedido_id
                    AND PGE.nombre = 'Aprobado'
              )
    )
        THROW 50216, 'trg_PEDIDO_Transicion: un pedido se confirma solo con un pago aprobado (RN19).', 1;
END;
GO

-- Corre primero para que el error no dependa del orden de los triggers: si no,
-- trg_PEDIDO_DescontarStock puede fallar antes con el 547 de stock negativo.
EXEC sp_settriggerorder @triggername = N'dbo.trg_PEDIDO_Transicion', @order = N'First', @stmttype = N'UPDATE';
GO

-- ----------------------------------------------------------------------------
-- 2. Pagos y renglones
--
-- Protegen lo ya cobrado y el historial de pagos. Ningún procedimiento modifica
-- renglones ni borra pagos: para cambiar un carrito se crea otro pedido.
-- ----------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.trg_PAGO_Transicion', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PAGO_Transicion;
GO

-- Protege el ciclo del pago y sus datos (RN22, RN24, RN25). usp_RegistrarVenta rechaza
-- por su cuenta un pago ya procesado, porque lee el estado con el bloqueo tomado: este
-- control cubre el DML directo. fecha_creacion queda libre porque la demostración la
-- mueve para simular el tiempo. Un pago Cancelado puede tener fecha_pago: es el rastro
-- de un cobro sin venta (RN37).
CREATE TRIGGER dbo.trg_PAGO_Transicion
ON dbo.PAGO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.pago_id = I.pago_id
        WHERE I.pedido_id <> D.pedido_id
           OR I.importe <> D.importe
           OR I.pago_metodo_id <> D.pago_metodo_id
    )
        THROW 50221, 'trg_PAGO_Transicion: el pedido, el importe y el metodo de un pago no cambian (RN22).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.pago_id = I.pago_id
        INNER JOIN dbo.PAGO_ESTADO AS ANTERIOR
            ON ANTERIOR.pago_estado_id = D.pago_estado_id
        WHERE ANTERIOR.nombre <> 'Pendiente'
          AND (
                  I.pago_estado_id <> D.pago_estado_id
               OR I.fecha_pago <> D.fecha_pago
               OR (I.fecha_pago IS NULL AND D.fecha_pago IS NOT NULL)
               OR (I.fecha_pago IS NOT NULL AND D.fecha_pago IS NULL)
              )
    )
        THROW 50222, 'trg_PAGO_Transicion: un pago ya procesado no cambia (RN24, RN25).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.PAGO_ESTADO AS NUEVO
            ON NUEVO.pago_estado_id = I.pago_estado_id
        WHERE (NUEVO.nombre = 'Aprobado' AND I.fecha_pago IS NULL)
           OR (NUEVO.nombre IN ('Pendiente', 'Rechazado') AND I.fecha_pago IS NOT NULL)
    )
        THROW 50223, 'trg_PAGO_Transicion: la fecha de pago no corresponde al estado del pago (RN25).', 1;
END;
GO

-- Corre primero para rechazar antes de que trg_PAGO_ConfirmarPedido propague el cambio.
EXEC sp_settriggerorder @triggername = N'dbo.trg_PAGO_Transicion', @order = N'First', @stmttype = N'UPDATE';
GO

IF OBJECT_ID(N'dbo.trg_DETALLE_Congelado', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_DETALLE_Congelado;
GO

-- Los renglones no cambian ni se borran: alterarían un total ya cobrado o el precio
-- histórico, y un pedido podría quedarse sin renglones (RN15, RN17, RN22, RN26).
CREATE TRIGGER dbo.trg_DETALLE_Congelado
ON dbo.PEDIDO_DETALLE
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- El trigger también se dispara con una sentencia que no afecta filas.
    IF NOT EXISTS (SELECT 1 FROM deleted)
        RETURN;

    THROW 50251, 'trg_DETALLE_Congelado: los renglones de un pedido no cambian ni se borran (RN15, RN17, RN22, RN26).', 1;
END;
GO

IF OBJECT_ID(N'dbo.trg_PAGO_Alta', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PAGO_Alta;
GO

-- Un pago nace Pendiente, por el total de un pedido Pendiente con la reserva vigente
-- y sin otro pago abierto (RN22, RN24, RN35). usp_IniciarPago valida lo mismo antes de
-- escribir, para respetar el orden de bloqueos: este control cubre el DML directo.
-- El total de un pedido sin renglones es 0, así que su pago siempre se rechaza.
CREATE TRIGGER dbo.trg_PAGO_Alta
ON dbo.PAGO
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.PAGO_ESTADO AS PGE
            ON PGE.pago_estado_id = I.pago_estado_id
        WHERE PGE.nombre <> 'Pendiente'
           OR I.fecha_pago IS NOT NULL
    )
        THROW 50231, 'trg_PAGO_Alta: un pago nace Pendiente y sin fecha de pago (RN24, RN25).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.PEDIDO AS P
            ON P.pedido_id = I.pedido_id
        INNER JOIN dbo.PEDIDO_ESTADO AS PE
            ON PE.pedido_estado_id = P.pedido_estado_id
        WHERE PE.nombre <> 'Pendiente'
    )
        THROW 50232, 'trg_PAGO_Alta: el pedido no esta Pendiente (RN24).', 1;

    -- dbo.PAGO ya incluye las filas nuevas, así que también cuenta las de esta sentencia.
    IF EXISTS (
        SELECT 1
        FROM dbo.PAGO AS PG
        INNER JOIN dbo.PAGO_ESTADO AS PGE
            ON PGE.pago_estado_id = PG.pago_estado_id
        WHERE PG.pedido_id IN (SELECT pedido_id FROM inserted)
          AND PGE.nombre IN ('Pendiente', 'Aprobado')
        GROUP BY PG.pedido_id
        HAVING COUNT(*) > 1
    )
        THROW 50233, 'trg_PAGO_Alta: el pedido ya tiene un pago pendiente o aprobado (RN24).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        WHERE I.importe <> dbo.fn_TotalPedido(I.pedido_id)
    )
        THROW 50234, 'trg_PAGO_Alta: el importe no coincide con el total del pedido (RN22).', 1;

    -- Mismo plazo que dbo.fn_VencimientoReserva sin un pago Pendiente. No se usa esa
    -- función porque aquí ya ve el pago nuevo como Pendiente y devolvería un plazo
    -- nuevo: la reserva nunca vencería. Los controles anteriores aseguran que no hay
    -- otro pago abierto.
    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.PEDIDO AS P
            ON P.pedido_id = I.pedido_id
        WHERE I.fecha_creacion > DATEADD(MINUTE, 15, P.fecha_pedido)
           OR P.fecha_pedido > I.fecha_creacion   -- fecha futura: no reserva
    )
        THROW 50235, 'trg_PAGO_Alta: la reserva del pedido vencio (RN35).', 1;
END;
GO

IF OBJECT_ID(N'dbo.trg_PAGO_SinBorrado', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PAGO_SinBorrado;
GO

-- Los pagos no se borran: un pedido confirmado se quedaría sin su pago, y se perdería
-- el historial de intentos (RN29).
CREATE TRIGGER dbo.trg_PAGO_SinBorrado
ON dbo.PAGO
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- El trigger también se dispara con una sentencia que no afecta filas.
    IF NOT EXISTS (SELECT 1 FROM deleted)
        RETURN;

    THROW 50241, 'trg_PAGO_SinBorrado: los pagos no se borran (RN29).', 1;
END;
GO

-- ----------------------------------------------------------------------------
-- 3. Altas e historial
--
-- Cubren las altas hechas fuera de los procedimientos y evitan reescribir ventas
-- pasadas. RN08 y RN15 no se pueden exigir en el alta, porque la fila padre debe
-- existir primero. En su lugar, se impide usar esa fila: un libro sin autor no se
-- publica (50272), y un pedido sin renglones no se paga (50234, en trg_PAGO_Alta).
-- ----------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.trg_PUBLICACION_Historial', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PUBLICACION_Historial;
GO

-- Una publicación con renglones conserva su vendedor, su libro y su condición:
-- cambiarlos reescribiría comprobantes y reportes de ventas pasadas. Una baja no se
-- revierte (RN28). El precio y el stock quedan libres: cada renglón guarda su precio.
CREATE TRIGGER dbo.trg_PUBLICACION_Historial
ON dbo.PUBLICACION
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT (UPDATE(usuario_id) OR UPDATE(libro_id) OR UPDATE(condicion_id) OR UPDATE(fecha_eliminacion))
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.publicacion_id = I.publicacion_id
        WHERE (
                  I.usuario_id <> D.usuario_id
               OR I.libro_id <> D.libro_id
               OR I.condicion_id <> D.condicion_id
              )
          AND EXISTS (
                  SELECT 1
                  FROM dbo.PEDIDO_DETALLE AS PD
                  WHERE PD.publicacion_id = I.publicacion_id
              )
    )
        THROW 50274, 'trg_PUBLICACION_Historial: una publicacion con pedidos no cambia de vendedor, libro ni condicion (RN28).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.publicacion_id = I.publicacion_id
        WHERE I.fecha_eliminacion IS NULL
          AND D.fecha_eliminacion IS NOT NULL
    )
        THROW 50275, 'trg_PUBLICACION_Historial: la baja de una publicacion no se revierte (RN28).', 1;
END;
GO

IF OBJECT_ID(N'dbo.trg_PEDIDO_Alta', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PEDIDO_Alta;
GO

-- Un pedido nace Pendiente, de un cliente activo y con la copia de una de sus
-- direcciones (RN04, RN18, RN19, RN28). usp_CrearPedido valida al cliente y la dirección
-- antes de abrir la transacción, con @DireccionId. Este control solo ve la copia y
-- cubre el DML directo. Revisa únicamente el alta: después, el cliente puede editar o
-- borrar esa dirección, y el pedido conserva su copia (RN27).
CREATE TRIGGER dbo.trg_PEDIDO_Alta
ON dbo.PEDIDO
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.PEDIDO_ESTADO AS PE
            ON PE.pedido_estado_id = I.pedido_estado_id
        WHERE PE.nombre <> 'Pendiente'
    )
        THROW 50211, 'trg_PEDIDO_Alta: un pedido nace Pendiente (RN19).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.USUARIO AS U
            ON U.usuario_id = I.usuario_id
        INNER JOIN dbo.USUARIO_ROL AS UR
            ON UR.usuario_rol_id = U.usuario_rol_id
        WHERE UR.nombre <> 'Cliente'
           OR U.fecha_eliminacion IS NOT NULL
    )
        THROW 50212, 'trg_PEDIDO_Alta: el usuario no es un cliente activo (RN04, RN28).', 1;

    -- Los CHECK no admiten texto vacío en piso ni departamento, así que COALESCE no
    -- confunde NULL con un valor.
    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        WHERE NOT EXISTS (
                  SELECT 1
                  FROM dbo.DIRECCION AS D
                  WHERE D.usuario_id = I.usuario_id
                    AND D.ciudad_id = I.ciudad_id
                    AND D.calle = I.envio_calle
                    AND D.altura = I.envio_altura
                    AND D.codigo_postal = I.envio_codigo_postal
                    AND COALESCE(D.piso, '') = COALESCE(I.envio_piso, '')
                    AND COALESCE(D.departamento, '') = COALESCE(I.envio_departamento, '')
              )
    )
        THROW 50213, 'trg_PEDIDO_Alta: la direccion no coincide con una del cliente (RN18).', 1;
END;
GO

IF OBJECT_ID(N'dbo.trg_PUBLICACION_Vendedor', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_PUBLICACION_Vendedor;
GO

-- Solo un vendedor publica, y solo libros con autor (RN08, RN10). Una publicación
-- disponible necesita un vendedor activo (RN12). Esa condición exige disponible = 1
-- porque retirar una publicación de un vendedor dado de baja sí es válido: lo hace
-- trg_PUBLICACION_Agotada, que dispara este trigger con disponible = 0.
CREATE TRIGGER dbo.trg_PUBLICACION_Vendedor
ON dbo.PUBLICACION
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT (UPDATE(usuario_id) OR UPDATE(libro_id) OR UPDATE(disponible))
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.USUARIO AS U
            ON U.usuario_id = I.usuario_id
        INNER JOIN dbo.USUARIO_ROL AS UR
            ON UR.usuario_rol_id = U.usuario_rol_id
        WHERE UR.nombre <> 'Vendedor'
    )
        THROW 50271, 'trg_PUBLICACION_Vendedor: solo un vendedor puede publicar (RN10).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        WHERE NOT EXISTS (
                  SELECT 1
                  FROM dbo.AUTOR_LIBRO AS AL
                  WHERE AL.libro_id = I.libro_id
              )
    )
        THROW 50272, 'trg_PUBLICACION_Vendedor: el libro no tiene autor (RN08).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.USUARIO AS U
            ON U.usuario_id = I.usuario_id
        WHERE I.disponible = 1
          AND U.fecha_eliminacion IS NOT NULL
    )
        THROW 50273, 'trg_PUBLICACION_Vendedor: el vendedor esta dado de baja (RN12).', 1;
END;
GO

IF OBJECT_ID(N'dbo.trg_USUARIO_CambioRol', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_USUARIO_CambioRol;
GO

-- Un usuario con pedidos o publicaciones conserva su rol: si no, quedarían pedidos de
-- alguien que no es cliente o publicaciones de alguien que no es vendedor (RN04, RN10).
CREATE TRIGGER dbo.trg_USUARIO_CambioRol
ON dbo.USUARIO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(usuario_rol_id)
        RETURN;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN deleted AS D
            ON D.usuario_id = I.usuario_id
        WHERE I.usuario_rol_id <> D.usuario_rol_id
          AND (
                  EXISTS (SELECT 1 FROM dbo.PEDIDO AS P WHERE P.usuario_id = I.usuario_id)
               OR EXISTS (SELECT 1 FROM dbo.PUBLICACION AS PUB WHERE PUB.usuario_id = I.usuario_id)
              )
    )
        THROW 50281, 'trg_USUARIO_CambioRol: un usuario con pedidos o publicaciones no cambia de rol (RN04, RN10).', 1;
END;
GO

-- ----------------------------------------------------------------------------
-- 4. Bajas y renglones nuevos
--
-- La baja de un vendedor retira sus publicaciones, un libro conserva al menos un
-- autor y un renglón nuevo cumple las mismas condiciones que exige usp_CrearPedido.
-- ----------------------------------------------------------------------------

IF OBJECT_ID(N'dbo.trg_USUARIO_Baja', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_USUARIO_Baja;
GO

-- La baja de un vendedor da de baja sus publicaciones vigentes, también las pausadas
-- (RN12, RN28). Usa la fecha del usuario, o la de alta de la publicación si es
-- posterior: hay publicaciones con fecha_creacion futura, y chk_publicacion_fechas
-- rechazaría una baja anterior al alta. Reactivar al usuario no las recupera, porque
-- la baja de una publicación no se revierte.
CREATE TRIGGER dbo.trg_USUARIO_Baja
ON dbo.USUARIO
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(fecha_eliminacion)
        RETURN;

    UPDATE PUB
    SET PUB.disponible = 0,
        PUB.fecha_eliminacion = CASE
                                    WHEN PUB.fecha_creacion > I.fecha_eliminacion THEN PUB.fecha_creacion
                                    ELSE I.fecha_eliminacion
                                END
    FROM dbo.PUBLICACION AS PUB WITH (ROWLOCK, FORCESEEK)
    INNER JOIN inserted AS I
        ON I.usuario_id = PUB.usuario_id
    INNER JOIN deleted AS D
        ON D.usuario_id = I.usuario_id
    WHERE I.fecha_eliminacion IS NOT NULL
      AND D.fecha_eliminacion IS NULL
      AND PUB.fecha_eliminacion IS NULL;
END;
GO

IF OBJECT_ID(N'dbo.trg_AUTOR_LIBRO_UltimoAutor', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_AUTOR_LIBRO_UltimoAutor;
GO

-- Un libro no se queda sin autores (RN08). Como borrar un libro exige borrar antes sus
-- filas de AUTOR_LIBRO, un libro mal cargado solo se puede eliminar deshabilitando
-- este trigger.
CREATE TRIGGER dbo.trg_AUTOR_LIBRO_UltimoAutor
ON dbo.AUTOR_LIBRO
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- Un UPDATE que mueve un autor a otro libro deja el libro anterior en deleted.
    IF EXISTS (
        SELECT 1
        FROM deleted AS D
        WHERE NOT EXISTS (
                  SELECT 1
                  FROM dbo.AUTOR_LIBRO AS AL
                  WHERE AL.libro_id = D.libro_id
              )
    )
        THROW 50291, 'trg_AUTOR_LIBRO_UltimoAutor: un libro no puede quedarse sin autores (RN08).', 1;
END;
GO

IF OBJECT_ID(N'dbo.trg_DETALLE_Alta', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_DETALLE_Alta;
GO

-- Un renglón nuevo va en un pedido Pendiente y sin pagos, con una publicación activa,
-- stock libre y su precio vigente (RN12, RN13, RN22, RN26). usp_CrearPedido valida lo
-- mismo antes de escribir, con las publicaciones bloqueadas: este control cubre el DML
-- directo. No revisa al vendedor: con trg_USUARIO_Baja y trg_PUBLICACION_Vendedor, una
-- publicación activa no puede ser de un vendedor dado de baja.
CREATE TRIGGER dbo.trg_DETALLE_Alta
ON dbo.PEDIDO_DETALLE
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Con un pago iniciado, un renglón más dejaría el importe distinto del total.
    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.PEDIDO AS P
            ON P.pedido_id = I.pedido_id
        INNER JOIN dbo.PEDIDO_ESTADO AS PE
            ON PE.pedido_estado_id = P.pedido_estado_id
        WHERE PE.nombre <> 'Pendiente'
           OR EXISTS (
                  SELECT 1
                  FROM dbo.PAGO AS PG
                  WHERE PG.pedido_id = I.pedido_id
              )
    )
        THROW 50261, 'trg_DETALLE_Alta: el pedido no esta Pendiente o ya tiene pagos (RN22).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.PUBLICACION AS PUB
            ON PUB.publicacion_id = I.publicacion_id
        WHERE PUB.disponible = 0
           OR PUB.fecha_eliminacion IS NOT NULL
    )
        THROW 50262, 'trg_DETALLE_Alta: la publicacion no esta disponible (RN12).', 1;

    -- Excluye su propio pedido: la fila ya está insertada y contaría como reserva.
    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        WHERE dbo.fn_StockLibre(I.publicacion_id, I.pedido_id) < I.cantidad
    )
        THROW 50263, 'trg_DETALLE_Alta: no hay stock libre suficiente (RN13).', 1;

    IF EXISTS (
        SELECT 1
        FROM inserted AS I
        INNER JOIN dbo.PUBLICACION AS PUB
            ON PUB.publicacion_id = I.publicacion_id
        WHERE I.precio_unitario <> PUB.precio
    )
        THROW 50264, 'trg_DETALLE_Alta: el precio no coincide con el vigente (RN26).', 1;
END;
GO

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
