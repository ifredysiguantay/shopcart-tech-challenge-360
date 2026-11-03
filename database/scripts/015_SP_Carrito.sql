CREATE OR ALTER PROCEDURE SP_Carritos_ObtenerOCrear
    @IDUsuario     INT = NULL,
    @TokenInvitado UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IDCarrito INT;

    IF @IDUsuario IS NULL AND @TokenInvitado IS NULL
        SET @TokenInvitado = NEWID();

    SELECT @IDCarrito = IDCarrito FROM Carrito
    WHERE Estado = N'Activo'
      AND ((@IDUsuario IS NOT NULL AND IDUsuario = @IDUsuario) OR (@IDUsuario IS NULL AND TokenInvitado = @TokenInvitado));

    IF @IDCarrito IS NULL
    BEGIN TRY
        INSERT Carrito (IDUsuario, TokenInvitado)
        VALUES (@IDUsuario, CASE WHEN @IDUsuario IS NULL THEN NEWID() END);
        SET @IDCarrito = SCOPE_IDENTITY();
    END TRY
    BEGIN CATCH
        IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;
        SELECT @IDCarrito = IDCarrito FROM Carrito WHERE Estado = N'Activo' AND IDUsuario = @IDUsuario;
    END CATCH

    SELECT IDCarrito, TokenInvitado FROM Carrito WHERE IDCarrito = @IDCarrito;
END
GO

CREATE OR ALTER PROCEDURE SP_Carritos_Detalle
    @IDCarrito INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IDCupon INT, @Codigo NVARCHAR(30);
    SELECT @IDCupon = c.IDCupon, @Codigo = cu.Codigo
    FROM Carrito c LEFT JOIN Cupon cu ON cu.IDCupon = c.IDCupon
    WHERE c.IDCarrito = @IDCarrito;

    SELECT f.IDVariante, v.SKU, p.Nombre AS Producto, v.Atributos, f.PrecioUnitario, f.Cantidad,
           f.Subtotal, f.DescuentoLinea, f.TotalLinea, v.ExistenciaDisponible
    FROM FU_Cupones_CalculoDescuento(@IDCarrito, @IDCupon) f
    JOIN Variante v ON v.IDVariante = f.IDVariante
    JOIN Producto p ON p.IDProducto = v.IDProducto
    ORDER BY f.IDVariante;

    SELECT ISNULL(SUM(f.Subtotal), 0) AS Subtotal,
           ISNULL(SUM(f.DescuentoLinea), 0) AS Descuento,
           ISNULL(SUM(f.TotalLinea), 0) AS Total,
           @Codigo AS CodigoCupon
    FROM FU_Cupones_CalculoDescuento(@IDCarrito, @IDCupon) f;
END
GO

CREATE OR ALTER PROCEDURE SP_Carritos_AgregarItem
    @IDCarrito  INT,
    @IDVariante INT,
    @Cantidad   INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF @Cantidad <= 0 THROW 51000, N'La cantidad debe ser mayor a cero.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM Variante v JOIN Producto p ON p.IDProducto = v.IDProducto
        WHERE v.IDVariante = @IDVariante AND v.Activo = 1 AND p.Activo = 1)
        THROW 51001, N'El producto no está disponible.', 1;

    BEGIN TRAN;

    DECLARE @Actual INT = ISNULL((SELECT Cantidad FROM CarritoItem WITH (UPDLOCK, HOLDLOCK) WHERE IDCarrito = @IDCarrito AND IDVariante = @IDVariante), 0);
    DECLARE @Disponible INT = (SELECT ExistenciaDisponible FROM Variante WHERE IDVariante = @IDVariante);

    IF @Actual + @Cantidad > @Disponible
    BEGIN
        DECLARE @Mensaje NVARCHAR(200) = CONCAT(N'Solo hay ', @Disponible, N' unidad(es) disponible(s).');
        THROW 51002, @Mensaje, 1;
    END

    IF @Actual = 0
        INSERT CarritoItem (IDCarrito, IDVariante, Cantidad) VALUES (@IDCarrito, @IDVariante, @Cantidad);
    ELSE
        UPDATE CarritoItem SET Cantidad = @Actual + @Cantidad WHERE IDCarrito = @IDCarrito AND IDVariante = @IDVariante;

    UPDATE Carrito SET FechaActualizacion = SYSUTCDATETIME() WHERE IDCarrito = @IDCarrito;

    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE SP_Carritos_ActualizarItem
    @IDCarrito  INT,
    @IDVariante INT,
    @Cantidad   INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF @Cantidad <= 0 THROW 51000, N'La cantidad debe ser mayor a cero.', 1;

    BEGIN TRAN;

    IF NOT EXISTS (SELECT 1 FROM CarritoItem WITH (UPDLOCK, HOLDLOCK) WHERE IDCarrito = @IDCarrito AND IDVariante = @IDVariante)
        THROW 51001, N'El producto no está en el carrito.', 1;

    DECLARE @Disponible INT = (SELECT ExistenciaDisponible FROM Variante WHERE IDVariante = @IDVariante);
    IF @Cantidad > @Disponible
    BEGIN
        DECLARE @Mensaje NVARCHAR(200) = CONCAT(N'Solo hay ', @Disponible, N' unidad(es) disponible(s).');
        THROW 51002, @Mensaje, 1;
    END

    UPDATE CarritoItem SET Cantidad = @Cantidad WHERE IDCarrito = @IDCarrito AND IDVariante = @IDVariante;
    UPDATE Carrito SET FechaActualizacion = SYSUTCDATETIME() WHERE IDCarrito = @IDCarrito;

    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE SP_Carritos_EliminarItem
    @IDCarrito  INT,
    @IDVariante INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    BEGIN TRAN;
    DELETE FROM CarritoItem WHERE IDCarrito = @IDCarrito AND IDVariante = @IDVariante;
    IF @@ROWCOUNT = 0 THROW 51001, N'El producto no está en el carrito.', 1;
    UPDATE Carrito SET FechaActualizacion = SYSUTCDATETIME() WHERE IDCarrito = @IDCarrito;
    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE SP_Carritos_AplicarCupon
    @IDCarrito INT,
    @IDUsuario INT,
    @Codigo    NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @IDCupon INT;
    EXEC SP_Cupones_Validar @Codigo, @IDUsuario, @IDCarrito, @IDCupon OUTPUT;

    UPDATE Carrito SET IDCupon = @IDCupon, FechaActualizacion = SYSUTCDATETIME() WHERE IDCarrito = @IDCarrito;
END
GO

CREATE OR ALTER PROCEDURE SP_Carritos_QuitarCupon
    @IDCarrito INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Carrito SET IDCupon = NULL, FechaActualizacion = SYSUTCDATETIME() WHERE IDCarrito = @IDCarrito;
END
GO

CREATE OR ALTER PROCEDURE SP_Carritos_Fusionar
    @IDUsuario     INT,
    @TokenInvitado UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @IDInvitado INT, @IDCarritoUsuario INT;
    SELECT @IDInvitado = IDCarrito FROM Carrito WHERE TokenInvitado = @TokenInvitado AND Estado = N'Activo';
    IF @IDInvitado IS NULL RETURN;

    BEGIN TRAN;

    SELECT @IDCarritoUsuario = IDCarrito FROM Carrito WITH (UPDLOCK) WHERE IDUsuario = @IDUsuario AND Estado = N'Activo';

    IF @IDCarritoUsuario IS NULL
        UPDATE Carrito SET IDUsuario = @IDUsuario, TokenInvitado = NULL, FechaActualizacion = SYSUTCDATETIME()
        WHERE IDCarrito = @IDInvitado;
    ELSE
    BEGIN
        MERGE CarritoItem AS destino
        USING (
            SELECT g.IDVariante,
                   CASE WHEN ISNULL(u.Cantidad, 0) + g.Cantidad > v.ExistenciaDisponible
                        THEN v.ExistenciaDisponible ELSE ISNULL(u.Cantidad, 0) + g.Cantidad END AS Cantidad
            FROM CarritoItem g
            JOIN Variante v ON v.IDVariante = g.IDVariante AND v.Activo = 1 AND v.ExistenciaDisponible > 0
            LEFT JOIN CarritoItem u ON u.IDCarrito = @IDCarritoUsuario AND u.IDVariante = g.IDVariante
            WHERE g.IDCarrito = @IDInvitado) AS origen
        ON destino.IDCarrito = @IDCarritoUsuario AND destino.IDVariante = origen.IDVariante
        WHEN MATCHED THEN UPDATE SET Cantidad = origen.Cantidad
        WHEN NOT MATCHED THEN INSERT (IDCarrito, IDVariante, Cantidad) VALUES (@IDCarritoUsuario, origen.IDVariante, origen.Cantidad);

        UPDATE Carrito SET FechaActualizacion = SYSUTCDATETIME() WHERE IDCarrito = @IDCarritoUsuario;
        UPDATE Carrito SET Estado = N'Fusionado' WHERE IDCarrito = @IDInvitado;
    END

    COMMIT;
END
GO
