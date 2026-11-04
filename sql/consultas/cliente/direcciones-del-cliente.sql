/* Direcciones de un cliente: las direcciones que registró, con su ciudad y
   provincia, para elegir el destino de un nuevo pedido (RN05 y RN18). El
   pedido guarda una copia de la dirección elegida (RN27), así que editarla
   después no altera los pedidos anteriores.

   Si el cliente no registró direcciones, la consulta no devuelve filas. */

DECLARE @cliente_id INT = 347;

SELECT
    D.direccion_id,
    -- Si no tiene piso o departamento, la suma con NULL da NULL y CONCAT omite
    -- esa parte.
    CONCAT(
        D.calle, ' ', D.altura,
        ', piso ' + D.piso,
        ', depto. ' + D.departamento
    ) AS direccion,
    D.codigo_postal,
    CI.nombre AS ciudad,
    PR.nombre AS provincia,
    D.referencia
FROM dbo.DIRECCION AS D
INNER JOIN dbo.CIUDAD AS CI
    ON D.ciudad_id = CI.ciudad_id
INNER JOIN dbo.PROVINCIA AS PR
    ON CI.provincia_id = PR.provincia_id
WHERE D.usuario_id = @cliente_id
ORDER BY D.direccion_id;
