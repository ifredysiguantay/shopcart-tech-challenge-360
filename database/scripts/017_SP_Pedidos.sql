CREATE OR ALTER PROCEDURE SP_Pedidos_Listar
    @IDUsuarioSolicitante INT,
    @EsStaff              BIT,
    @IDEstadoPedido       TINYINT = NULL,
    @IDCliente            INT = NULL,
    @Desde                DATE = NULL,
    @Hasta                DATE = NULL,
    @Orden                NVARCHAR(10) = N'fecha',
    @Direccion            NVARCHAR(4) = N'desc',
    @Pagina               INT = 1,
    @TamanoPagina         INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @EsStaff = 0 SET @IDCliente = @IDUsuarioSolicitante;

    SELECT p.IDPedido, p.IDUsuario AS IDCliente, u.Nombre AS Cliente, u.Correo AS CorreoCliente,
           e.Nombre AS Estado, p.Subtotal, p.Descuento, p.Total, p.MontoDevuelto, p.FechaCreacion,
           COUNT(*) OVER () AS TotalRegistros
    FROM Pedido p
    JOIN Usuario u ON u.IDUsuario = p.IDUsuario
    JOIN EstadoPedido e ON e.IDEstadoPedido = p.IDEstadoPedido
    WHERE (@IDEstadoPedido IS NULL OR p.IDEstadoPedido = @IDEstadoPedido)
      AND (@IDCliente IS NULL OR p.IDUsuario = @IDCliente)
      AND (@Desde IS NULL OR p.FechaCreacion >= @Desde)
      AND (@Hasta IS NULL OR p.FechaCreacion < DATEADD(DAY, 1, CAST(@Hasta AS DATETIME2(3))))
    ORDER BY
        CASE WHEN @Orden = N'total' AND @Direccion = N'asc'  THEN p.Total END ASC,
        CASE WHEN @Orden = N'total' AND @Direccion = N'desc' THEN p.Total END DESC,
        CASE WHEN @Orden = N'fecha' AND @Direccion = N'asc'  THEN p.FechaCreacion END ASC,
        CASE WHEN @Orden = N'fecha' AND @Direccion = N'desc' THEN p.FechaCreacion END DESC,
        p.IDPedido DESC
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE SP_Pedidos_Obtener
    @IDPedido             INT,
    @IDUsuarioSolicitante INT,
    @EsStaff              BIT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Propietario INT = (SELECT IDUsuario FROM Pedido WHERE IDPedido = @IDPedido);
    IF @Propietario IS NULL THROW 51001, N'Pedido no encontrado.', 1;
    IF @EsStaff = 0 AND @Propietario <> @IDUsuarioSolicitante THROW 51003, N'No tienes acceso a este pedido.', 1;

    SELECT p.IDPedido, p.IDUsuario AS IDCliente, u.Nombre AS Cliente, e.Nombre AS Estado, p.DireccionEntrega,
           p.CodigoCupon, p.Subtotal, p.Descuento, p.Total, p.MontoDevuelto, p.FechaCreacion
    FROM Pedido p
    JOIN Usuario u ON u.IDUsuario = p.IDUsuario
    JOIN EstadoPedido e ON e.IDEstadoPedido = p.IDEstadoPedido
    WHERE p.IDPedido = @IDPedido;

    SELECT d.IDPedidoDetalle, d.IDVariante, d.SKU, d.NombreProducto, d.PrecioUnitario, d.Cantidad,
           d.DescuentoLinea, d.TotalLinea, d.CantidadDevuelta, d.MontoDevuelto
    FROM PedidoDetalle d WHERE d.IDPedido = @IDPedido ORDER BY d.IDPedidoDetalle;

    SELECT h.EstadoAnterior, h.EstadoNuevo, h.Usuario, h.Fecha
    FROM VW_Pedidos_Historial h WHERE h.IDPedido = @IDPedido ORDER BY h.Fecha, h.EstadoNuevo;

    SELECT dv.IDDevolucion, dv.IDPedidoDetalle, dv.Cantidad, dv.Monto, dv.Motivo, dv.Fecha
    FROM Devolucion dv WHERE dv.IDPedido = @IDPedido ORDER BY dv.IDDevolucion;
END
GO

CREATE OR ALTER PROCEDURE SP_Pedidos_AvanzarEstado
    @IDPedido       INT,
    @IDEstadoNuevo  TINYINT,
    @IDUsuario      INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF @IDEstadoNuevo IN (5, 6)
        THROW 51004, N'Para cancelar o devolver usa las operaciones específicas.', 1;

    BEGIN TRAN;

    DECLARE @IDEstadoActual TINYINT = (SELECT IDEstadoPedido FROM Pedido WITH (UPDLOCK, ROWLOCK) WHERE IDPedido = @IDPedido);
    IF @IDEstadoActual IS NULL THROW 51001, N'Pedido no encontrado.', 1;

    IF NOT EXISTS (SELECT 1 FROM TransicionPedido WHERE IDEstadoOrigen = @IDEstadoActual AND IDEstadoDestino = @IDEstadoNuevo)
        THROW 51004, N'La transición de estado solicitada no está permitida.', 1;

    UPDATE Pedido SET IDEstadoPedido = @IDEstadoNuevo WHERE IDPedido = @IDPedido;

    INSERT HistorialEstadoPedido (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario)
    VALUES (@IDPedido, @IDEstadoActual, @IDEstadoNuevo, @IDUsuario);

    DECLARE @Anterior NVARCHAR(MAX) = (SELECT Nombre FROM EstadoPedido WHERE IDEstadoPedido = @IDEstadoActual);
    DECLARE @Nuevo NVARCHAR(MAX) = (SELECT Nombre FROM EstadoPedido WHERE IDEstadoPedido = @IDEstadoNuevo);
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Pedidos', N'Pedido', @IDPedido, N'CambiarEstado', @Anterior, @Nuevo;

    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE SP_Pedidos_Cancelar
    @IDPedido  INT,
    @IDUsuario INT,
    @EsStaff   BIT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    BEGIN TRAN;

    DECLARE @Propietario INT, @IDEstadoActual TINYINT;
    SELECT @Propietario = IDUsuario, @IDEstadoActual = IDEstadoPedido
    FROM Pedido WITH (UPDLOCK, ROWLOCK) WHERE IDPedido = @IDPedido;

    IF @Propietario IS NULL THROW 51001, N'Pedido no encontrado.', 1;
    IF @EsStaff = 0 AND @Propietario <> @IDUsuario THROW 51003, N'No tienes acceso a este pedido.', 1;
    IF NOT EXISTS (SELECT 1 FROM TransicionPedido WHERE IDEstadoOrigen = @IDEstadoActual AND IDEstadoDestino = 5)
        THROW 51004, N'El pedido ya no puede cancelarse.', 1;

    UPDATE Pedido SET IDEstadoPedido = 5 WHERE IDPedido = @IDPedido;

    DECLARE @IDVariante INT, @Cantidad INT, @Motivo NVARCHAR(250) = CONCAT(N'Cancelación - pedido #', @IDPedido);
    DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
        SELECT IDVariante, Cantidad FROM PedidoDetalle WHERE IDPedido = @IDPedido ORDER BY IDVariante;
    OPEN lineas;
    FETCH NEXT FROM lineas INTO @IDVariante, @Cantidad;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC SP_Inventario_AplicarMovimiento @IDVariante, N'Entrada', @Cantidad, @Motivo, @IDUsuario, @IDPedido;
        FETCH NEXT FROM lineas INTO @IDVariante, @Cantidad;
    END
    CLOSE lineas;
    DEALLOCATE lineas;

    UPDATE Pago SET Estado = N'Reembolsado' WHERE IDPedido = @IDPedido;

    IF EXISTS (SELECT 1 FROM CuponUso WHERE IDPedido = @IDPedido AND Anulado = 0)
    BEGIN
        UPDATE CuponUso SET Anulado = 1 WHERE IDPedido = @IDPedido;
        UPDATE Cupon SET UsosActuales = UsosActuales - 1 WHERE IDCupon = (SELECT IDCupon FROM Pedido WHERE IDPedido = @IDPedido);
    END

    INSERT HistorialEstadoPedido (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario)
    VALUES (@IDPedido, @IDEstadoActual, 5, @IDUsuario);

    DECLARE @Anterior NVARCHAR(MAX) = (SELECT Nombre FROM EstadoPedido WHERE IDEstadoPedido = @IDEstadoActual);
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Pedidos', N'Pedido', @IDPedido, N'Cancelar', @Anterior, N'Cancelado';

    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE SP_Pedidos_Devolver
    @IDPedido   INT,
    @IDUsuario  INT,
    @Motivo     NVARCHAR(250),
    @LineasJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF LEN(LTRIM(RTRIM(ISNULL(@Motivo, N'')))) = 0 THROW 51000, N'El motivo es obligatorio.', 1;
    IF ISJSON(@LineasJson) <> 1 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@LineasJson))
        THROW 51000, N'Debes indicar al menos una línea a devolver.', 1;

    DECLARE @Lineas TABLE (IDPedidoDetalle INT PRIMARY KEY, Cantidad INT NOT NULL, Monto DECIMAL(12,2) NULL);

    INSERT @Lineas (IDPedidoDetalle, Cantidad)
    SELECT IDPedidoDetalle, SUM(Cantidad)
    FROM OPENJSON(@LineasJson) WITH (IDPedidoDetalle INT '$.idPedidoDetalle', Cantidad INT '$.cantidad')
    GROUP BY IDPedidoDetalle;

    IF EXISTS (SELECT 1 FROM @Lineas WHERE Cantidad <= 0 OR IDPedidoDetalle IS NULL)
        THROW 51000, N'Las cantidades a devolver deben ser mayores a cero.', 1;

    BEGIN TRAN;

    DECLARE @IDEstadoActual TINYINT = (SELECT IDEstadoPedido FROM Pedido WITH (UPDLOCK, ROWLOCK) WHERE IDPedido = @IDPedido);
    IF @IDEstadoActual IS NULL THROW 51001, N'Pedido no encontrado.', 1;
    IF @IDEstadoActual <> 4 THROW 51004, N'Solo se pueden devolver pedidos entregados.', 1;

    IF EXISTS (SELECT 1 FROM @Lineas l WHERE NOT EXISTS (
            SELECT 1 FROM PedidoDetalle d WHERE d.IDPedidoDetalle = l.IDPedidoDetalle AND d.IDPedido = @IDPedido))
        THROW 51000, N'Alguna línea no pertenece al pedido.', 1;

    DECLARE @Excedidas NVARCHAR(MAX) = (
        SELECT STRING_AGG(d.SKU, N', ')
        FROM @Lineas l JOIN PedidoDetalle d ON d.IDPedidoDetalle = l.IDPedidoDetalle
        WHERE l.Cantidad > d.Cantidad - d.CantidadDevuelta);
    IF @Excedidas IS NOT NULL
    BEGIN
        DECLARE @Mensaje NVARCHAR(500) = CONCAT(N'No se puede devolver más de lo vendido en: ', @Excedidas, N'.');
        THROW 51004, @Mensaje, 1;
    END

    UPDATE l
    SET Monto = ROUND(d.TotalLinea * (d.CantidadDevuelta + l.Cantidad) / d.Cantidad, 2) - d.MontoDevuelto
    FROM @Lineas l JOIN PedidoDetalle d ON d.IDPedidoDetalle = l.IDPedidoDetalle;

    INSERT Devolucion (IDPedido, IDPedidoDetalle, Cantidad, Monto, Motivo, IDUsuario)
    SELECT @IDPedido, IDPedidoDetalle, Cantidad, Monto, @Motivo, @IDUsuario FROM @Lineas;

    UPDATE d
    SET CantidadDevuelta = d.CantidadDevuelta + l.Cantidad, MontoDevuelto = d.MontoDevuelto + l.Monto
    FROM PedidoDetalle d JOIN @Lineas l ON l.IDPedidoDetalle = d.IDPedidoDetalle;

    UPDATE Pedido SET MontoDevuelto = MontoDevuelto + (SELECT SUM(Monto) FROM @Lineas) WHERE IDPedido = @IDPedido;

    DECLARE @IDVariante INT, @Cantidad INT, @MotivoKardex NVARCHAR(250) = CONCAT(N'Devolución - pedido #', @IDPedido);
    DECLARE lineas CURSOR LOCAL FAST_FORWARD FOR
        SELECT d.IDVariante, l.Cantidad FROM @Lineas l JOIN PedidoDetalle d ON d.IDPedidoDetalle = l.IDPedidoDetalle ORDER BY d.IDVariante;
    OPEN lineas;
    FETCH NEXT FROM lineas INTO @IDVariante, @Cantidad;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC SP_Inventario_AplicarMovimiento @IDVariante, N'Devolucion', @Cantidad, @MotivoKardex, @IDUsuario, @IDPedido;
        FETCH NEXT FROM lineas INTO @IDVariante, @Cantidad;
    END
    CLOSE lineas;
    DEALLOCATE lineas;

    DECLARE @Total BIT = CASE WHEN NOT EXISTS (SELECT 1 FROM PedidoDetalle WHERE IDPedido = @IDPedido AND CantidadDevuelta < Cantidad) THEN 1 ELSE 0 END;
    IF @Total = 1
    BEGIN
        UPDATE Pedido SET IDEstadoPedido = 6 WHERE IDPedido = @IDPedido;
        INSERT HistorialEstadoPedido (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario) VALUES (@IDPedido, 4, 6, @IDUsuario);
    END

    DECLARE @Nuevo NVARCHAR(MAX) = (SELECT l.IDPedidoDetalle, l.Cantidad, l.Monto FROM @Lineas l FOR JSON PATH);
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Pedidos', N'Pedido', @IDPedido, N'Devolver', NULL, @Nuevo;

    COMMIT;

    SELECT @IDPedido AS IDPedido, SUM(Monto) AS MontoDevuelto, @Total AS DevolucionTotal FROM @Lineas;
END
GO
