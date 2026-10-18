# Implementación - Etapa 3

Este documento explica cómo el modelo relacional de la Etapa 2 se llevó a SQL Server: cómo se crea la base, qué tipos de datos y restricciones se eligieron y cómo se cargaron los datos de prueba. El detalle de cada restricción está en [Restricciones de integridad](restricciones-integridad.md), y su verificación, en [Pruebas y validación](pruebas-validacion.md).

## 1. Motor y scripts

La base se implementó en SQL Server con T-SQL, compatible con la versión 2012 o superior. La implementación se reparte en dos scripts, que se ejecutan completos y en este orden:

| Paso | Script                             | Qué hace                                                                |
| ---- | ---------------------------------- | ----------------------------------------------------------------------- |
| 1    | `sql/ddl/sistema-venta-libros.sql` | Crea la base `sistema-venta-libros`, sus 21 tablas y sus restricciones. |
| 2    | `sql/dml/datos_prueba.sql`         | Carga los datos de prueba.                                              |

Los dos scripts están protegidos contra una segunda ejecución por error: el primero se detiene si la base ya existe, y el segundo, si alguna tabla ya tiene datos. En ambos casos avisan y no modifican nada. Además, fijan por sí mismos las opciones de sesión que necesitan, por lo que funcionan igual desde SSMS que desde la línea de comandos (`sqlcmd`).

## 2. De la relación a la tabla

Cada relación del modelo lógico se convirtió en una tabla con el mismo nombre, y cada atributo, en una columna. Por ejemplo, la relación PEDIDO_DETALLE (**pedido_detalle_id**, cantidad, precio_unitario, pedido_id, publicacion_id) quedó así:

```sql
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
```

Todas las tablas siguen el mismo patrón:

- **Clave primaria.** Es un entero que el motor numera automáticamente (`IDENTITY`). Además, las filas se almacenan ordenadas por ella.
- **Claves foráneas.** Hay una por cada referencia del modelo lógico.
- **Unicidad.** Conserva las claves candidatas identificadas en la normalización, como el par pedido-publicación de este ejemplo.
- **Validaciones.** Los `CHECK` limitan los valores que acepta cada columna.
- **Obligatoriedad.** Solo los atributos opcionales del modelo admiten valores vacíos; el resto se declara `NOT NULL`.

Cada restricción tiene un nombre explícito, con un prefijo que indica su tipo:

| Prefijo | Restricción       | Ejemplo                    |
| ------- | ----------------- | -------------------------- |
| `pk_`   | Clave primaria    | `pk_pedido_detalle`        |
| `fk_`   | Clave foránea     | `fk_pedido_detalle_pedido` |
| `uq_`   | Unicidad          | `uq_usuario_dni`           |
| `chk_`  | Validación        | `chk_publicacion_stock`    |
| `df_`   | Valor por defecto | `df_pedido_fecha_pedido`   |

Así, cuando una operación viola una regla, el mensaje de error indica exactamente cuál, en lugar de mostrar un nombre generado por el motor, como `CK__PEDIDO_D__3A81B327`.

## 3. Orden de creación

Una tabla solo puede referenciar a otra que ya exista. Por eso las tablas se crean en seis grupos, y cada uno va después de aquellos de los que depende:

| Paso | Grupo         | Tablas                                           |
| ---- | ------------- | ------------------------------------------------ |
| 1    | Catálogos     | Los diez catálogos, de USUARIO_ROL a PAGO_METODO |
| 2    | Ubicación     | PROVINCIA, CIUDAD                                |
| 3    | Usuarios      | USUARIO, DIRECCION                               |
| 4    | Libros        | AUTOR, LIBRO, AUTOR_LIBRO                        |
| 5    | Publicaciones | PUBLICACION                                      |
| 6    | Ventas        | PEDIDO, PEDIDO_DETALLE, PAGO                     |

Con este orden, cada clave foránea se declara dentro de su propia tabla, sin modificaciones posteriores. El script de datos sigue la misma secuencia.

## 4. Tipos de datos

Cada tipo se eligió según lo que representa el dato:

| Dato                  | Tipo              | Ejemplos                                          | Motivo                                               |
| --------------------- | ----------------- | ------------------------------------------------- | ---------------------------------------------------- |
| Identificadores       | `INT IDENTITY`    | `libro_id`, `pedido_id`                           | El motor los genera sin repetirlos.                  |
| Textos                | `VARCHAR(n)`      | `titulo`, `calle`, `email`                        | Longitud ajustada a lo que necesita cada dato.       |
| Textos largos         | `VARCHAR(MAX)`    | `biografia`, `referencia`                         | Contenido libre, sin un máximo previsible.           |
| Códigos de largo fijo | `CHAR(n)`         | `isbn` (13), `isni` (16)                          | Siempre tienen la misma cantidad de caracteres.      |
| Otros códigos         | `VARCHAR(n)`      | `dni`, `telefono`, `codigo_postal`                | Son códigos, no cantidades: no se calcula con ellos. |
| Importes              | `DECIMAL(18, 2)`  | `precio`, `precio_unitario`, `importe`            | Valores exactos, sin errores de redondeo.            |
| Enteros               | `INT`, `SMALLINT` | `stock`, `cantidad`, `anio_publicacion`           | El año usa `SMALLINT`, que alcanza y ocupa menos.    |
| Fechas                | `DATE`            | `fecha_nacimiento`, `fecha_fallecimiento`         | Solo interesa el día.                                |
| Momentos              | `DATETIME`        | `fecha_pedido`, `fecha_pago`, `fecha_eliminacion` | Registran el día y la hora del hecho.                |
| Indicadores           | `BIT`             | `disponible`                                      | Solo admiten sí o no.                                |

Dos longitudes siguen estándares conocidos. El email admite 254 caracteres, el máximo de una dirección de correo. La contraseña no se almacena: solo se guarda su hash, en una columna de 255 caracteres.

## 5. Integridad de los datos

### 5.1 Claves foráneas

Las 22 claves foráneas usan la regla por defecto del motor, `NO ACTION`, tanto para borrados como para modificaciones: no se puede eliminar una fila mientras otra la referencie. No se usó la propagación en cascada, a propósito:

- **Borrado.** Usuarios y publicaciones no se eliminan, se dan de baja (RN28). Con un borrado en cascada, eliminar un vendedor arrastraría sus publicaciones y los renglones de los pedidos que las incluyen, y el historial de ventas quedaría incompleto.
- **Modificación.** Las claves primarias son identificadores generados que nunca cambian; de hecho, SQL Server no permite modificar una columna `IDENTITY`. No hay cambios que propagar.

### 5.2 Unicidad

Las 17 restricciones `UNIQUE` impiden repetir los identificadores naturales (DNI y email del usuario, RN03; ISBN del libro, RN06), los nombres de los catálogos y de las provincias, una ciudad dentro de su provincia y los pares de las tablas intermedias (un autor en un libro; una publicación en un pedido, RN16). Cada una crea un índice, que además agiliza las búsquedas por ese dato.

Dos reglas necesitan algo más que una restricción `UNIQUE`, y se resuelven con índices únicos filtrados:

- **ISNI del autor.** Es opcional, pero no puede repetirse. SQL Server trata el valor vacío (`NULL`) como un valor más y, con una restricción `UNIQUE`, lo admitiría una sola vez: no podría haber dos autores sin ISNI. El índice filtrado exige la unicidad solo a los autores que lo tienen:

  ```sql
  CREATE UNIQUE NONCLUSTERED INDEX uq_autor_isni
      ON dbo.AUTOR (isni)
      WHERE isni IS NOT NULL;
  ```

- **Publicaciones vigentes.** Un vendedor no puede tener dos publicaciones vigentes del mismo libro en la misma condición (RN11), pero sí volver a publicarlo después de dar de baja la anterior. El índice exige la unicidad solo a las publicaciones sin fecha de baja.

Estos dos índices se crean después de su tabla, porque SQL Server 2012 no permite declararlos dentro de `CREATE TABLE`.

### 5.3 Validaciones y valores por defecto

Los 18 `CHECK` controlan reglas que dependen solo de los datos de la propia fila:

| Control           | Ejemplos                                                                                                  | Reglas           |
| ----------------- | --------------------------------------------------------------------------------------------------------- | ---------------- |
| Valores positivos | Precios, importes, cantidades, páginas y alturas mayores que cero; stock nunca negativo.                  | RN10, RN13, RN15 |
| Formato           | DNI de 7 u 8 dígitos; email con forma de dirección; ISBN e ISNI solo con caracteres válidos.              | —                |
| Fechas coherentes | El pago no se acredita antes de iniciarse; una baja no es anterior al alta; nacimientos anteriores a hoy. | RN25             |
| Estado coherente  | Una publicación dada de baja no puede figurar como disponible.                                            | RN28             |

Los cuatro valores por defecto completan datos que el sistema ya conoce: el pedido, la publicación y el pago registran como fecha de creación el momento en que se insertan, y toda publicación nueva queda disponible.

### 5.4 Lo que el esquema no controla

Algunas reglas dependen de otras filas o de otras tablas; por ejemplo, que solo un cliente pueda hacer pedidos o que la cantidad pedida no supere el stock. Estas restricciones no alcanzan para expresarlas. Están listadas en [Modelo relacional](../etapa-02/modelo-relacional.md#5-reglas-que-el-esquema-no-garantiza) y se implementan en la Etapa 5.

## 6. Datos de prueba

### 6.1 Cómo se cargan

- **Todo o nada.** La carga corre en una única transacción: si una inserción falla, se deshace todo y las tablas quedan vacías.
- **Identificadores fijos.** Los ID se cargan de forma explícita, en lugar de dejar que el motor los genere. Así, las referencias apuntan siempre a las mismas filas, y las consultas y los documentos pueden citar «el pedido 3» con la certeza de que es el mismo en cualquier instalación. En publicaciones, pedidos y pagos, además, los ID siguen el orden cronológico.
- **Fechas sin ambigüedad.** Se escriben en formatos que el motor interpreta igual en cualquier idioma de sesión (`'20260305'` o `'2026-03-05T10:15:00'`). De lo contrario, una fecha como 05/03 podría leerse como 5 de marzo en una instalación y como 3 de mayo en otra.
- **Datos realistas.** Los títulos, los autores y las ciudades son reales; los 74 municipios de Corrientes provienen de la API Georef de datos.gob.ar. Los DNI, los correos, los teléfonos, los ISBN, los ISNI y los hashes de contraseña son ficticios.

### 6.2 Cantidad de registros

| Grupo              | Registros por tabla                                                                            |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| Principales        | USUARIO: 500; DIRECCION: 603; AUTOR: 362; LIBRO: 500; PUBLICACION: 791; PEDIDO: 600; PAGO: 718 |
| Intermedias        | AUTOR_LIBRO: 581; PEDIDO_DETALLE: 1.290                                                        |
| Ubicación          | PROVINCIA: 1; CIUDAD: 74                                                                       |
| Catálogos abiertos | IDIOMA: 10; CATEGORIA: 30; NACIONALIDAD: 32; EDITORIAL: 60                                     |
| Catálogos cerrados | USUARIO_ROL y PAGO_METODO: 3; PEDIDO_ESTADO y PAGO_ESTADO: 4; CONDICION: 5; ENCUADERNACION: 2  |

En total se cargan 6.173 filas. Los 500 usuarios son 3 administradores, 40 vendedores y 457 clientes.

La mayoría de las tablas alcanza o supera los 8 a 10 registros requeridos, y las principales y las intermedias los superan ampliamente. Las excepciones son deliberadas:

- **Catálogos cerrados.** Tienen exactamente los valores que fijan las reglas de negocio o el rubro: tres roles (RN01), tres métodos de pago (RN21), cuatro estados de pago (RN23), cuatro estados de pedido (RN19, RN20), cinco grados de conservación y dos tipos de encuadernación. Agregar valores inventados contradiría esas reglas.
- **Provincia.** La versión inicial solo contempla Corrientes, como se explica en [Decisiones de diseño](../etapa-02/decisiones-diseno.md) (sección 2). Sus 74 municipios aportan el volumen de la ubicación.

### 6.3 Escenarios representados

Los datos se armaron para que cada situación prevista por las reglas aparezca varias veces. La tabla indica cuántos casos hay y un ejemplo de cada uno. Esto también sirve como base para las consultas de la Etapa 4.

| Escenario                                                      | Casos                                                         | Ejemplo                                       | Reglas     |
| -------------------------------------------------------------- | ------------------------------------------------------------- | --------------------------------------------- | ---------- |
| Precio de venta distinto del precio actual de la publicación   | 795 de los 1.290 renglones                                    | Pedido 94                                     | RN26       |
| Libro con varios autores                                       | 58 libros, con dos a cuatro autores                           | Libro 2                                       | RN08       |
| Un libro ofrecido por varios vendedores, en distinta condición | 93 libros, con tres o más vendedores                          | Libro 4: seis vendedores, cuatro condiciones  | RN11       |
| Libro publicado otra vez después de dar de baja la oferta      | 14 publicaciones                                              | Publicación 8, publicada otra vez como la 298 | RN11, RN28 |
| Pedido con publicaciones de varios vendedores                  | 258 pedidos                                                   | Pedido 216                                    | RN16       |
| Pago rechazado o cancelado seguido de uno aprobado             | 108 pedidos                                                   | Pedido 151                                    | RN24, RN29 |
| Pedidos en cada estado                                         | 555 entregados, 12 confirmados, 14 pendientes y 19 cancelados | Pedidos 94, 375, 410 y 179                    | RN19, RN20 |
| Publicación agotada, pausada o dada de baja                    | 90, 27 y 49 publicaciones                                     | Publicaciones 230, 6 y 247                    | RN12, RN28 |
| Usuario dado de baja que conserva su historial                 | 23 clientes y 2 vendedores                                    | Cliente 10                                    | RN28       |
| Cliente con varias direcciones                                 | 70 clientes con dos y 18 con tres                             | Cliente 6                                     | RN05       |
| Autor sin ISNI                                                 | 49 autores                                                    | Autores 7 y 10                                | —          |

Además, los datos respetan las reglas que el esquema todavía no controla: solo los clientes hacen pedidos y solo los vendedores publican, cada pedido copia una de las direcciones de su cliente, cada pago cubre el total de su pedido y el stock cargado ya tiene descontadas las ventas confirmadas.
