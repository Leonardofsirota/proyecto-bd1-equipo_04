USE [sistema-venta-libros];
GO

-- Demostración de los objetos compartidos de la auditoría (script.sql): el usuario de
-- sesión y el control de dbo.usp_RegistrarAuditoria. Los triggers se prueban en la
-- demostración de su carpeta. Requiere la base instalada completa, como indica el
-- README, más este script.sql.
-- Se fija QUOTED_IDENTIFIER como en los demás scripts: sqlcmd lo trae en OFF.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- No corre dentro de una transacción. Crea sus propios usuarios, y
-- #LimpiarDemoEstructura los borra antes y después, junto con los eventos de
-- auditoría que hayan generado, así que se puede ejecutar varias veces sin dejar
-- datos en la base. Lo único que no se revierte son los contadores IDENTITY.
-- #FilasDemoAuditoria dura toda la sesión: guarda las filas de la demostración para
-- que filas_demo cuente al final los eventos que hubieran quedado.
IF OBJECT_ID(N'tempdb..#FilasDemoAuditoria', N'U') IS NOT NULL
    DROP TABLE #FilasDemoAuditoria;
GO

CREATE TABLE #FilasDemoAuditoria
(
    tabla VARCHAR(128) NOT NULL,
    registro_id INT NOT NULL,
    PRIMARY KEY (tabla, registro_id)
);
GO

IF OBJECT_ID(N'tempdb..#LimpiarDemoEstructura', N'P') IS NOT NULL
    DROP PROCEDURE #LimpiarDemoEstructura;
GO

-- Borra las filas de la demostración y después sus eventos de auditoría.
-- Recoge las filas de las cuatro tablas auditadas (USUARIO, PUBLICACION, PEDIDO y
-- PAGO), aunque su trigger todavía no exista: así también se borran los eventos que
-- generen los triggers que se instalen después, incluidos los del propio DELETE.
-- Pagos y renglones no se borran en la operación normal, así que sus triggers se
-- deshabilitan solo para esta limpieza. DISABLE TRIGGER es transaccional: si algo
-- falla, XACT_ABORT revierte todo y los triggers vuelven a quedar habilitados.
CREATE PROCEDURE #LimpiarDemoEstructura
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Usuarios TABLE (usuario_id INT PRIMARY KEY);

    BEGIN TRANSACTION;

    INSERT INTO @Usuarios (usuario_id)
    SELECT usuario_id
    FROM dbo.USUARIO
    WHERE email LIKE 'demo.auditoria.estructura[_]auditoria.%@example.com';

    INSERT INTO #FilasDemoAuditoria (tabla, registro_id)
    SELECT F.tabla, F.registro_id
    FROM
    (
        SELECT 'USUARIO', U.usuario_id
        FROM @Usuarios AS U

        UNION ALL

        SELECT 'PUBLICACION', PUB.publicacion_id
        FROM dbo.PUBLICACION AS PUB
        INNER JOIN @Usuarios AS U
            ON U.usuario_id = PUB.usuario_id

        UNION ALL

        SELECT 'PEDIDO', P.pedido_id
        FROM dbo.PEDIDO AS P
        INNER JOIN @Usuarios AS U
            ON U.usuario_id = P.usuario_id

        UNION ALL

        SELECT 'PAGO', PG.pago_id
        FROM dbo.PAGO AS PG
        INNER JOIN dbo.PEDIDO AS P
            ON P.pedido_id = PG.pedido_id
        INNER JOIN @Usuarios AS U
            ON U.usuario_id = P.usuario_id
    ) AS F (tabla, registro_id)
    WHERE NOT EXISTS (
        SELECT 1
        FROM #FilasDemoAuditoria AS X
        WHERE X.tabla = F.tabla
          AND X.registro_id = F.registro_id
    );

    DISABLE TRIGGER dbo.trg_PAGO_SinBorrado ON dbo.PAGO;
    DISABLE TRIGGER dbo.trg_DETALLE_Congelado ON dbo.PEDIDO_DETALLE;

    DELETE PG
    FROM dbo.PAGO AS PG
    INNER JOIN dbo.PEDIDO AS P
        ON P.pedido_id = PG.pedido_id
    WHERE P.usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE PD
    FROM dbo.PEDIDO_DETALLE AS PD
    INNER JOIN dbo.PEDIDO AS P
        ON P.pedido_id = PD.pedido_id
    WHERE P.usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE FROM dbo.PEDIDO
    WHERE usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE FROM dbo.PUBLICACION
    WHERE usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE FROM dbo.DIRECCION
    WHERE usuario_id IN (SELECT usuario_id FROM @Usuarios);

    DELETE FROM dbo.USUARIO
    WHERE usuario_id IN (SELECT usuario_id FROM @Usuarios);

    ENABLE TRIGGER dbo.trg_DETALLE_Congelado ON dbo.PEDIDO_DETALLE;
    ENABLE TRIGGER dbo.trg_PAGO_SinBorrado ON dbo.PAGO;

    DELETE AD
    FROM dbo.AUDITORIA_DETALLE AS AD
    INNER JOIN dbo.AUDITORIA AS A
        ON A.auditoria_id = AD.auditoria_id
    INNER JOIN #FilasDemoAuditoria AS F
        ON F.tabla = A.tabla
       AND F.registro_id = A.registro_id;

    DELETE A
    FROM dbo.AUDITORIA AS A
    INNER JOIN #FilasDemoAuditoria AS F
        ON F.tabla = A.tabla
       AND F.registro_id = A.registro_id;

    COMMIT TRANSACTION;
END;
GO

-- Con XACT_ABORT en OFF, los errores provocados no cortan el lote.
SET NOCOUNT ON;
SET XACT_ABORT OFF;

EXEC #LimpiarDemoEstructura;

DECLARE @Resultados TABLE
(
    orden INT IDENTITY(1,1) PRIMARY KEY,
    caso VARCHAR(70) NOT NULL,
    esperado VARCHAR(80) NOT NULL,
    obtenido VARCHAR(80) NULL,
    resultado AS CASE WHEN obtenido = esperado THEN 'OK' ELSE 'FALLO' END
);

DECLARE @Activo INT;
DECLARE @Baja INT;
DECLARE @Inexistente INT;
DECLARE @Cambios dbo.AuditoriaCambioType;
DECLARE @Desde INT;
DECLARE @Error INT;
-- Suma @@TRANCOUNT después de cada EXEC: tiene que seguir en cero.
DECLARE @Abiertas INT = 0;

BEGIN TRY
    -- Datos propios: un cliente activo y uno dado de baja. Los carga un script, sin
    -- usuario de sesión.
    INSERT INTO dbo.USUARIO
    (
        nombre,
        apellido,
        dni,
        email,
        telefono,
        fecha_nacimiento,
        password_hash,
        fecha_eliminacion,
        usuario_rol_id
    )
    SELECT
        D.nombre,
        'Demo',
        D.dni,
        D.email,
        '3794000000',
        '1990-01-01',
        'hash-demo',
        D.fecha_eliminacion,
        UR.usuario_rol_id
    FROM
    (
        VALUES
            ('Activo', '99101101', 'demo.auditoria.estructura_auditoria.1@example.com', CAST(NULL AS DATETIME)),
            ('Baja', '99101102', 'demo.auditoria.estructura_auditoria.2@example.com', GETDATE())
    ) AS D (nombre, dni, email, fecha_eliminacion)
    INNER JOIN dbo.USUARIO_ROL AS UR
        ON UR.nombre = 'Cliente';

    SELECT @Activo = usuario_id FROM dbo.USUARIO WHERE dni = '99101101';
    SELECT @Baja = usuario_id FROM dbo.USUARIO WHERE dni = '99101102';

    -- Caso 1: en una sesión nueva, CONTEXT_INFO() es NULL
    PRINT 'Caso 1: sesión sin usuario declarado';

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('1. fn_UsuarioSesion() sin usuario declarado', 'NULL', ISNULL(CAST(dbo.fn_UsuarioSesion() AS VARCHAR(10)), 'NULL'));

    -- Caso 2
    PRINT 'Caso 2: se declara un usuario activo';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Activo;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('2. fn_UsuarioSesion() con el usuario activo', CAST(@Activo AS VARCHAR(10)), ISNULL(CAST(dbo.fn_UsuarioSesion() AS VARCHAR(10)), 'NULL'));

    -- Caso 3: un usuario que no puede actuar no se declara, y la sesión conserva el
    -- usuario anterior (RN28)
    PRINT 'Caso 3: usuario inexistente y usuario dado de baja';

    -- Se calcula justo antes de usarlo: la demostración inserta usuarios.
    SELECT @Inexistente = MAX(usuario_id) + 1 FROM dbo.USUARIO;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Inexistente;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('3. Usuario inexistente', '50401', CAST(@Error AS VARCHAR(10)));

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = @Baja;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('3. Usuario dado de baja', '50401', CAST(@Error AS VARCHAR(10))),
        ('3. Sigue declarado el usuario del caso 2', CAST(@Activo AS VARCHAR(10)), ISNULL(CAST(dbo.fn_UsuarioSesion() AS VARCHAR(10)), 'NULL'));

    -- Caso 4
    PRINT 'Caso 4: se limpia el usuario de sesión';

    EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('4. fn_UsuarioSesion() después de limpiar', 'NULL', ISNULL(CAST(dbo.fn_UsuarioSesion() AS VARCHAR(10)), 'NULL'));

    -- Caso 5: fuera de un trigger, el procedimiento registraría un cambio que no
    -- ocurrió
    PRINT 'Caso 5: usp_RegistrarAuditoria fuera de un trigger';

    INSERT INTO @Cambios (registro_id, operacion, columna, valor_anterior, valor_nuevo)
    VALUES (@Activo, 'U', 'email', 'demo.auditoria.estructura_auditoria.1@example.com', 'falso@example.com');

    SELECT @Desde = ISNULL(MAX(auditoria_id), 0) FROM dbo.AUDITORIA;

    SET @Error = NULL;
    BEGIN TRY
        EXEC dbo.usp_RegistrarAuditoria
            @Tabla = 'USUARIO',
            @Origen = NULL,
            @Cambios = @Cambios;
    END TRY
    BEGIN CATCH
        SET @Error = ERROR_NUMBER();
    END CATCH;
    SET @Abiertas = @Abiertas + @@TRANCOUNT;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES
        ('5. Llamada directa', '50402', CAST(@Error AS VARCHAR(10))),
        ('5. Eventos nuevos', '0', (SELECT CAST(COUNT(*) AS VARCHAR(10)) FROM dbo.AUDITORIA WHERE auditoria_id > @Desde));

    -- Caso 6: ninguna llamada deja una transacción abierta, tampoco las que fallaron
    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('6. Transacciones abiertas tras cada EXEC', '0', CAST(@Abiertas AS VARCHAR(10)));
END TRY
BEGIN CATCH
    -- Un error no previsto queda como FALLO: así el lote termina, se muestran los
    -- resultados y el lote siguiente limpia los datos.
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    INSERT INTO @Resultados (caso, esperado, obtenido)
    VALUES ('Error no previsto', 'ninguno', LEFT(ERROR_MESSAGE(), 80));
END CATCH;

SELECT
    caso,
    esperado,
    obtenido,
    resultado
FROM @Resultados
ORDER BY orden;

SELECT
    COUNT(*) AS comprobaciones,
    SUM(CASE WHEN resultado = 'OK' THEN 1 ELSE 0 END) AS correctas,
    SUM(CASE WHEN resultado = 'FALLO' THEN 1 ELSE 0 END) AS fallidas
FROM @Resultados;
GO

-- Lote propio: corre aunque la demostración falle. Sin los usuarios no puede quedar
-- ninguna otra fila de demostración, porque las claves foráneas lo impedirían; los
-- eventos sí, porque AUDITORIA no tiene claves foráneas, y por eso se cuentan aparte.
EXEC #LimpiarDemoEstructura;
EXEC dbo.usp_EstablecerUsuarioSesion @UsuarioId = NULL;

SELECT
    (
        SELECT COUNT(*)
        FROM dbo.USUARIO
        WHERE email LIKE 'demo.auditoria.estructura[_]auditoria.%@example.com'
    )
    + (
        SELECT COUNT(*)
        FROM dbo.AUDITORIA AS A
        INNER JOIN #FilasDemoAuditoria AS F
            ON F.tabla = A.tabla
           AND F.registro_id = A.registro_id
    ) AS filas_demo;

DROP PROCEDURE #LimpiarDemoEstructura;
DROP TABLE #FilasDemoAuditoria;
GO
