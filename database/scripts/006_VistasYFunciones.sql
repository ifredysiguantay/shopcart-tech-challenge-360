CREATE OR ALTER VIEW VW_Pedidos_Completados
AS
SELECT p.IDPedido,
       p.IDUsuario,
       p.FechaCreacion,
       p.Total,
       p.MontoDevuelto,
       p.Total - p.MontoDevuelto AS TotalNeto
FROM Pedido p
JOIN EstadoPedido e ON e.IDEstadoPedido = p.IDEstadoPedido
WHERE e.Nombre = N'Entregado';
GO

CREATE OR ALTER VIEW VW_Dashboard_LineasVendidas
AS
SELECT d.IDPedidoDetalle,
       c.IDPedido,
       c.FechaCreacion,
       pr.IDProducto,
       pr.Nombre AS Producto,
       ca.IDCategoria,
       ca.Nombre AS Categoria,
       d.Cantidad - d.CantidadDevuelta AS UnidadesNetas,
       d.TotalLinea - d.MontoDevuelto AS VentaNeta
FROM VW_Pedidos_Completados c
JOIN PedidoDetalle d ON d.IDPedido = c.IDPedido
JOIN Variante v ON v.IDVariante = d.IDVariante
JOIN Producto pr ON pr.IDProducto = v.IDProducto
JOIN Categoria ca ON ca.IDCategoria = pr.IDCategoria;
GO

CREATE OR ALTER VIEW VW_Pedidos_Historial
AS
SELECT h.IDPedido,
       ea.Nombre AS EstadoAnterior,
       en.Nombre AS EstadoNuevo,
       h.IDUsuario,
       u.Nombre AS Usuario,
       h.Fecha
FROM HistorialEstadoPedido h
JOIN EstadoPedido en ON en.IDEstadoPedido = h.IDEstadoNuevo
LEFT JOIN EstadoPedido ea ON ea.IDEstadoPedido = h.IDEstadoAnterior
LEFT JOIN Usuario u ON u.IDUsuario = h.IDUsuario;
GO

CREATE OR ALTER VIEW VW_Inventario_Conciliacion
AS
SELECT v.IDVariante,
       v.SKU,
       v.ExistenciaFisica,
       ISNULL(SUM(m.Cantidad), 0) AS SumaKardex
FROM Variante v
LEFT JOIN MovimientoInventario m ON m.IDVariante = v.IDVariante
GROUP BY v.IDVariante, v.SKU, v.ExistenciaFisica
HAVING v.ExistenciaFisica <> ISNULL(SUM(m.Cantidad), 0);
GO

CREATE OR ALTER FUNCTION FU_Cupones_CalculoDescuento (@IDCarrito INT, @IDCupon INT)
RETURNS TABLE
AS
RETURN
WITH Lineas AS (
    SELECT ci.IDVariante,
           ci.Cantidad,
           v.Precio AS PrecioUnitario,
           CAST(ci.Cantidad * v.Precio AS DECIMAL(12,2)) AS Subtotal,
           c.Tipo,
           c.Valor,
           CASE WHEN c.IDCupon IS NOT NULL AND (c.IDCategoria IS NULL OR c.IDCategoria = p.IDCategoria) THEN 1 ELSE 0 END AS Elegible
    FROM CarritoItem ci
    JOIN Variante v ON v.IDVariante = ci.IDVariante
    JOIN Producto p ON p.IDProducto = v.IDProducto
    LEFT JOIN Cupon c ON c.IDCupon = @IDCupon
    WHERE ci.IDCarrito = @IDCarrito
),
ConBase AS (
    SELECT *, SUM(CASE WHEN Elegible = 1 THEN Subtotal ELSE 0 END) OVER () AS BaseElegible
    FROM Lineas
),
ConTotal AS (
    SELECT *,
           CAST(CASE
                WHEN Tipo IS NULL OR BaseElegible = 0 THEN 0
                WHEN Tipo = N'Porcentaje' THEN ROUND(BaseElegible * Valor / 100, 2)
                WHEN Valor > BaseElegible THEN BaseElegible
                ELSE Valor
           END AS DECIMAL(12,2)) AS DescuentoTotal
    FROM ConBase
),
Prorrateo AS (
    SELECT *,
           CAST(CASE WHEN Elegible = 1 THEN ROUND(DescuentoTotal * Subtotal / BaseElegible, 2) ELSE 0 END AS DECIMAL(12,2)) AS DescuentoBase,
           ROW_NUMBER() OVER (PARTITION BY Elegible ORDER BY Subtotal DESC, IDVariante) AS Orden
    FROM ConTotal
),
ConResto AS (
    SELECT *, SUM(DescuentoBase) OVER () AS DescuentoRepartido
    FROM Prorrateo
)
SELECT IDVariante,
       Cantidad,
       PrecioUnitario,
       Subtotal,
       CAST(DescuentoBase + CASE WHEN Elegible = 1 AND Orden = 1 THEN DescuentoTotal - DescuentoRepartido ELSE 0 END AS DECIMAL(12,2)) AS DescuentoLinea,
       CAST(Subtotal - DescuentoBase - CASE WHEN Elegible = 1 AND Orden = 1 THEN DescuentoTotal - DescuentoRepartido ELSE 0 END AS DECIMAL(12,2)) AS TotalLinea,
       CAST(Elegible AS BIT) AS Elegible
FROM ConResto;
GO
