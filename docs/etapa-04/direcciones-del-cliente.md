# Direcciones del cliente - Etapa 4

Este documento explica la consulta [`cliente/direcciones-del-cliente.sql`](../../sql/consultas/cliente/direcciones-del-cliente.sql), que resuelve el caso de uso [Consultar direcciones del cliente](casos-uso.md#2-requisitos-cubiertos).

## 1. Qué hace

Lista las direcciones que registró un cliente, con su código postal, ciudad, provincia y referencia. Si no registró ninguna, la consulta no devuelve filas.

## 2. Quién la usa

El **Cliente**, para elegir el destino de un nuevo pedido (RN05, RN18).

## 3. Cómo lo resuelve

- **Cliente elegido:** se indica con la variable `@cliente_id`.
- **Uniones:** va de la dirección a su ciudad y de la ciudad a su provincia.
- **Dirección en una columna:** `CONCAT` reúne la calle, la altura, el piso y el departamento. El piso y el departamento se agregan con `+`: si faltan, la suma da `NULL` y `CONCAT` omite esa parte, incluido su texto («, piso »).
- **Orden:** por número de dirección.

El pedido guarda una copia de la dirección elegida (RN27), así que editar lo que muestra esta consulta no altera los pedidos anteriores.

## 4. Resultado esperado

Con `@cliente_id = 347` devuelve dos direcciones:

| Dirección | Calle y altura    | Código postal | Ciudad      | Provincia  | Referencia                   |
| --------: | ----------------- | ------------- | ----------- | ---------- | ---------------------------- |
|       416 | Juan Pujol 966    | 3420          | Saladas     | Corrientes | —                            |
|       417 | Av. Belgrano 1251 | 3432          | Bella Vista | Corrientes | Oficina, horario de 8 a 13 h |
