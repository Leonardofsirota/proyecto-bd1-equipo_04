<div align="center">

# Marketplace de Libros

Sistema online de compra y venta de libros, al estilo de un marketplace.

Este repositorio recopila la documentación académica y los scripts SQL del trabajo práctico integrador de la cátedra Bases de Datos I (FaCENA-UNNE).

</div>

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
- [Total de ventas por vendedor](docs/etapa-04/total-ventas-por-vendedor.md)
- [Total de ventas por categoría](docs/etapa-04/total-ventas-por-categoria.md)
- [Libros más vendidos](docs/etapa-04/libros-mas-vendidos.md)
- [Pedidos con pago aprobado](docs/etapa-04/pedidos-con-pago-aprobado.md)
- [Pedidos sin pago aprobado](docs/etapa-04/pedidos-sin-pago-aprobado.md)
- [Control de carga de datos](docs/etapa-04/control-carga-datos.md)
