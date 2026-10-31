# Marketplace de Libros

Sistema online de compra y venta de libros, al estilo de un marketplace.

Este repositorio recopila la documentación académica y los scripts SQL del trabajo práctico integrador de la cátedra Bases de Datos I (FaCENA-UNNE).

<br>

## Presentación

Librerías y particulares publican sus libros, nuevos o usados, y los clientes los encuentran y los compran en un solo lugar, sin recorrer a cada vendedor por separado.

Todos los vendedores comparten un mismo catálogo, por lo que un título puede tener varias ofertas, cada una con su propio precio, stock y estado del ejemplar. El cliente las compara y elige la que más le conviene.

Luego arma su pedido, que puede reunir libros de distintos vendedores, indica dónde quiere recibirlo y lo paga en línea. Cuando el pago se aprueba, el pedido se confirma y sigue su curso hasta la entrega.

El modelo de datos, las reglas de negocio y las consultas se explican en detalle en la [documentación](docs/).

<br>

## Detalles técnicos

### Herramientas

<p align="center">
  <a href="https://www.microsoft.com/sql-server"><picture><source media="(prefers-color-scheme: dark)" srcset="recursos-readme/tools/sql-server-oscuro.png"><img src="recursos-readme/tools/sql-server-claro.png" alt="SQL Server" width="150"></picture></a>
  <a href="https://learn.microsoft.com/sql/ssms/sql-server-management-studio-ssms"><picture><source media="(prefers-color-scheme: dark)" srcset="recursos-readme/tools/ssms-oscuro.png"><img src="recursos-readme/tools/ssms-claro.png" alt="SQL Server Management Studio (SSMS)" width="150"></picture></a>
  <a href="https://erdplus.com"><picture><source media="(prefers-color-scheme: dark)" srcset="recursos-readme/tools/erdplus-oscuro.png"><img src="recursos-readme/tools/erdplus-claro.png" alt="ERDPlus" width="150"></picture></a>
  <a href="https://plantuml.com"><picture><source media="(prefers-color-scheme: dark)" srcset="recursos-readme/tools/plantuml-oscuro.png"><img src="recursos-readme/tools/plantuml-claro.png" alt="PlantUML" width="150"></picture></a>
</p>

### Documentación

**Etapa 1 · Requerimientos**

- [Descripción del caso](docs/etapa-01/descripcion-caso.md)
- [Alcance](docs/etapa-01/alcance.md)
- [Reglas de negocio](docs/etapa-01/reglas-negocio.md)

**Etapa 2 · Modelado**

- [Diagrama entidad-relación](docs/etapa-02/der/der.png)
- [Modelo relacional](docs/etapa-02/modelo-relacional.md)
- [Diagrama del modelo relacional](docs/etapa-02/relacional/relacional.png)
- [Normalización](docs/etapa-02/normalizacion.md)
- [Decisiones de diseño](docs/etapa-02/decisiones-diseno.md)

**Etapa 3 · Implementación**

- [Implementación](docs/etapa-03/implementacion.md)
- [Restricciones de integridad](docs/etapa-03/restricciones-integridad.md)
- [Pruebas y validación](docs/etapa-03/pruebas-validacion.md)

**Etapa 4 · Consultas**

- [Casos de uso](docs/etapa-04/casos-uso.md)
- [Ofertas vigentes por libro](docs/etapa-04/ofertas-vigentes-por-libro.md)
- [Comprobante de venta](docs/etapa-04/factura-comprobante.md)
- [Pedidos del cliente](docs/etapa-04/pedidos-del-cliente.md)
- [Direcciones del cliente](docs/etapa-04/direcciones-del-cliente.md)
- [Búsqueda en el catálogo](docs/etapa-04/buscar-libros-catalogo.md)
- [Publicaciones del vendedor](docs/etapa-04/publicaciones-del-vendedor.md)
- [Pedidos a entregar](docs/etapa-04/pedidos-a-entregar.md)
- [Ventas por publicación](docs/etapa-04/ventas-por-publicacion.md)
- [Total de ventas por categoría](docs/etapa-04/total-ventas-por-categoria.md)
- [Ventas por mes](docs/etapa-04/ventas-por-mes.md)
- [Libros más vendidos](docs/etapa-04/libros-mas-vendidos.md)
- [Total de ventas por vendedor](docs/etapa-04/total-ventas-por-vendedor.md)
- [Pedidos con pago aprobado](docs/etapa-04/pedidos-con-pago-aprobado.md)
- [Pedidos sin pago aprobado](docs/etapa-04/pedidos-sin-pago-aprobado.md)
- [Pagos por método](docs/etapa-04/pagos-por-metodo.md)
- [Usuarios por rol](docs/etapa-04/usuarios-por-rol.md)
- [Control de carga de datos](docs/etapa-04/control-carga-datos.md)

<br>

## Cómo instalar

**Requisitos**

- SQL Server 2012 o superior
- SSMS

**Pasos**

1. Conectarse a SQL Server desde SSMS con un usuario que pueda crear bases de datos.

2. Abrir [`sql/ddl/sistema-venta-libros.sql`](sql/ddl/sistema-venta-libros.sql) y ejecutarlo completo con <kbd>F5</kbd>. Crea la base `sistema-venta-libros` y sus tablas.

3. Abrir [`sql/dml/datos_prueba.sql`](sql/dml/datos_prueba.sql) y ejecutarlo completo con <kbd>F5</kbd>. Carga los datos de prueba.

4. Abrir [`calcular_descuento_pedido/script.sql`](sql/tecnico/procedimientos_funciones/calcular_descuento_pedido/script.sql) y ejecutarlo completo con <kbd>F5</kbd>. Después, hacer lo mismo con [`registrar_venta/script.sql`](sql/tecnico/procedimientos_funciones/registrar_venta/script.sql). Crean las funciones y los procedimientos de la Etapa 5, entre ellos `fn_StockLibre`, que necesitan las consultas de ofertas y de catálogo.

> [!NOTE]
> - El orden importa: cada paso necesita lo que crea el anterior.
> - Si la base ya existe, el paso 2 se detiene sin modificarla. Para reinstalar desde cero, hay que eliminarla antes.
