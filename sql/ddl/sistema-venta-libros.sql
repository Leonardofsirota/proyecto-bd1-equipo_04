/* ============================================================================
   Sistema de venta de libros - Creación de la base de datos (DDL)

   Motor:      SQL Server 2012 o superior (T-SQL)
   Uso:        abrir este archivo en SSMS y ejecutarlo completo (F5).
               Después se puede cargar sql/dml/datos_prueba.sql.

   - Si la base [sistema-venta-libros] ya existe, el script avisa y se detiene
     sin modificar nada.
   - La base se crea con las rutas de archivos y opciones por defecto del motor.
   - Las tablas se crean en orden de dependencia: cada una después de las
     tablas a las que hace referencia.
   - Las claves foráneas no definen reglas ON DELETE / ON UPDATE, por lo que
     usan el comportamiento por defecto (NO ACTION).
   - Los CHECK de texto comparan con DATALENGTH porque en VARCHAR "=" y LIKE pueden
     ignorar los espacios finales: 'PB ' = 'PB' es verdadero. Una clase negativa
     como '%[^0-9]%' sí los detecta, por eso esos patrones no necesitan el control.
   - Los patrones de formato fijan su intercalación con COLLATE porque la base toma
     la del servidor, y en varias de ellas [0-9] también incluye caracteres como ²:
     Latin1_General_BIN2 limita los rangos a ASCII, y Latin1_General_CI_AI hace
     que [a-z] incluya las letras acentuadas de los nombres de personas.
   ============================================================================ */

USE master;
GO

-- SET NOEXEC ON hace que los lotes siguientes se compilen sin ejecutarse.
IF DB_ID(N'sistema-venta-libros') IS NOT NULL
BEGIN
    RAISERROR(N'La base [sistema-venta-libros] ya existe. El script se detuvo sin realizar cambios.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE DATABASE [sistema-venta-libros];
GO

USE [sistema-venta-libros];
GO

-- Opciones que quedan registradas en cada tabla y que exigen los índices filtrados
-- de AUTOR y PUBLICACION. SSMS las activa por defecto; sqlcmd no activa QUOTED_IDENTIFIER.
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ----------------------------------------------------------------------------
-- 1. Catálogos
-- ----------------------------------------------------------------------------

CREATE TABLE dbo.USUARIO_ROL (
    usuario_rol_id INT IDENTITY(1,1) NOT NULL,
    nombre         VARCHAR(50)       NOT NULL,
    CONSTRAINT pk_usuario_rol         PRIMARY KEY CLUSTERED (usuario_rol_id),
    CONSTRAINT uq_usuario_rol_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_usuario_rol_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.CATEGORIA (
    categoria_id INT IDENTITY(1,1) NOT NULL,
    nombre       VARCHAR(100)      NOT NULL,
    CONSTRAINT pk_categoria         PRIMARY KEY CLUSTERED (categoria_id),
    CONSTRAINT uq_categoria_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_categoria_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.IDIOMA (
    idioma_id INT IDENTITY(1,1) NOT NULL,
    nombre    VARCHAR(50)       NOT NULL,
    CONSTRAINT pk_idioma         PRIMARY KEY CLUSTERED (idioma_id),
    CONSTRAINT uq_idioma_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_idioma_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.EDITORIAL (
    editorial_id INT IDENTITY(1,1) NOT NULL,
    nombre       VARCHAR(100)      NOT NULL,
    CONSTRAINT pk_editorial         PRIMARY KEY CLUSTERED (editorial_id),
    CONSTRAINT uq_editorial_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_editorial_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.ENCUADERNACION (
    encuadernacion_id INT IDENTITY(1,1) NOT NULL,
    nombre            VARCHAR(50)       NOT NULL,
    CONSTRAINT pk_encuadernacion         PRIMARY KEY CLUSTERED (encuadernacion_id),
    CONSTRAINT uq_encuadernacion_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_encuadernacion_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.CONDICION (
    condicion_id INT IDENTITY(1,1) NOT NULL,
    nombre       VARCHAR(50)       NOT NULL,
    CONSTRAINT pk_condicion         PRIMARY KEY CLUSTERED (condicion_id),
    CONSTRAINT uq_condicion_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_condicion_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.NACIONALIDAD (
    nacionalidad_id INT IDENTITY(1,1) NOT NULL,
    nombre          VARCHAR(100)      NOT NULL,
    CONSTRAINT pk_nacionalidad         PRIMARY KEY CLUSTERED (nacionalidad_id),
    CONSTRAINT uq_nacionalidad_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_nacionalidad_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.PEDIDO_ESTADO (
    pedido_estado_id INT IDENTITY(1,1) NOT NULL,
    nombre           VARCHAR(50)       NOT NULL,
    CONSTRAINT pk_pedido_estado         PRIMARY KEY CLUSTERED (pedido_estado_id),
    CONSTRAINT uq_pedido_estado_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_pedido_estado_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.PAGO_ESTADO (
    pago_estado_id INT IDENTITY(1,1) NOT NULL,
    nombre         VARCHAR(50)       NOT NULL,
    CONSTRAINT pk_pago_estado         PRIMARY KEY CLUSTERED (pago_estado_id),
    CONSTRAINT uq_pago_estado_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_pago_estado_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.PAGO_METODO (
    pago_metodo_id INT IDENTITY(1,1) NOT NULL,
    nombre         VARCHAR(50)       NOT NULL,
    CONSTRAINT pk_pago_metodo         PRIMARY KEY CLUSTERED (pago_metodo_id),
    CONSTRAINT uq_pago_metodo_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_pago_metodo_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

-- ----------------------------------------------------------------------------
-- 2. Ubicación geográfica
-- ----------------------------------------------------------------------------

CREATE TABLE dbo.PROVINCIA (
    provincia_id INT IDENTITY(1,1) NOT NULL,
    nombre       VARCHAR(100)      NOT NULL,
    CONSTRAINT pk_provincia         PRIMARY KEY CLUSTERED (provincia_id),
    CONSTRAINT uq_provincia_nombre  UNIQUE NONCLUSTERED (nombre),
    CONSTRAINT chk_provincia_nombre CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre))))
);
GO

CREATE TABLE dbo.CIUDAD (
    ciudad_id    INT IDENTITY(1,1) NOT NULL,
    nombre       VARCHAR(100)      NOT NULL,
    provincia_id INT               NOT NULL,
    CONSTRAINT pk_ciudad                  PRIMARY KEY CLUSTERED (ciudad_id),
    CONSTRAINT uq_ciudad_nombre_provincia UNIQUE NONCLUSTERED (nombre, provincia_id),
    CONSTRAINT chk_ciudad_nombre          CHECK (LEN(nombre) > 0 AND DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre)))),
    CONSTRAINT fk_ciudad_provincia        FOREIGN KEY (provincia_id) REFERENCES dbo.PROVINCIA (provincia_id)
);
GO

-- ----------------------------------------------------------------------------
-- 3. Usuarios y direcciones
-- ----------------------------------------------------------------------------

CREATE TABLE dbo.USUARIO (
    usuario_id        INT IDENTITY(1,1) NOT NULL,
    nombre            VARCHAR(50)       NOT NULL,
    apellido          VARCHAR(50)       NOT NULL,
    dni               VARCHAR(8)        NOT NULL,
    email             VARCHAR(254)      NOT NULL,
    telefono          VARCHAR(13)       NOT NULL,
    fecha_nacimiento  DATE              NOT NULL,
    password_hash     VARCHAR(255)      NOT NULL,
    fecha_eliminacion DATETIME          NULL,
    usuario_rol_id    INT               NOT NULL,
    CONSTRAINT pk_usuario                   PRIMARY KEY CLUSTERED (usuario_id),
    CONSTRAINT uq_usuario_dni               UNIQUE NONCLUSTERED (dni),
    CONSTRAINT uq_usuario_email             UNIQUE NONCLUSTERED (email),
    CONSTRAINT chk_usuario_nombre           CHECK (DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre)))
                                                   AND nombre COLLATE Latin1_General_CI_AI LIKE '%[a-z]%'
                                                   AND NOT nombre COLLATE Latin1_General_CI_AI LIKE '%[^a-z .''-]%'),
    CONSTRAINT chk_usuario_apellido         CHECK (DATALENGTH(apellido) = DATALENGTH(LTRIM(RTRIM(apellido)))
                                                   AND apellido COLLATE Latin1_General_CI_AI LIKE '%[a-z]%'
                                                   AND NOT apellido COLLATE Latin1_General_CI_AI LIKE '%[^a-z .''-]%'),
    CONSTRAINT chk_usuario_dni              CHECK (LEN(dni) BETWEEN 7 AND 8 AND NOT dni COLLATE Latin1_General_BIN2 LIKE '%[^0-9]%'),
    CONSTRAINT chk_usuario_email            CHECK (
        -- Forma usuario@dominio.ext, con hasta 64 caracteres antes de la arroba.
        email LIKE '_%@_%._%'
        AND CHARINDEX('@', email) <= 65
        AND NOT email COLLATE Latin1_General_BIN2 LIKE '%[^a-zA-Z0-9._%+@-]%'
        -- Una sola arroba, y ningún punto al inicio, repetido o junto a la arroba.
        AND NOT email LIKE '%@%@%'
        AND NOT email LIKE '.%'
        AND NOT email LIKE '%[.@][.@]%'
        -- El dominio no admite _, % ni +, y sus partes no empiezan ni terminan en guion.
        AND NOT email LIKE '%@%[_%+]%'
        AND NOT email LIKE '%@-%'
        AND NOT email LIKE '%@%.-%'
        AND NOT email LIKE '%@%-.%'
        -- La extensión, lo que sigue al último punto, tiene al menos dos letras.
        AND CHARINDEX('.', REVERSE(email)) > 2
        AND NOT RIGHT(email, CHARINDEX('.', REVERSE(email) + '.') - 1) COLLATE Latin1_General_BIN2 LIKE '%[^a-zA-Z]%'
    ),
    CONSTRAINT chk_usuario_telefono         CHECK (LEN(telefono) BETWEEN 10 AND 13 AND NOT telefono COLLATE Latin1_General_BIN2 LIKE '%[^0-9]%'),
    CONSTRAINT chk_usuario_fecha_nacimiento CHECK (fecha_nacimiento < CONVERT(DATE, GETDATE())),
    CONSTRAINT chk_usuario_password_hash    CHECK (LEN(password_hash) > 0 AND NOT password_hash LIKE '% %'),
    CONSTRAINT chk_usuario_fechas           CHECK (fecha_eliminacion IS NULL OR fecha_eliminacion > fecha_nacimiento),
    CONSTRAINT fk_usuario_usuario_rol       FOREIGN KEY (usuario_rol_id) REFERENCES dbo.USUARIO_ROL (usuario_rol_id)
);
GO

CREATE TABLE dbo.DIRECCION (
    direccion_id  INT IDENTITY(1,1) NOT NULL,
    calle         VARCHAR(255)      NOT NULL,
    altura        INT               NOT NULL,
    piso          VARCHAR(2)        NULL,
    departamento  VARCHAR(3)        NULL,
    codigo_postal VARCHAR(8)        NOT NULL,
    referencia    VARCHAR(MAX)      NULL,
    usuario_id    INT               NOT NULL,
    ciudad_id     INT               NOT NULL,
    CONSTRAINT pk_direccion                PRIMARY KEY CLUSTERED (direccion_id),
    CONSTRAINT chk_direccion_calle         CHECK (LEN(calle) > 0 AND DATALENGTH(calle) = DATALENGTH(LTRIM(RTRIM(calle)))),
    CONSTRAINT chk_direccion_altura        CHECK (altura BETWEEN 1 AND 99999),
    CONSTRAINT chk_direccion_piso          CHECK (LEN(piso) > 0 AND NOT piso COLLATE Latin1_General_BIN2 LIKE '%[^0-9A-Z]%'),
    CONSTRAINT chk_direccion_departamento  CHECK (LEN(departamento) > 0 AND NOT departamento COLLATE Latin1_General_BIN2 LIKE '%[^0-9A-Z]%'),
    -- Código de cuatro dígitos o CPA argentino de ocho caracteres (por ejemplo, W3400ABC).
    CONSTRAINT chk_direccion_codigo_postal CHECK (DATALENGTH(codigo_postal) = LEN(codigo_postal)
                                                  AND (codigo_postal COLLATE Latin1_General_BIN2 LIKE '[0-9][0-9][0-9][0-9]'
                                                       OR codigo_postal COLLATE Latin1_General_BIN2 LIKE '[A-Z][0-9][0-9][0-9][0-9][A-Z][A-Z][A-Z]')),
    CONSTRAINT chk_direccion_referencia    CHECK (LEN(referencia) > 0 AND DATALENGTH(referencia) = DATALENGTH(LTRIM(RTRIM(referencia)))),
    CONSTRAINT fk_direccion_usuario        FOREIGN KEY (usuario_id) REFERENCES dbo.USUARIO (usuario_id),
    CONSTRAINT fk_direccion_ciudad         FOREIGN KEY (ciudad_id)  REFERENCES dbo.CIUDAD (ciudad_id)
);
GO

-- ----------------------------------------------------------------------------
-- 4. Autores y libros
-- ----------------------------------------------------------------------------

CREATE TABLE dbo.AUTOR (
    autor_id            INT IDENTITY(1,1) NOT NULL,
    nombre              VARCHAR(100)      NOT NULL,
    apellido            VARCHAR(100)      NOT NULL,
    isni                CHAR(16)          NULL,
    nacionalidad_id     INT               NULL,
    fecha_nacimiento    DATE              NULL,
    fecha_fallecimiento DATE              NULL,
    diferencial         VARCHAR(150)      NULL,
    biografia           VARCHAR(MAX)      NULL,
    CONSTRAINT pk_autor              PRIMARY KEY CLUSTERED (autor_id),
    CONSTRAINT chk_autor_nombre      CHECK (DATALENGTH(nombre) = DATALENGTH(LTRIM(RTRIM(nombre)))
                                            AND nombre COLLATE Latin1_General_CI_AI LIKE '%[a-z]%'
                                            AND NOT nombre COLLATE Latin1_General_CI_AI LIKE '%[^a-z .''-]%'),
    CONSTRAINT chk_autor_apellido    CHECK (DATALENGTH(apellido) = DATALENGTH(LTRIM(RTRIM(apellido)))
                                            AND apellido COLLATE Latin1_General_CI_AI LIKE '%[a-z]%'
                                            AND NOT apellido COLLATE Latin1_General_CI_AI LIKE '%[^a-z .''-]%'),
    CONSTRAINT chk_autor_fechas      CHECK (fecha_fallecimiento IS NULL OR fecha_nacimiento IS NULL OR fecha_fallecimiento >= fecha_nacimiento),
    CONSTRAINT chk_autor_isni        CHECK (NOT LEFT(isni, 15) LIKE '%[^0-9]%' AND RIGHT(isni, 1) LIKE '[0-9X]'),
    CONSTRAINT chk_autor_diferencial CHECK (LEN(diferencial) > 0 AND DATALENGTH(diferencial) = DATALENGTH(LTRIM(RTRIM(diferencial)))),
    CONSTRAINT chk_autor_biografia   CHECK (LEN(biografia) > 0 AND DATALENGTH(biografia) = DATALENGTH(LTRIM(RTRIM(biografia)))),
    CONSTRAINT fk_autor_nacionalidad FOREIGN KEY (nacionalidad_id) REFERENCES dbo.NACIONALIDAD (nacionalidad_id)
);
GO

-- El ISNI es opcional, pero no puede repetirse entre autores. Los índices filtrados
-- se crean fuera de CREATE TABLE porque SQL Server 2012 no admite declararlos ahí.
CREATE UNIQUE NONCLUSTERED INDEX uq_autor_isni
    ON dbo.AUTOR (isni)
    WHERE isni IS NOT NULL;
GO

CREATE TABLE dbo.LIBRO (
    libro_id          INT IDENTITY(1,1) NOT NULL,
    isbn              CHAR(13)          NOT NULL,
    titulo            VARCHAR(255)      NOT NULL,
    nro_paginas       INT               NOT NULL,
    encuadernacion_id INT               NOT NULL,
    categoria_id      INT               NOT NULL,
    idioma_id         INT               NOT NULL,
    editorial_id      INT               NOT NULL,
    anio_publicacion  SMALLINT          NOT NULL,
    CONSTRAINT pk_libro                   PRIMARY KEY CLUSTERED (libro_id),
    CONSTRAINT uq_libro_isbn              UNIQUE NONCLUSTERED (isbn),
    CONSTRAINT chk_libro_isbn             CHECK (NOT isbn LIKE '%[^0-9]%'),
    CONSTRAINT chk_libro_titulo           CHECK (LEN(titulo) > 0 AND DATALENGTH(titulo) = DATALENGTH(LTRIM(RTRIM(titulo)))),
    CONSTRAINT chk_libro_nro_paginas      CHECK (nro_paginas > 0),
    CONSTRAINT chk_libro_anio_publicacion CHECK (anio_publicacion > 0 AND anio_publicacion <= DATEPART(YEAR, GETDATE()) + 1),
    CONSTRAINT fk_libro_encuadernacion    FOREIGN KEY (encuadernacion_id) REFERENCES dbo.ENCUADERNACION (encuadernacion_id),
    CONSTRAINT fk_libro_categoria         FOREIGN KEY (categoria_id)      REFERENCES dbo.CATEGORIA (categoria_id),
    CONSTRAINT fk_libro_idioma            FOREIGN KEY (idioma_id)         REFERENCES dbo.IDIOMA (idioma_id),
    CONSTRAINT fk_libro_editorial         FOREIGN KEY (editorial_id)      REFERENCES dbo.EDITORIAL (editorial_id)
);
GO

CREATE TABLE dbo.AUTOR_LIBRO (
    autor_libro_id INT IDENTITY(1,1) NOT NULL,
    libro_id       INT               NOT NULL,
    autor_id       INT               NOT NULL,
    CONSTRAINT pk_autor_libro       PRIMARY KEY CLUSTERED (autor_libro_id),
    CONSTRAINT uq_autor_libro       UNIQUE NONCLUSTERED (autor_id, libro_id),
    CONSTRAINT fk_autor_libro_libro FOREIGN KEY (libro_id) REFERENCES dbo.LIBRO (libro_id),
    CONSTRAINT fk_autor_libro_autor FOREIGN KEY (autor_id) REFERENCES dbo.AUTOR (autor_id)
);
GO

-- ----------------------------------------------------------------------------
-- 5. Publicaciones
-- ----------------------------------------------------------------------------

CREATE TABLE dbo.PUBLICACION (
    publicacion_id    INT IDENTITY(1,1) NOT NULL,
    usuario_id        INT               NOT NULL,
    libro_id          INT               NOT NULL,
    condicion_id      INT               NOT NULL,
    stock             INT               NOT NULL,
    precio            DECIMAL(18, 2)    NOT NULL,
    disponible        BIT               NOT NULL CONSTRAINT df_publicacion_disponible     DEFAULT (1),
    fecha_creacion    DATETIME          NOT NULL CONSTRAINT df_publicacion_fecha_creacion DEFAULT (GETDATE()),
    fecha_eliminacion DATETIME          NULL,
    CONSTRAINT pk_publicacion                          PRIMARY KEY CLUSTERED (publicacion_id),
    CONSTRAINT chk_publicacion_stock                   CHECK (stock >= 0),
    CONSTRAINT chk_publicacion_precio                  CHECK (precio > 0),
    CONSTRAINT chk_publicacion_fechas                  CHECK (fecha_eliminacion IS NULL OR fecha_eliminacion >= fecha_creacion),
    CONSTRAINT chk_publicacion_eliminada_no_disponible CHECK (fecha_eliminacion IS NULL OR disponible = 0),
    CONSTRAINT fk_publicacion_usuario                  FOREIGN KEY (usuario_id)   REFERENCES dbo.USUARIO (usuario_id),
    CONSTRAINT fk_publicacion_libro                    FOREIGN KEY (libro_id)     REFERENCES dbo.LIBRO (libro_id),
    CONSTRAINT fk_publicacion_condicion                FOREIGN KEY (condicion_id) REFERENCES dbo.CONDICION (condicion_id)
);
GO

-- Un vendedor no puede tener dos publicaciones vigentes del mismo libro en la misma condición.
CREATE UNIQUE NONCLUSTERED INDEX uq_publicacion_usuario_libro_condicion
    ON dbo.PUBLICACION (usuario_id, libro_id, condicion_id)
    WHERE fecha_eliminacion IS NULL;
GO

-- ----------------------------------------------------------------------------
-- 6. Pedidos, detalle y pagos
-- ----------------------------------------------------------------------------

CREATE TABLE dbo.PEDIDO (
    pedido_id           INT IDENTITY(1,1) NOT NULL,
    fecha_pedido        DATETIME          NOT NULL CONSTRAINT df_pedido_fecha_pedido DEFAULT (GETDATE()),
    envio_calle         VARCHAR(255)      NOT NULL,
    envio_altura        INT               NOT NULL,
    envio_piso          VARCHAR(2)        NULL,
    envio_departamento  VARCHAR(3)        NULL,
    envio_codigo_postal VARCHAR(8)        NOT NULL,
    envio_referencia    VARCHAR(MAX)      NULL,
    usuario_id          INT               NOT NULL,
    pedido_estado_id    INT               NOT NULL,
    ciudad_id           INT               NOT NULL,
    CONSTRAINT pk_pedido                      PRIMARY KEY CLUSTERED (pedido_id),
    CONSTRAINT chk_pedido_envio_calle         CHECK (LEN(envio_calle) > 0 AND DATALENGTH(envio_calle) = DATALENGTH(LTRIM(RTRIM(envio_calle)))),
    CONSTRAINT chk_pedido_envio_altura        CHECK (envio_altura BETWEEN 1 AND 99999),
    CONSTRAINT chk_pedido_envio_piso          CHECK (LEN(envio_piso) > 0 AND NOT envio_piso COLLATE Latin1_General_BIN2 LIKE '%[^0-9A-Z]%'),
    CONSTRAINT chk_pedido_envio_departamento  CHECK (LEN(envio_departamento) > 0 AND NOT envio_departamento COLLATE Latin1_General_BIN2 LIKE '%[^0-9A-Z]%'),
    CONSTRAINT chk_pedido_envio_codigo_postal CHECK (DATALENGTH(envio_codigo_postal) = LEN(envio_codigo_postal)
                                                     AND (envio_codigo_postal COLLATE Latin1_General_BIN2 LIKE '[0-9][0-9][0-9][0-9]'
                                                          OR envio_codigo_postal COLLATE Latin1_General_BIN2 LIKE '[A-Z][0-9][0-9][0-9][0-9][A-Z][A-Z][A-Z]')),
    CONSTRAINT chk_pedido_envio_referencia    CHECK (LEN(envio_referencia) > 0 AND DATALENGTH(envio_referencia) = DATALENGTH(LTRIM(RTRIM(envio_referencia)))),
    CONSTRAINT fk_pedido_usuario              FOREIGN KEY (usuario_id)       REFERENCES dbo.USUARIO (usuario_id),
    CONSTRAINT fk_pedido_pedido_estado        FOREIGN KEY (pedido_estado_id) REFERENCES dbo.PEDIDO_ESTADO (pedido_estado_id),
    CONSTRAINT fk_pedido_ciudad               FOREIGN KEY (ciudad_id)        REFERENCES dbo.CIUDAD (ciudad_id)
);
GO

CREATE TABLE dbo.PEDIDO_DETALLE (
    pedido_detalle_id INT IDENTITY(1,1) NOT NULL,
    cantidad          INT               NOT NULL,
    precio_unitario   DECIMAL(18, 2)    NOT NULL,
    pedido_id         INT               NOT NULL,
    publicacion_id    INT               NOT NULL,
    CONSTRAINT pk_pedido_detalle                    PRIMARY KEY CLUSTERED (pedido_detalle_id),
    CONSTRAINT uq_pedido_detalle_pedido_publicacion UNIQUE NONCLUSTERED (pedido_id, publicacion_id),
    CONSTRAINT chk_pedido_detalle_cantidad          CHECK (cantidad > 0),
    CONSTRAINT chk_pedido_detalle_precio_unitario   CHECK (precio_unitario > 0),
    CONSTRAINT fk_pedido_detalle_pedido             FOREIGN KEY (pedido_id)      REFERENCES dbo.PEDIDO (pedido_id),
    CONSTRAINT fk_pedido_detalle_publicacion        FOREIGN KEY (publicacion_id) REFERENCES dbo.PUBLICACION (publicacion_id)
);
GO

CREATE TABLE dbo.PAGO (
    pago_id        INT IDENTITY(1,1) NOT NULL,
    importe        DECIMAL(18, 2)    NOT NULL,
    fecha_creacion DATETIME          NOT NULL CONSTRAINT df_pago_fecha_creacion DEFAULT (GETDATE()),
    fecha_pago     DATETIME          NULL,
    pago_estado_id INT               NOT NULL,
    pago_metodo_id INT               NOT NULL,
    pedido_id      INT               NOT NULL,
    CONSTRAINT pk_pago             PRIMARY KEY CLUSTERED (pago_id),
    CONSTRAINT chk_pago_fechas     CHECK (fecha_pago IS NULL OR fecha_pago >= fecha_creacion),
    CONSTRAINT chk_pago_importe    CHECK (importe > 0),
    CONSTRAINT fk_pago_pago_estado FOREIGN KEY (pago_estado_id) REFERENCES dbo.PAGO_ESTADO (pago_estado_id),
    CONSTRAINT fk_pago_pago_metodo FOREIGN KEY (pago_metodo_id) REFERENCES dbo.PAGO_METODO (pago_metodo_id),
    CONSTRAINT fk_pago_pedido      FOREIGN KEY (pedido_id)      REFERENCES dbo.PEDIDO (pedido_id)
);
GO

-- Vuelve a habilitar la ejecución por si el control inicial la detuvo.
SET NOEXEC OFF;
GO
