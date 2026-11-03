CREATE OR ALTER PROCEDURE SP_Cupones_Crear
    @Codigo               NVARCHAR(30),
    @Tipo                 NVARCHAR(12),
    @Valor                DECIMAL(12,2),
    @FechaInicio          DATETIME2(0),
    @FechaFin             DATETIME2(0),
    @MontoMinimo          DECIMAL(12,2) = 0,
    @LimiteUsosTotal      INT,
    @LimiteUsosPorCliente INT,
    @IDCategoria          INT = NULL,
    @IDUsuario            INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF @IDCategoria IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Categoria WHERE IDCategoria = @IDCategoria)
        THROW 51001, N'La categoría no existe.', 1;

    BEGIN TRAN;

    INSERT Cupon (Codigo, Tipo, Valor, FechaInicio, FechaFin, MontoMinimo, LimiteUsosTotal, LimiteUsosPorCliente, IDCategoria)
    VALUES (@Codigo, @Tipo, @Valor, @FechaInicio, @FechaFin, @MontoMinimo, @LimiteUsosTotal, @LimiteUsosPorCliente, @IDCategoria);

    DECLARE @IDCupon INT = SCOPE_IDENTITY();
    DECLARE @Nuevo NVARCHAR(MAX) = (SELECT c.* FROM Cupon c WHERE c.IDCupon = @IDCupon FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Cupones', N'Cupon', @IDCupon, N'Crear', NULL, @Nuevo;

    COMMIT;

    SELECT @IDCupon AS IDCupon;
END
GO

CREATE OR ALTER PROCEDURE SP_Cupones_Actualizar
    @IDCupon              INT,
    @Tipo                 NVARCHAR(12),
    @Valor                DECIMAL(12,2),
    @FechaInicio          DATETIME2(0),
    @FechaFin             DATETIME2(0),
    @MontoMinimo          DECIMAL(12,2),
    @LimiteUsosTotal      INT,
    @LimiteUsosPorCliente INT,
    @IDCategoria          INT = NULL,
    @Activo               BIT,
    @IDUsuario            INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    BEGIN TRAN;

    DECLARE @Anterior NVARCHAR(MAX) = (
        SELECT c.* FROM Cupon c WITH (UPDLOCK, ROWLOCK) WHERE c.IDCupon = @IDCupon FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    IF @Anterior IS NULL THROW 51001, N'Cupón no encontrado.', 1;
    IF @IDCategoria IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Categoria WHERE IDCategoria = @IDCategoria)
        THROW 51001, N'La categoría no existe.', 1;

    UPDATE Cupon
    SET Tipo = @Tipo, Valor = @Valor, FechaInicio = @FechaInicio, FechaFin = @FechaFin, MontoMinimo = @MontoMinimo,
        LimiteUsosTotal = @LimiteUsosTotal, LimiteUsosPorCliente = @LimiteUsosPorCliente,
        IDCategoria = @IDCategoria, Activo = @Activo
    WHERE IDCupon = @IDCupon;

    DECLARE @Nuevo NVARCHAR(MAX) = (SELECT c.* FROM Cupon c WHERE c.IDCupon = @IDCupon FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    DECLARE @Accion NVARCHAR(20) = CASE WHEN @Activo = 0 THEN N'Desactivar' ELSE N'Actualizar' END;
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Cupones', N'Cupon', @IDCupon, @Accion, @Anterior, @Nuevo;

    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE SP_Cupones_Listar
    @Pagina       INT = 1,
    @TamanoPagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.IDCupon, c.Codigo, c.Tipo, c.Valor, c.FechaInicio, c.FechaFin, c.MontoMinimo,
           c.LimiteUsosTotal, c.LimiteUsosPorCliente, c.IDCategoria, c.UsosActuales, c.Activo,
           COUNT(*) OVER () AS TotalRegistros
    FROM Cupon c
    ORDER BY c.IDCupon DESC
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE SP_Cupones_Eliminar
    @IDCupon   INT,
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Cupon WHERE IDCupon = @IDCupon)
        THROW 51001, N'Cupón no encontrado.', 1;

    BEGIN TRAN;

    IF EXISTS (SELECT 1 FROM CuponUso WHERE IDCupon = @IDCupon) OR EXISTS (SELECT 1 FROM Pedido WHERE IDCupon = @IDCupon)
    BEGIN
        UPDATE Cupon SET Activo = 0 WHERE IDCupon = @IDCupon;
        EXEC SP_Bitacora_Registrar @IDUsuario, N'Cupones', N'Cupon', @IDCupon, N'Desactivar', N'{"Activo":true}', N'{"Activo":false}';
        COMMIT;
        SELECT N'Desactivado' AS Resultado;
        RETURN;
    END

    UPDATE Carrito SET IDCupon = NULL WHERE IDCupon = @IDCupon;
    DELETE FROM Checkout WHERE IDCupon = @IDCupon AND Estado <> N'Activo';
    DELETE FROM Cupon WHERE IDCupon = @IDCupon;
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Cupones', N'Cupon', @IDCupon, N'Eliminar', NULL, NULL;

    COMMIT;
    SELECT N'Eliminado' AS Resultado;
END
GO

CREATE OR ALTER PROCEDURE SP_Cupones_Validar
    @Codigo    NVARCHAR(30),
    @IDUsuario INT,
    @IDCarrito INT,
    @IDCupon   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Activo BIT, @Inicio DATETIME2(0), @Fin DATETIME2(0), @Minimo DECIMAL(12,2),
            @LimiteTotal INT, @LimiteCliente INT, @Usos INT, @Ahora DATETIME2(0) = SYSUTCDATETIME();

    SELECT @IDCupon = IDCupon, @Activo = Activo, @Inicio = FechaInicio, @Fin = FechaFin, @Minimo = MontoMinimo,
           @LimiteTotal = LimiteUsosTotal, @LimiteCliente = LimiteUsosPorCliente, @Usos = UsosActuales
    FROM Cupon WHERE Codigo = @Codigo;

    IF @IDCupon IS NULL THROW 51001, N'El cupón no existe.', 1;
    IF @Activo = 0 THROW 51004, N'El cupón no está activo.', 1;
    IF @Ahora < @Inicio THROW 51004, N'El cupón aún no está vigente.', 1;
    IF @Ahora > @Fin THROW 51004, N'El cupón está vencido.', 1;
    IF @Usos >= @LimiteTotal THROW 51004, N'El cupón está agotado.', 1;

    IF (SELECT COUNT(*) FROM CuponUso WHERE IDCupon = @IDCupon AND IDUsuario = @IDUsuario AND Anulado = 0) >= @LimiteCliente
        THROW 51004, N'Ya alcanzaste el límite de usos de este cupón.', 1;

    IF NOT EXISTS (SELECT 1 FROM FU_Cupones_CalculoDescuento(@IDCarrito, @IDCupon) WHERE Elegible = 1)
        THROW 51004, N'El cupón no aplica a los productos de tu carrito.', 1;

    DECLARE @Subtotal DECIMAL(12,2) = (SELECT ISNULL(SUM(Subtotal), 0) FROM FU_Cupones_CalculoDescuento(@IDCarrito, @IDCupon));
    IF @Subtotal < @Minimo
    BEGIN
        DECLARE @Mensaje NVARCHAR(200) = CONCAT(N'El monto mínimo de compra para este cupón es Q', FORMAT(@Minimo, 'N2'), N'.');
        THROW 51004, @Mensaje, 1;
    END
END
GO
