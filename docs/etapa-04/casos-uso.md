# Casos de uso - Etapa 4

Este documento reúne las consultas de la etapa: qué rol usa cada una, qué requisito de la consigna cubre y qué se considera una venta. Cómo funciona cada consulta se documenta por separado.

## 1. Diagrama

![Diagrama de casos de uso](casos-uso.png)

Los actores son los tres roles de la [Descripción del caso](../etapa-01/descripcion-caso.md#3-usuarios). El diagrama se genera con PlantUML desde [casos-uso.puml](casos-uso.puml).

## 2. Requisitos cubiertos

La consigna pide tres consultas mínimas:

- **Factura/comprobante:** encabezado y detalle de una venta, con subtotal por renglón y total acumulado.
- **Reporte agregado:** total de ventas por vendedor o por categoría en un rango de fechas, con `GROUP BY`, `SUM` y `COUNT`.
- **Consulta avanzada:** al menos tres tablas unidas con `JOIN` y filtros con `HAVING` o subconsultas.

| Caso de uso                             | Requisito           | Script                                                                                                 |
| --------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------ |
| Consultar ofertas vigentes por libro    | —                   | [catalogo/ofertas-vigentes-por-libro.sql](../../sql/consultas/catalogo/ofertas-vigentes-por-libro.sql) |
| Consultar comprobante de venta          | Factura/comprobante | [comprobantes/factura-comprobante.sql](../../sql/consultas/comprobantes/factura-comprobante.sql)       |
| Consultar total de ventas por vendedor  | Reporte agregado    | [ventas/total-ventas-por-vendedor.sql](../../sql/consultas/ventas/total-ventas-por-vendedor.sql)       |
| Consultar total de ventas por categoría | Reporte agregado    | [ventas/total-ventas-por-categoria.sql](../../sql/consultas/ventas/total-ventas-por-categoria.sql)     |
| Consultar libros más vendidos           | Consulta avanzada   | [ventas/libros-mas-vendidos.sql](../../sql/consultas/ventas/libros-mas-vendidos.sql)                   |
| Consultar pedidos con pago aprobado     | —                   | [pagos/pedidos-con-pago-aprobado.sql](../../sql/consultas/pagos/pedidos-con-pago-aprobado.sql)         |
| Consultar pedidos sin pago aprobado     | Consulta avanzada   | [pagos/pedidos-sin-pago-aprobado.sql](../../sql/consultas/pagos/pedidos-sin-pago-aprobado.sql)         |

Las dos consultas sin requisito responden a necesidades del dominio: comparar las ofertas de un libro antes de comprarlo y ver qué pedidos ya se cobraron.

`control/control-carga-datos.sql` no figura porque no es un caso de uso: revisa la precarga de datos y forma parte de las [pruebas de la Etapa 3](../etapa-03/pruebas-validacion.md#4-datos-de-prueba).

## 3. Qué se considera una venta

Una venta es un pedido con un pago aprobado. Este criterio lo aplican el comprobante y las consultas de `ventas/`; las de `pagos/` separan los pedidos que lo cumplen de los que no.

- **No se filtra por el estado del pedido.** Según RN19, el pedido se confirma cuando se aprueba su pago, así que el pago aprobado basta. Los [datos de prueba](../etapa-03/pruebas-validacion.md#4-datos-de-prueba) respetan esa regla; el motor la controlará a partir de la Etapa 5.
- **Un pedido puede tener varios intentos de pago, pero a lo sumo uno aprobado** (RN24, RN29). Las consultas que solo necesitan saber si el pedido es una venta usan `EXISTS`, para no repetir filas por cada intento. Las que muestran datos del pago, como el comprobante y los pedidos con pago aprobado, se unen directamente al pago aprobado: al haber uno solo, no se duplican filas.
