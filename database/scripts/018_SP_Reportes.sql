CREATE OR ALTER PROCEDURE SP_Reportes_VentasPorPeriodo
    @Agrupacion NVARCHAR(10),
    @Desde      DATE,
    @Hasta      DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @Agrupacion NOT IN (N'dia', N'semana', N'mes')
        THROW 51000, N'La agrupación debe ser dia, semana o mes.', 1;

    SELECT k.Periodo, SUM(p.TotalNeto) AS Ventas, COUNT(*) AS Pedidos
    FROM VW_Pedidos_Completados p
    CROSS APPLY (
        SELECT CASE @Agrupacion
                   WHEN N'dia' THEN CAST(p.FechaCreacion AS DATE)
                   WHEN N'semana' THEN DATEADD(DAY, -(DATEDIFF(DAY, '19000101', CAST(p.FechaCreacion AS DATE)) % 7), CAST(p.FechaCreacion AS DATE))
                   ELSE DATEFROMPARTS(YEAR(p.FechaCreacion), MONTH(p.FechaCreacion), 1)
               END AS Periodo) k
    WHERE p.FechaCreacion >= @Desde AND p.FechaCreacion < DATEADD(DAY, 1, CAST(@Hasta AS DATETIME2(3)))
    GROUP BY k.Periodo
    ORDER BY k.Periodo;
END
GO

CREATE OR ALTER PROCEDURE SP_Reportes_VentasPorCategoria
    @Desde DATE,
    @Hasta DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.IDCategoria, l.Categoria, SUM(l.VentaNeta) AS Ventas, SUM(l.UnidadesNetas) AS Unidades
    FROM VW_Dashboard_LineasVendidas l
    WHERE l.FechaCreacion >= @Desde AND l.FechaCreacion < DATEADD(DAY, 1, CAST(@Hasta AS DATETIME2(3)))
    GROUP BY l.IDCategoria, l.Categoria
    ORDER BY Ventas DESC;
END
GO

CREATE OR ALTER PROCEDURE SP_Reportes_TopProductos
    @Desde DATE,
    @Hasta DATE,
    @Top   INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@Top) l.IDProducto, l.Producto, SUM(l.UnidadesNetas) AS Unidades, SUM(l.VentaNeta) AS Ventas
    FROM VW_Dashboard_LineasVendidas l
    WHERE l.FechaCreacion >= @Desde AND l.FechaCreacion < DATEADD(DAY, 1, CAST(@Hasta AS DATETIME2(3)))
    GROUP BY l.IDProducto, l.Producto
    HAVING SUM(l.UnidadesNetas) > 0
    ORDER BY Unidades DESC, Ventas DESC;
END
GO

CREATE OR ALTER PROCEDURE SP_Reportes_Resumen
    @Desde              DATE,
    @Hasta              DATE,
    @MinutosAbandono    INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ISNULL(SUM(p.TotalNeto), 0) AS Ventas,
           COUNT(*) AS Pedidos,
           ISNULL(SUM(p.TotalNeto) / NULLIF(COUNT(*), 0), 0) AS TicketPromedio
    FROM VW_Pedidos_Completados p
    WHERE p.FechaCreacion >= @Desde AND p.FechaCreacion < DATEADD(DAY, 1, CAST(@Hasta AS DATETIME2(3)));

    SELECT COUNT(*) AS CarritosAbandonados
    FROM Carrito c
    WHERE c.Estado = N'Activo'
      AND c.FechaActualizacion < DATEADD(MINUTE, -@MinutosAbandono, SYSUTCDATETIME())
      AND EXISTS (SELECT 1 FROM CarritoItem ci WHERE ci.IDCarrito = c.IDCarrito);
END
GO

CREATE OR ALTER PROCEDURE SP_Reportes_CarritosAbandonados
    @MinutosAbandono INT,
    @Pagina          INT = 1,
    @TamanoPagina    INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.IDCarrito, u.Correo AS Cliente, c.FechaActualizacion,
           (SELECT SUM(ci.Cantidad) FROM CarritoItem ci WHERE ci.IDCarrito = c.IDCarrito) AS Unidades,
           COUNT(*) OVER () AS TotalRegistros
    FROM Carrito c
    LEFT JOIN Usuario u ON u.IDUsuario = c.IDUsuario
    WHERE c.Estado = N'Activo'
      AND c.FechaActualizacion < DATEADD(MINUTE, -@MinutosAbandono, SYSUTCDATETIME())
      AND EXISTS (SELECT 1 FROM CarritoItem ci WHERE ci.IDCarrito = c.IDCarrito)
    ORDER BY c.FechaActualizacion
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO
