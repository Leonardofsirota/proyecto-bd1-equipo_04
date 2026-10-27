CREATE OR ALTER FUNCTION dbo.fn_ImporteDescuento
(
    @TotalCompra DECIMAL(18, 2),
    @Porcentaje DECIMAL(5, 2)
)
RETURNS DECIMAL(18, 2)
AS
BEGIN
    IF @TotalCompra IS NULL OR @Porcentaje IS NULL
        RETURN NULL;

    IF @TotalCompra < 0 OR @Porcentaje < 0
        RETURN NULL;

    IF @Porcentaje > 100
        RETURN NULL;

    RETURN CAST(
        ROUND(
            @TotalCompra * @Porcentaje / 100.0,
            2
        )
        AS DECIMAL(18, 2)
    );
END;
GO