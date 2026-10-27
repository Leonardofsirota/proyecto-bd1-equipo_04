USE [sistema-venta-libros];
GO

IF TYPE_ID(N'dbo.DetalleVentaType') IS NULL
BEGIN
    EXEC(N'
        CREATE TYPE dbo.DetalleVentaType AS TABLE
        (
            publicacion_id INT NOT NULL PRIMARY KEY,
            cantidad INT NOT NULL
        );
    ');
END;
GO