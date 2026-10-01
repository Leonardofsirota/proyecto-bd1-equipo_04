/* ============================================================================
   Sistema de venta de libros - Datos de prueba (precarga inicial)

   Motor:      SQL Server (T-SQL)
   Requisito:  la base [sistema-venta-libros] ya fue creada con
               sql/ddl/sistema-venta-libros.sql y sus tablas están vacías.
   Uso:        abrir este archivo en SSMS y ejecutarlo completo (F5).

   - Si alguna tabla ya tiene datos, el script se detiene sin insertar nada.
   - Toda la carga corre en una única transacción: se inserta todo o nada.
   - Los ID se cargan de forma explícita (IDENTITY_INSERT) para que las claves
     foráneas sean siempre las mismas en cualquier instalación.
   - Las fechas usan formatos independientes del idioma de la sesión
     ('AAAAMMDD' y 'AAAA-MM-DDThh:mm:ss').
   - ISBN, ISNI, DNI, correos, teléfonos y hashes de contraseña son ficticios.
   ============================================================================ */

USE [sistema-venta-libros];
GO

-- Requerido para insertar en tablas con índices filtrados (AUTOR y PUBLICACION).
-- SSMS lo activa por defecto; sqlcmd no.
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- La precarga solo se ejecuta sobre tablas vacías.
IF    EXISTS (SELECT 1 FROM dbo.USUARIO_ROL)
   OR EXISTS (SELECT 1 FROM dbo.CATEGORIA)
   OR EXISTS (SELECT 1 FROM dbo.IDIOMA)
   OR EXISTS (SELECT 1 FROM dbo.EDITORIAL)
   OR EXISTS (SELECT 1 FROM dbo.ENCUADERNACION)
   OR EXISTS (SELECT 1 FROM dbo.CONDICION)
   OR EXISTS (SELECT 1 FROM dbo.NACIONALIDAD)
   OR EXISTS (SELECT 1 FROM dbo.PEDIDO_ESTADO)
   OR EXISTS (SELECT 1 FROM dbo.PAGO_ESTADO)
   OR EXISTS (SELECT 1 FROM dbo.PAGO_METODO)
   OR EXISTS (SELECT 1 FROM dbo.PROVINCIA)
   OR EXISTS (SELECT 1 FROM dbo.CIUDAD)
   OR EXISTS (SELECT 1 FROM dbo.USUARIO)
   OR EXISTS (SELECT 1 FROM dbo.DIRECCION)
   OR EXISTS (SELECT 1 FROM dbo.AUTOR)
   OR EXISTS (SELECT 1 FROM dbo.LIBRO)
   OR EXISTS (SELECT 1 FROM dbo.AUTOR_LIBRO)
   OR EXISTS (SELECT 1 FROM dbo.PUBLICACION)
   OR EXISTS (SELECT 1 FROM dbo.PEDIDO)
   OR EXISTS (SELECT 1 FROM dbo.PEDIDO_DETALLE)
   OR EXISTS (SELECT 1 FROM dbo.PAGO)
BEGIN
    RAISERROR('La base ya contiene datos. La precarga solo se ejecuta sobre tablas vacías; no se insertó nada.', 16, 1);
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    -- ----------------------------------------------------------------------
    -- 1. Catálogos
    -- ----------------------------------------------------------------------

    SET IDENTITY_INSERT dbo.USUARIO_ROL ON;
    INSERT INTO dbo.USUARIO_ROL (usuario_rol_id, nombre)
    VALUES
        (1, 'Administrador'),
        (2, 'Vendedor'),
        (3, 'Cliente');
    SET IDENTITY_INSERT dbo.USUARIO_ROL OFF;

    -- Géneros literarios (1 a 10) y áreas académicas o técnicas (11 a 20).
    SET IDENTITY_INSERT dbo.CATEGORIA ON;
    INSERT INTO dbo.CATEGORIA (categoria_id, nombre)
    VALUES
        (1 , 'Novela'),
        (2 , 'Cuento'),
        (3 , 'Poesía'),
        (4 , 'Ciencia ficción'),
        (5 , 'Fantasía'),
        (6 , 'Policial'),
        (7 , 'Terror'),
        (8 , 'Romance'),
        (9 , 'Teatro'),
        (10, 'Ensayo'),
        (11, 'Informática'),
        (12, 'Matemática'),
        (13, 'Física'),
        (14, 'Ingeniería'),
        (15, 'Derecho'),
        (16, 'Medicina'),
        (17, 'Economía'),
        (18, 'Historia'),
        (19, 'Filosofía'),
        (20, 'Psicología');
    SET IDENTITY_INSERT dbo.CATEGORIA OFF;

    SET IDENTITY_INSERT dbo.IDIOMA ON;
    INSERT INTO dbo.IDIOMA (idioma_id, nombre)
    VALUES
        (1 , 'Español'),
        (2 , 'Inglés'),
        (3 , 'Portugués'),
        (4 , 'Francés'),
        (5 , 'Italiano'),
        (6 , 'Alemán'),
        (7 , 'Ruso'),
        (8 , 'Japonés'),
        (9 , 'Chino'),
        (10, 'Árabe');
    SET IDENTITY_INSERT dbo.IDIOMA OFF;

    SET IDENTITY_INSERT dbo.EDITORIAL ON;
    INSERT INTO dbo.EDITORIAL (editorial_id, nombre)
    VALUES
        (1 , 'Planeta'),
        (2 , 'Sudamericana'),
        (3 , 'Alfaguara'),
        (4 , 'Emecé'),
        (5 , 'Anagrama'),
        (6 , 'Siglo XXI Editores'),
        (7 , 'Eudeba'),
        (8 , 'Tusquets'),
        (9 , 'Debolsillo'),
        (10, 'Salamandra');
    SET IDENTITY_INSERT dbo.EDITORIAL OFF;

    SET IDENTITY_INSERT dbo.ENCUADERNACION ON;
    INSERT INTO dbo.ENCUADERNACION (encuadernacion_id, nombre)
    VALUES
        (1, 'Tapa blanda'),
        (2, 'Tapa dura');
    SET IDENTITY_INSERT dbo.ENCUADERNACION OFF;

    SET IDENTITY_INSERT dbo.CONDICION ON;
    INSERT INTO dbo.CONDICION (condicion_id, nombre)
    VALUES
        (1, 'Nuevo'),
        (2, 'Como nuevo'),
        (3, 'Muy bueno'),
        (4, 'Bueno'),
        (5, 'Aceptable');
    SET IDENTITY_INSERT dbo.CONDICION OFF;

    SET IDENTITY_INSERT dbo.NACIONALIDAD ON;
    INSERT INTO dbo.NACIONALIDAD (nacionalidad_id, nombre)
    VALUES
        (1 , 'Argentina'),
        (2 , 'Colombiana'),
        (3 , 'Chilena'),
        (4 , 'Mexicana'),
        (5 , 'Peruana'),
        (6 , 'Uruguaya'),
        (7 , 'Española'),
        (8 , 'Estadounidense'),
        (9 , 'Británica'),
        (10, 'Francesa');
    SET IDENTITY_INSERT dbo.NACIONALIDAD OFF;

    SET IDENTITY_INSERT dbo.PEDIDO_ESTADO ON;
    INSERT INTO dbo.PEDIDO_ESTADO (pedido_estado_id, nombre)
    VALUES
        (1, 'Pendiente'),
        (2, 'Confirmado'),
        (3, 'Entregado'),
        (4, 'Cancelado');
    SET IDENTITY_INSERT dbo.PEDIDO_ESTADO OFF;

    SET IDENTITY_INSERT dbo.PAGO_ESTADO ON;
    INSERT INTO dbo.PAGO_ESTADO (pago_estado_id, nombre)
    VALUES
        (1, 'Pendiente'),
        (2, 'Aprobado'),
        (3, 'Rechazado'),
        (4, 'Cancelado');
    SET IDENTITY_INSERT dbo.PAGO_ESTADO OFF;

    SET IDENTITY_INSERT dbo.PAGO_METODO ON;
    INSERT INTO dbo.PAGO_METODO (pago_metodo_id, nombre)
    VALUES
        (1, 'Tarjeta de débito'),
        (2, 'Tarjeta de crédito'),
        (3, 'Transferencia');
    SET IDENTITY_INSERT dbo.PAGO_METODO OFF;

    -- ----------------------------------------------------------------------
    -- 2. Ubicación geográfica
    -- ----------------------------------------------------------------------

    -- Por ahora el sistema solo contempla la provincia de Corrientes.
    SET IDENTITY_INSERT dbo.PROVINCIA ON;
    INSERT INTO dbo.PROVINCIA (provincia_id, nombre)
    VALUES
        (1, 'Corrientes');
    SET IDENTITY_INSERT dbo.PROVINCIA OFF;

    -- Los 74 municipios de Corrientes (fuente: API Georef, datos.gob.ar).
    SET IDENTITY_INSERT dbo.CIUDAD ON;
    INSERT INTO dbo.CIUDAD (ciudad_id, nombre, provincia_id)
    VALUES
        (1 , '9 de Julio'                   , 1),
        (2 , 'Alvear'                       , 1),
        (3 , 'Bella Vista'                  , 1),
        (4 , 'Bonpland'                     , 1),
        (5 , 'Caá Catí'                     , 1),
        (6 , 'Carolina'                     , 1),
        (7 , 'Cazadores Correntinos'        , 1),
        (8 , 'Cecilio Echavarría'           , 1),
        (9 , 'Chavarría'                    , 1),
        (10, 'Colonia Carlos Pellegrini'    , 1),
        (11, 'Colonia Libertad'             , 1),
        (12, 'Colonia Liebig'               , 1),
        (13, 'Colonia Pando'                , 1),
        (14, 'Colonia Santa Rosa'           , 1),
        (15, 'Concepción del Yaguareté Corá', 1),
        (16, 'Corrientes'                   , 1),
        (17, 'Cruz de los Milagros'         , 1),
        (18, 'Curuzú Cuatiá'                , 1),
        (19, 'El Sombrero'                  , 1),
        (20, 'Empedrado'                    , 1),
        (21, 'Esquina'                      , 1),
        (22, 'Estación Torrent'             , 1),
        (23, 'Felipe Yofré'                 , 1),
        (24, 'Garaví'                       , 1),
        (25, 'Garruchos'                    , 1),
        (26, 'Gobernador Martínez'          , 1),
        (27, 'Gobernador Virasoro'          , 1),
        (28, 'Goya'                         , 1),
        (29, 'Guaviraví'                    , 1),
        (30, 'Herlitzka'                    , 1),
        (31, 'Itá Ibaté'                    , 1),
        (32, 'Itatí'                        , 1),
        (33, 'Ituzaingó'                    , 1),
        (34, 'Juan Pujol'                   , 1),
        (35, 'La Cruz'                      , 1),
        (36, 'Lavalle'                      , 1),
        (37, 'Lomas de Vallejos'            , 1),
        (38, 'Loreto'                       , 1),
        (39, 'Mariano I. Loza'              , 1),
        (40, 'Mburucuyá'                    , 1),
        (41, 'Mercedes'                     , 1),
        (42, 'Mocoretá'                     , 1),
        (43, 'Monte Caseros'                , 1),
        (44, 'Pago de los Deseos'           , 1),
        (45, 'Palmar Grande'                , 1),
        (46, 'Parada Pucheta'               , 1),
        (47, 'Paso de la Patria'            , 1),
        (48, 'Paso de los Libres'           , 1),
        (49, 'Pedro R. Fernández'           , 1),
        (50, 'Perugorría'                   , 1),
        (51, 'Pueblo Libertador'            , 1),
        (52, 'Ramada Paso'                  , 1),
        (53, 'Riachuelo'                    , 1),
        (54, 'Saladas'                      , 1),
        (55, 'San Antonio de Itatí'         , 1),
        (56, 'San Antonio Isla Apipé Grande', 1),
        (57, 'San Carlos'                   , 1),
        (58, 'San Cosme'                    , 1),
        (59, 'San Isidro'                   , 1),
        (60, 'San Lorenzo'                  , 1),
        (61, 'San Luis del Palmar'          , 1),
        (62, 'San Miguel'                   , 1),
        (63, 'San Roque'                    , 1),
        (64, 'Santa Ana de los Guácaras'    , 1),
        (65, 'Santa Lucía'                  , 1),
        (66, 'Santo Tomé'                   , 1),
        (67, 'Sauce'                        , 1),
        (68, 'Tabay'                        , 1),
        (69, 'Tapebicuá'                    , 1),
        (70, 'Tatacuá'                      , 1),
        (71, 'Tres de Abril'                , 1),
        (72, 'Villa Olivari'                , 1),
        (73, 'Yapeyú'                       , 1),
        (74, 'Yatay Ti Calle'               , 1);
    SET IDENTITY_INSERT dbo.CIUDAD OFF;

    COMMIT TRANSACTION;
    PRINT 'Precarga finalizada correctamente.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
