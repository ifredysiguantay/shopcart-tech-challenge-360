CREATE OR ALTER PROCEDURE SP_Inventario_AplicarMovimiento
    @IDVariante       INT,
    @Tipo             NVARCHAR(12),
    @Cantidad         INT,
    @Motivo           NVARCHAR(250),
    @IDUsuario        INT = NULL,
    @IDPedido         INT = NULL,
    @ReservaALiberar  INT = 0
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Variante WHERE IDVariante = @IDVariante)
        THROW 51001, N'Variante no encontrada.', 1;

    UPDATE Variante
    SET ExistenciaFisica = ExistenciaFisica + @Cantidad,
        ExistenciaReservada = ExistenciaReservada - @ReservaALiberar
    WHERE IDVariante = @IDVariante
      AND ExistenciaFisica + @Cantidad >= 0
      AND ExistenciaFisica + @Cantidad >= ExistenciaReservada - @ReservaALiberar;

    IF @@ROWCOUNT = 0
        THROW 51004, N'La existencia resultante no puede ser negativa ni menor a las unidades reservadas.', 1;

    INSERT MovimientoInventario (IDVariante, Tipo, Cantidad, Motivo, IDUsuario, IDPedido)
    VALUES (@IDVariante, @Tipo, @Cantidad, @Motivo, @IDUsuario, @IDPedido);
END
GO

CREATE OR ALTER PROCEDURE SP_Inventario_RegistrarMovimiento
    @IDVariante INT,
    @Tipo       NVARCHAR(12),
    @Cantidad   INT,
    @Motivo     NVARCHAR(250),
    @IDUsuario  INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF @Tipo NOT IN (N'Entrada', N'Ajuste')
        THROW 51000, N'Solo se permiten movimientos manuales de tipo Entrada o Ajuste.', 1;
    IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, N'')))) = 0
        THROW 51000, N'El motivo es obligatorio.', 1;
    IF @Cantidad = 0 OR (@Tipo = N'Entrada' AND @Cantidad < 0)
        THROW 51000, N'La cantidad es inválida para el tipo de movimiento.', 1;

    BEGIN TRAN;

    DECLARE @Anterior INT = (SELECT ExistenciaFisica FROM Variante WITH (UPDLOCK, ROWLOCK) WHERE IDVariante = @IDVariante);
    IF @Anterior IS NULL THROW 51001, N'Variante no encontrada.', 1;

    EXEC SP_Inventario_AplicarMovimiento @IDVariante, @Tipo, @Cantidad, @Motivo, @IDUsuario;

    DECLARE @ValorNuevo NVARCHAR(MAX) = CAST(@Anterior + @Cantidad AS NVARCHAR(20));
    DECLARE @ValorAnterior NVARCHAR(MAX) = CAST(@Anterior AS NVARCHAR(20));
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Existencias', N'Variante', @IDVariante, @Tipo, @ValorAnterior, @ValorNuevo;

    COMMIT;

    SELECT v.IDVariante, v.SKU, v.ExistenciaFisica, v.ExistenciaReservada, v.ExistenciaDisponible
    FROM Variante v WHERE v.IDVariante = @IDVariante;
END
GO

CREATE OR ALTER PROCEDURE SP_Inventario_Kardex
    @IDVariante   INT,
    @Pagina       INT = 1,
    @TamanoPagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM Variante WHERE IDVariante = @IDVariante)
        THROW 51001, N'Variante no encontrada.', 1;

    WITH Kardex AS (
        SELECT m.IDMovimientoInventario, m.Fecha, m.Tipo, m.Cantidad, m.Motivo, m.IDUsuario, m.IDPedido,
               SUM(m.Cantidad) OVER (ORDER BY m.IDMovimientoInventario ROWS UNBOUNDED PRECEDING) AS Saldo
        FROM MovimientoInventario m
        WHERE m.IDVariante = @IDVariante)
    SELECT k.IDMovimientoInventario, k.Fecha, k.Tipo, k.Cantidad, k.Motivo, u.Correo AS Usuario, k.IDPedido, k.Saldo,
           COUNT(*) OVER () AS TotalRegistros
    FROM Kardex k
    LEFT JOIN Usuario u ON u.IDUsuario = k.IDUsuario
    ORDER BY k.IDMovimientoInventario DESC
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE SP_Inventario_Listar
    @Texto        NVARCHAR(100) = NULL,
    @Pagina       INT = 1,
    @TamanoPagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT v.IDVariante, v.SKU, p.Nombre AS Producto, v.Atributos,
           v.ExistenciaFisica, v.ExistenciaReservada, v.ExistenciaDisponible, v.Activo,
           COUNT(*) OVER () AS TotalRegistros
    FROM Variante v
    JOIN Producto p ON p.IDProducto = v.IDProducto
    WHERE @Texto IS NULL OR CHARINDEX(@Texto, p.Nombre) > 0 OR CHARINDEX(@Texto, v.SKU) > 0
    ORDER BY p.Nombre, v.SKU
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO
