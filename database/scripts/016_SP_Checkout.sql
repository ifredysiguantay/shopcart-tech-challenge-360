CREATE OR ALTER PROCEDURE SP_Reservas_Liberar
    @IDCarrito INT = NULL,
    @Estado    NVARCHAR(12)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Liberados TABLE (IDCheckout INT PRIMARY KEY);

    BEGIN TRAN;

    UPDATE Checkout SET Estado = @Estado
    OUTPUT inserted.IDCheckout INTO @Liberados
    WHERE Estado = N'Activo'
      AND ((@IDCarrito IS NOT NULL AND IDCarrito = @IDCarrito)
        OR (@IDCarrito IS NULL AND FechaExpiracion <= SYSUTCDATETIME()));

    UPDATE v
    SET ExistenciaReservada = v.ExistenciaReservada - r.Cantidad
    FROM Variante v
    JOIN (
        SELECT re.IDVariante, SUM(re.Cantidad) AS Cantidad
        FROM ReservaExistencia re JOIN @Liberados l ON l.IDCheckout = re.IDCheckout
        GROUP BY re.IDVariante) r ON r.IDVariante = v.IDVariante;

    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE SP_Reservas_LiberarVencidas
AS
BEGIN
    SET NOCOUNT ON;
    EXEC SP_Reservas_Liberar @IDCarrito = NULL, @Estado = N'Expirado';
END
GO

CREATE OR ALTER PROCEDURE SP_Checkout_Iniciar
    @IDUsuario         INT,
    @IDDireccion       INT,
    @MinutosReserva    INT = 15
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    EXEC SP_Reservas_LiberarVencidas;

    DECLARE @IDCarrito INT, @IDCupon INT, @Codigo NVARCHAR(30);
    SELECT @IDCarrito = c.IDCarrito, @IDCupon = c.IDCupon, @Codigo = cu.Codigo
    FROM Carrito c LEFT JOIN Cupon cu ON cu.IDCupon = c.IDCupon
    WHERE c.IDUsuario = @IDUsuario AND c.Estado = N'Activo';

    IF @IDCarrito IS NULL OR NOT EXISTS (SELECT 1 FROM CarritoItem WHERE IDCarrito = @IDCarrito)
        THROW 51004, N'El carrito está vacío.', 1;

    DECLARE @Propietario INT, @DireccionActiva BIT;
    SELECT @Propietario = IDUsuario, @DireccionActiva = Activo FROM Direccion WHERE IDDireccion = @IDDireccion;
    IF @Propietario IS NULL THROW 51001, N'Dirección no encontrada.', 1;
    IF @Propietario <> @IDUsuario THROW 51003, N'No tienes acceso a esta dirección.', 1;
    IF @DireccionActiva = 0 THROW 51004, N'La dirección está desactivada.', 1;

    BEGIN TRAN;

    EXEC SP_Reservas_Liberar @IDCarrito = @IDCarrito, @Estado = N'Reemplazado';

    IF @IDCupon IS NOT NULL
        EXEC SP_Cupones_Validar @Codigo, @IDUsuario, @IDCarrito, @IDCupon OUTPUT;

    SELECT v.IDVariante INTO #Bloqueadas
    FROM Variante v WITH (UPDLOCK, ROWLOCK)
    JOIN CarritoItem ci ON ci.IDVariante = v.IDVariante
    WHERE ci.IDCarrito = @IDCarrito;

    DECLARE @SinExistencia NVARCHAR(MAX) = (
        SELECT STRING_AGG(v.SKU, N', ')
        FROM CarritoItem ci
        JOIN Variante v ON v.IDVariante = ci.IDVariante
        JOIN Producto p ON p.IDProducto = v.IDProducto
        WHERE ci.IDCarrito = @IDCarrito
          AND (v.Activo = 0 OR p.Activo = 0 OR v.ExistenciaDisponible < ci.Cantidad));

    IF @SinExistencia IS NOT NULL
    BEGIN
        DECLARE @Mensaje NVARCHAR(500) = CONCAT(N'No hay existencia suficiente para: ', @SinExistencia, N'. Ajusta tu carrito e inténtalo de nuevo.');
        THROW 51002, @Mensaje, 1;
    END

    UPDATE v SET ExistenciaReservada = v.ExistenciaReservada + ci.Cantidad
    FROM Variante v JOIN CarritoItem ci ON ci.IDVariante = v.IDVariante
    WHERE ci.IDCarrito = @IDCarrito;

    DECLARE @Subtotal DECIMAL(12,2), @Descuento DECIMAL(12,2);
    SELECT @Subtotal = SUM(Subtotal), @Descuento = SUM(DescuentoLinea)
    FROM FU_Cupones_CalculoDescuento(@IDCarrito, @IDCupon);

    INSERT Checkout (IDCarrito, IDUsuario, IDDireccion, IDCupon, Subtotal, Descuento, Total, FechaExpiracion)
    VALUES (@IDCarrito, @IDUsuario, @IDDireccion, @IDCupon, @Subtotal, @Descuento, @Subtotal - @Descuento,
            DATEADD(MINUTE, @MinutosReserva, SYSUTCDATETIME()));

    DECLARE @IDCheckout INT = SCOPE_IDENTITY();

    INSERT ReservaExistencia (IDCheckout, IDVariante, Cantidad, PrecioUnitario, DescuentoLinea)
    SELECT @IDCheckout, IDVariante, Cantidad, PrecioUnitario, DescuentoLinea
    FROM FU_Cupones_CalculoDescuento(@IDCarrito, @IDCupon);

    COMMIT;

    SELECT c.IDCheckout, c.FechaExpiracion, c.Subtotal, c.Descuento, c.Total
    FROM Checkout c WHERE c.IDCheckout = @IDCheckout;

    SELECT r.IDVariante, v.SKU, p.Nombre AS Producto, r.Cantidad, r.PrecioUnitario, r.DescuentoLinea
    FROM ReservaExistencia r
    JOIN Variante v ON v.IDVariante = r.IDVariante
    JOIN Producto p ON p.IDProducto = v.IDProducto
    WHERE r.IDCheckout = @IDCheckout
    ORDER BY r.IDVariante;
END
GO

CREATE OR ALTER PROCEDURE SP_Checkout_Pagar
    @IDCheckout        INT,
    @IDUsuario         INT,
    @ClaveIdempotencia NVARCHAR(100),
    @MetodoPago        NVARCHAR(30) = N'Tarjeta'
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF LEN(LTRIM(RTRIM(ISNULL(@ClaveIdempotencia, N'')))) = 0
        THROW 51000, N'La clave de idempotencia es obligatoria.', 1;

    DECLARE @Propietario INT, @Estado NVARCHAR(12), @Expira DATETIME2(3), @IDCarrito INT,
            @IDCupon INT, @IDPedido INT;

    BEGIN TRAN;

    SELECT @Propietario = IDUsuario, @Estado = Estado, @Expira = FechaExpiracion, @IDCarrito = IDCarrito, @IDCupon = IDCupon
    FROM Checkout WITH (UPDLOCK, ROWLOCK) WHERE IDCheckout = @IDCheckout;

    IF @Propietario IS NULL THROW 51001, N'Checkout no encontrado.', 1;
    IF @Propietario <> @IDUsuario THROW 51003, N'No tienes acceso a este checkout.', 1;

    SELECT @IDPedido = IDPedido FROM Pedido WHERE IDCheckout = @IDCheckout;
    IF @IDPedido IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM Pedido WHERE IDPedido = @IDPedido AND ClaveIdempotencia = @ClaveIdempotencia)
            THROW 51002, N'Este checkout ya fue pagado con otra clave de idempotencia.', 1;
        COMMIT;
        SELECT @IDPedido AS IDPedido, CAST(1 AS BIT) AS Repetido;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM Pedido WHERE IDUsuario = @IDUsuario AND ClaveIdempotencia = @ClaveIdempotencia)
        THROW 51002, N'La clave de idempotencia ya fue usada en otra operación.', 1;

    IF @Estado <> N'Activo'
        THROW 51004, N'El checkout ya no está activo; inicia el pago nuevamente.', 1;

    IF @Expira <= SYSUTCDATETIME()
    BEGIN
        EXEC SP_Reservas_LiberarVencidas;
        COMMIT;
        THROW 51002, N'La reserva de existencia venció; inicia el pago nuevamente.', 1;
    END

    IF @IDCupon IS NOT NULL
    BEGIN
        UPDATE Cupon SET UsosActuales = UsosActuales + 1
        WHERE IDCupon = @IDCupon AND Activo = 1 AND UsosActuales < LimiteUsosTotal
          AND SYSUTCDATETIME() BETWEEN FechaInicio AND FechaFin;
        IF @@ROWCOUNT = 0
            THROW 51004, N'El cupón ya no está disponible (vencido, agotado o inactivo).', 1;

        IF (SELECT COUNT(*) FROM CuponUso WHERE IDCupon = @IDCupon AND IDUsuario = @IDUsuario AND Anulado = 0)
           >= (SELECT LimiteUsosPorCliente FROM Cupon WHERE IDCupon = @IDCupon)
            THROW 51004, N'Ya alcanzaste el límite de usos de este cupón.', 1;
    END

    INSERT Pedido (IDUsuario, IDEstadoPedido, IDCheckout, IDCupon, CodigoCupon, DireccionEntrega,
                   Subtotal, Descuento, Total, ClaveIdempotencia)
    SELECT c.IDUsuario, 1, c.IDCheckout, c.IDCupon, cu.Codigo,
           CONCAT(d.Direccion, N', ', d.Ciudad, N', ', d.Departamento, N' - Tel. ', d.Telefono),
           c.Subtotal, c.Descuento, c.Total, @ClaveIdempotencia
    FROM Checkout c
    JOIN Direccion d ON d.IDDireccion = c.IDDireccion
    LEFT JOIN Cupon cu ON cu.IDCupon = c.IDCupon
    WHERE c.IDCheckout = @IDCheckout;

    SET @IDPedido = SCOPE_IDENTITY();

    INSERT PedidoDetalle (IDPedido, IDVariante, SKU, NombreProducto, PrecioUnitario, Cantidad, DescuentoLinea, TotalLinea)
    SELECT @IDPedido, r.IDVariante, v.SKU, p.Nombre, r.PrecioUnitario, r.Cantidad, r.DescuentoLinea,
           r.Cantidad * r.PrecioUnitario - r.DescuentoLinea
    FROM ReservaExistencia r
    JOIN Variante v ON v.IDVariante = r.IDVariante
    JOIN Producto p ON p.IDProducto = v.IDProducto
    WHERE r.IDCheckout = @IDCheckout;

    DECLARE @IDVariante INT, @Cantidad INT, @Motivo NVARCHAR(250) = CONCAT(N'Venta - pedido #', @IDPedido);
    DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
        SELECT IDVariante, Cantidad FROM ReservaExistencia WHERE IDCheckout = @IDCheckout ORDER BY IDVariante;
    OPEN lineas;
    FETCH NEXT FROM lineas INTO @IDVariante, @Cantidad;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @Salida INT = -@Cantidad;
        EXEC SP_Inventario_AplicarMovimiento @IDVariante, N'Salida', @Salida, @Motivo, @IDUsuario, @IDPedido, @Cantidad;
        FETCH NEXT FROM lineas INTO @IDVariante, @Cantidad;
    END
    CLOSE lineas;
    DEALLOCATE lineas;

    INSERT Pago (IDPedido, Monto, Metodo, Referencia, ClaveIdempotencia)
    SELECT @IDPedido, Total, @MetodoPago, CONVERT(NVARCHAR(36), NEWID()), @ClaveIdempotencia FROM Pedido WHERE IDPedido = @IDPedido;

    IF @IDCupon IS NOT NULL
        INSERT CuponUso (IDCupon, IDUsuario, IDPedido) VALUES (@IDCupon, @IDUsuario, @IDPedido);

    INSERT HistorialEstadoPedido (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario)
    VALUES (@IDPedido, NULL, 1, @IDUsuario);

    UPDATE Checkout SET Estado = N'Pagado' WHERE IDCheckout = @IDCheckout;
    UPDATE Carrito SET Estado = N'Convertido' WHERE IDCarrito = @IDCarrito;

    DECLARE @Nuevo NVARCHAR(MAX) = (
        SELECT p.IDPedido, p.Subtotal, p.Descuento, p.Total, p.CodigoCupon
        FROM Pedido p WHERE p.IDPedido = @IDPedido FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Pedidos', N'Pedido', @IDPedido, N'Crear', NULL, @Nuevo;

    COMMIT;

    SELECT @IDPedido AS IDPedido, CAST(0 AS BIT) AS Repetido;
END
GO
