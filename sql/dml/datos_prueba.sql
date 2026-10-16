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

    -- ----------------------------------------------------------------------
    -- 3. Usuarios y direcciones
    -- ----------------------------------------------------------------------

    -- 1 administrador, 4 vendedores (2 a 5) y 5 clientes (6 a 10).
    -- El usuario 10 está dado de baja (fecha_eliminacion) y conserva su historial.
    SET IDENTITY_INSERT dbo.USUARIO ON;
    INSERT INTO dbo.USUARIO (usuario_id, nombre, apellido, dni, email, telefono, fecha_nacimiento, password_hash, fecha_eliminacion, usuario_rol_id)
    VALUES
        (1 , 'Mariana', 'Acosta'   , '28456123', 'mariana.acosta@example.com'  , '3794410001', '19810412', '$2b$12$36lJchbN/a2etUClPVG2WLceDDYY4zMdz4cr2pza0J1KmoxKYHoeF', NULL                 , 1),
        (2 , 'Carlos' , 'Benítez'  , '30112457', 'carlos.benitez@example.com'  , '3794410002', '19840903', '$2b$12$eFS.JT2HWqpPSMj6dYGT1q4gbpzMmrEpNBS4m9Q2udBTZOJQXYSsg', NULL                 , 2),
        (3 , 'Lucía'  , 'Romero'   , '33587904', 'lucia.romero@example.com'    , '3773410003', '19880125', '$2b$12$qWhcIPME0IFla1cVC3xAz47kHRZ1PLd0kzfRuankEp7sPR8IBc4r/', NULL                 , 2),
        (4 , 'Jorge'  , 'Sosa'     , '25874136', 'jorge.sosa@example.com'      , '3777410004', '19771108', '$2b$12$LAJh1EIunOL9hhbnqwo//QiHD5zSxYr2kH3y3GsyV6YqfT/JG6i9U', NULL                 , 2),
        (5 , 'Valeria', 'Giménez'  , '36201548', 'valeria.gimenez@example.com' , '3756410005', '19920617', '$2b$12$SeBpt6Vw5JttznGMjbW9aUcO7GC88Pau4CGTZttKAJH97w68WWSHQ', NULL                 , 2),
        (6 , 'Martín' , 'Fernández', '38745210', 'martin.fernandez@example.com', '3794410006', '19950228', '$2b$12$dSxzrX5d1Z4tXZlxBSf9ZKYDhThoQ9tQ9WW5u4HxdK.Y9lpR9Rxft', NULL                 , 3),
        (7 , 'Sofía'  , 'Aguirre'  , '40125896', 'sofia.aguirre@example.com'   , '3777410007', '19971005', '$2b$12$hdvSYruzcnlOhlYri9wL9hXTbGh1eIluU8h74RYCBta./Lmq6mJoO', NULL                 , 3),
        (8 , 'Diego'  , 'Ojeda'    , '34698521', 'diego.ojeda@example.com'     , '3794410008', '19900719', '$2b$12$q7SpRDp7Ftz5LIKBfh0nU9Awa.YaLL7r/9yh3v/iIWpzxr/MEd72B', NULL                 , 3),
        (9 , 'Camila' , 'Vallejos' , '42367158', 'camila.vallejos@example.com' , '3772410009', '20000314', '$2b$12$eTwHvCChqWddYSkUGTWjLiEwznHDmZ4RnJ97HqMUKk0NI9IPVat6q', NULL                 , 3),
        (10, 'Nicolás', 'Ramírez'  , '9874563' , 'nicolas.ramirez@example.com' , '3774410010', '19581201', '$2b$12$pYDCpipvjxU5YSvraZmjMQ6gkHYAuOjldzPwr93QlWVrx9z.5mI5/', '2026-06-01T09:00:00', 3);
    SET IDENTITY_INSERT dbo.USUARIO OFF;

    SET IDENTITY_INSERT dbo.DIRECCION ON;
    INSERT INTO dbo.DIRECCION (direccion_id, calle, altura, piso, departamento, codigo_postal, referencia, usuario_id, ciudad_id)
    VALUES
        (1 , 'Junín'            , 1234, '3' , 'B' , '3400', 'Portero eléctrico: 3 B'                  , 6 , 16),
        (2 , 'Av. 3 de Abril'   , 850 , NULL, NULL, '3400', 'Local comercial, horario de 8 a 16 h'    , 6 , 16),
        (3 , 'Colón'            , 742 , NULL, NULL, '3450', NULL                                      , 7 , 28),
        (4 , 'Av. Independencia', 4150, NULL, NULL, '3400', 'Casa con rejas negras, frente a la plaza', 8 , 16),
        (5 , 'Belgrano'         , 315 , '1' , 'A' , '3230', NULL                                      , 9 , 48),
        (6 , 'Sarmiento'        , 968 , NULL, NULL, '3460', NULL                                      , 10, 18),
        (7 , 'San Juan'         , 1071, NULL, NULL, '3400', NULL                                      , 2 , 16),
        (8 , 'Pujol'            , 560 , NULL, NULL, '3470', 'Timbre en la librería de planta baja'    , 3 , 41),
        (9 , 'Salta'            , 233 , NULL, NULL, '3432', NULL                                      , 4 , 3),
        (10, 'Av. San Martín'   , 1890, '2' , 'D' , '3340', NULL                                      , 5 , 66);
    SET IDENTITY_INSERT dbo.DIRECCION OFF;

    -- ----------------------------------------------------------------------
    -- 4. Autores y libros
    -- ----------------------------------------------------------------------

    -- Dos autores sin ISNI: el índice único filtrado admite varios valores NULL.
    SET IDENTITY_INSERT dbo.AUTOR ON;
    INSERT INTO dbo.AUTOR (autor_id, nombre, apellido, isni, nacionalidad_id, fecha_nacimiento, fecha_fallecimiento, diferencial, biografia)
    VALUES
        (1 , 'Jorge Luis', 'Borges'        , '000000010000101X', 1, '18990824', '19860614', NULL                                               , 'Cuentista, poeta y ensayista, figura central de la literatura en lengua española del siglo XX.'),
        (2 , 'Julio'     , 'Cortázar'      , '0000000100002020', 1, '19140826', '19840212', NULL                                               , 'Novelista y cuentista, uno de los grandes renovadores de la narrativa hispanoamericana.'),
        (3 , 'Gabriel'   , 'García Márquez', '0000000100003031', 2, '19270306', '20140417', NULL                                               , 'Novelista y periodista, referente del realismo mágico y Premio Nobel de Literatura 1982.'),
        (4 , 'Isabel'    , 'Allende'       , '0000000100004042', 3, '19420802', NULL      , NULL                                               , 'Novelista, una de las autoras más leídas en lengua española.'),
        (5 , 'Mario'     , 'Vargas Llosa'  , '0000000100005053', 5, '19360328', '20250413', NULL                                               , 'Novelista y ensayista, Premio Nobel de Literatura 2010.'),
        (6 , 'Mario'     , 'Benedetti'     , '0000000100006064', 6, '19200914', '20090517', NULL                                               , 'Poeta, narrador y ensayista de la Generación del 45.'),
        (7 , 'Eduardo'   , 'Galeano'       , NULL              , 6, '19400903', '20150413', NULL                                               , 'Periodista y escritor, autor de ensayos sobre la historia de América Latina.'),
        (8 , 'Stephen'   , 'King'          , '0000000100008086', 8, '19470921', NULL      , 'También publicó con el seudónimo Richard Bachman' , 'Novelista, autor de referencia de la literatura de terror contemporánea.'),
        (9 , 'J. K.'     , 'Rowling'       , '0000000100009097', 9, '19650731', NULL      , 'También publica con el seudónimo Robert Galbraith', 'Novelista, creadora de la saga Harry Potter.'),
        (10, 'Adolfo'    , 'Bioy Casares'  , NULL              , 1, '19140915', '19990308', NULL                                               , 'Narrador de literatura fantástica y policial, colaborador habitual de Jorge Luis Borges.');
    SET IDENTITY_INSERT dbo.AUTOR OFF;

    SET IDENTITY_INSERT dbo.LIBRO ON;
    INSERT INTO dbo.LIBRO (libro_id, isbn, titulo, nro_paginas, encuadernacion_id, categoria_id, idioma_id, editorial_id, anio_publicacion)
    VALUES
        (1 , '9789500421010', 'Ficciones'                            , 224 , 1, 2 , 1, 4 , 1944),
        (2 , '9789500421027', 'Seis problemas para don Isidro Parodi', 192 , 1, 6 , 1, 4 , 1942),
        (3 , '9789500712033', 'Rayuela'                              , 632 , 1, 1 , 1, 2 , 1963),
        (4 , '9789500712040', 'Cien años de soledad'                 , 496 , 2, 1 , 1, 2 , 1967),
        (5 , '9788497593052', 'La casa de los espíritus'             , 464 , 1, 1 , 1, 9 , 1982),
        (6 , '9788420473062', 'La ciudad y los perros'               , 408 , 1, 1 , 1, 3 , 1963),
        (7 , '9789504914075', 'La tregua'                            , 208 , 1, 1 , 1, 1 , 1960),
        (8 , '9789876295086', 'Las venas abiertas de América Latina' , 384 , 1, 10, 1, 6 , 1971),
        (9 , '9788497593090', 'It'                                   , 1504, 1, 7 , 1, 9 , 1986),
        (10, '9788478884100', 'Harry Potter y la piedra filosofal'   , 256 , 2, 5 , 1, 10, 1997);
    SET IDENTITY_INSERT dbo.LIBRO OFF;

    -- Todo libro tiene al menos un autor; el libro 2 tiene dos (relación N:M).
    SET IDENTITY_INSERT dbo.AUTOR_LIBRO ON;
    INSERT INTO dbo.AUTOR_LIBRO (autor_libro_id, libro_id, autor_id)
    VALUES
        (1 , 1 , 1),
        (2 , 2 , 1),
        (3 , 2 , 10),
        (4 , 3 , 2),
        (5 , 4 , 3),
        (6 , 5 , 4),
        (7 , 6 , 5),
        (8 , 7 , 6),
        (9 , 8 , 7),
        (10, 9 , 8),
        (11, 10, 9);
    SET IDENTITY_INSERT dbo.AUTOR_LIBRO OFF;

    -- ----------------------------------------------------------------------
    -- 5. Publicaciones
    -- ----------------------------------------------------------------------

    -- Ofertas de los vendedores. El libro 4 lo ofrecen dos vendedores en distinta condición.
    -- La publicación 7 está agotada y la 10 fue dada de baja. El stock es el vigente,
    -- ya descontadas las ventas confirmadas.
    SET IDENTITY_INSERT dbo.PUBLICACION ON;
    INSERT INTO dbo.PUBLICACION (publicacion_id, usuario_id, libro_id, condicion_id, stock, precio, disponible, fecha_creacion, fecha_eliminacion)
    VALUES
        (1 , 2, 1 , 1, 8 , 18500.00, 1, '2026-02-10T09:30:00', NULL),
        (2 , 2, 4 , 1, 5 , 24900.00, 1, '2026-02-10T09:45:00', NULL),
        (3 , 2, 3 , 3, 2 , 15000.00, 1, '2026-02-12T18:00:00', NULL),
        (4 , 3, 4 , 2, 1 , 19800.00, 1, '2026-02-15T11:20:00', NULL),
        (5 , 3, 5 , 1, 6 , 21500.00, 1, '2026-02-15T11:35:00', NULL),
        (6 , 3, 10, 1, 10, 27500.00, 1, '2026-02-20T15:10:00', NULL),
        (7 , 4, 9 , 4, 0 , 16500.00, 0, '2026-03-01T10:00:00', NULL),
        (8 , 4, 8 , 1, 7 , 20900.00, 1, '2026-03-01T10:15:00', NULL),
        (9 , 5, 6 , 1, 4 , 22300.00, 1, '2026-03-08T17:40:00', NULL),
        (10, 5, 7 , 5, 1 , 6500.00 , 0, '2026-03-08T17:55:00', '2026-05-15T12:00:00');
    SET IDENTITY_INSERT dbo.PUBLICACION OFF;

    -- ----------------------------------------------------------------------
    -- 6. Pedidos, detalle y pagos
    -- ----------------------------------------------------------------------

    -- La dirección de envío se copia en el pedido al momento de la compra.
    SET IDENTITY_INSERT dbo.PEDIDO ON;
    INSERT INTO dbo.PEDIDO (pedido_id, fecha_pedido, envio_calle, envio_altura, envio_piso, envio_departamento, envio_codigo_postal, envio_referencia, usuario_id, pedido_estado_id, ciudad_id)
    VALUES
        (1 , '2026-03-05T10:15:00', 'Junín'            , 1234, '3' , 'B' , '3400', 'Portero eléctrico: 3 B'                  , 6 , 3, 16),
        (2 , '2026-03-18T16:40:00', 'Colón'            , 742 , NULL, NULL, '3450', NULL                                      , 7 , 3, 28),
        (3 , '2026-04-02T09:03:00', 'Av. Independencia', 4150, NULL, NULL, '3400', 'Casa con rejas negras, frente a la plaza', 8 , 3, 16),
        (4 , '2026-04-20T19:28:00', 'Sarmiento'        , 968 , NULL, NULL, '3460', NULL                                      , 10, 4, 18),
        (5 , '2026-05-11T12:08:00', 'Belgrano'         , 315 , '1' , 'A' , '3230', NULL                                      , 9 , 3, 48),
        (6 , '2026-06-08T18:22:00', 'Av. 3 de Abril'   , 850 , NULL, NULL, '3400', 'Local comercial, horario de 8 a 16 h'    , 6 , 3, 16),
        (7 , '2026-07-15T11:00:00', 'Colón'            , 742 , NULL, NULL, '3450', NULL                                      , 7 , 3, 28),
        (8 , '2026-08-21T20:12:00', 'Av. Independencia', 4150, NULL, NULL, '3400', 'Casa con rejas negras, frente a la plaza', 8 , 2, 16),
        (9 , '2026-09-12T14:38:00', 'Belgrano'         , 315 , '1' , 'A' , '3230', NULL                                      , 9 , 1, 48),
        (10, '2026-09-28T21:05:00', 'Junín'            , 1234, '3' , 'B' , '3400', 'Portero eléctrico: 3 B'                  , 6 , 1, 16);
    SET IDENTITY_INSERT dbo.PEDIDO OFF;

    -- precio_unitario es el precio vigente al momento de la compra. En los pedidos 1 y 3
    -- difiere del precio actual de las publicaciones 1, 2 y 8, que aumentaron después.
    SET IDENTITY_INSERT dbo.PEDIDO_DETALLE ON;
    INSERT INTO dbo.PEDIDO_DETALLE (pedido_detalle_id, cantidad, precio_unitario, pedido_id, publicacion_id)
    VALUES
        (1 , 1, 17000.00, 1 , 1),
        (2 , 1, 22900.00, 1 , 2),
        (3 , 2, 21500.00, 2 , 5),
        (4 , 1, 16500.00, 3 , 7),
        (5 , 1, 19900.00, 3 , 8),
        (6 , 1, 6500.00 , 4 , 10),
        (7 , 1, 27500.00, 5 , 6),
        (8 , 1, 19800.00, 5 , 4),
        (9 , 1, 22300.00, 5 , 9),
        (10, 1, 15000.00, 6 , 3),
        (11, 2, 27500.00, 7 , 6),
        (12, 1, 18500.00, 7 , 1),
        (13, 1, 24900.00, 8 , 2),
        (14, 1, 21500.00, 8 , 5),
        (15, 2, 22300.00, 9 , 9),
        (16, 1, 20900.00, 10, 8),
        (17, 1, 18500.00, 10, 1);
    SET IDENTITY_INSERT dbo.PEDIDO_DETALLE OFF;

    -- El importe de cada pago es el total del pedido. El pedido 3 tiene un intento rechazado
    -- y luego uno aprobado; el pedido 10 todavía no registra pagos.
    SET IDENTITY_INSERT dbo.PAGO ON;
    INSERT INTO dbo.PAGO (pago_id, importe, fecha_creacion, fecha_pago, pago_estado_id, pago_metodo_id, pedido_id)
    VALUES
        (1 , 39900.00, '2026-03-05T10:17:00', '2026-03-05T10:18:30', 2, 2, 1),
        (2 , 43000.00, '2026-03-18T16:42:00', '2026-03-18T16:43:10', 2, 1, 2),
        (3 , 36400.00, '2026-04-02T09:05:00', NULL                 , 3, 2, 3),
        (4 , 36400.00, '2026-04-02T09:20:00', '2026-04-03T11:00:00', 2, 3, 3),
        (5 , 6500.00 , '2026-04-20T19:30:00', NULL                 , 4, 3, 4),
        (6 , 69600.00, '2026-05-11T12:10:00', '2026-05-11T12:11:20', 2, 2, 5),
        (7 , 15000.00, '2026-06-08T18:25:00', '2026-06-08T18:25:50', 2, 1, 6),
        (8 , 73500.00, '2026-07-15T11:02:00', '2026-07-16T09:30:00', 2, 3, 7),
        (9 , 46400.00, '2026-08-21T20:15:00', '2026-08-21T20:16:05', 2, 2, 8),
        (10, 44600.00, '2026-09-12T14:40:00', NULL                 , 1, 3, 9);
    SET IDENTITY_INSERT dbo.PAGO OFF;

    COMMIT TRANSACTION;
    PRINT 'Precarga finalizada correctamente.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
