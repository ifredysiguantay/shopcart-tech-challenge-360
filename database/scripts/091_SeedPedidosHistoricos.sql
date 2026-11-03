-- 250 pedidos históricos (últimos 90 días) para que dashboard y reportes tengan datos.
-- Los cancelados no mueven existencia; los demás quedan entregados con su salida en el kardex.
DECLARE @Variantes TABLE (Posicion INT PRIMARY KEY, IDVariante INT, Precio DECIMAL(12,2), SKU NVARCHAR(50), Nombre NVARCHAR(150));
INSERT @Variantes
SELECT ROW_NUMBER() OVER (ORDER BY v.IDVariante), v.IDVariante, v.Precio, v.SKU, p.Nombre
FROM Variante v JOIN Producto p ON p.IDProducto = v.IDProducto
WHERE v.SKU <> N'SKU-ULTIMA-UNIDAD';

DECLARE @Total INT = (SELECT COUNT(*) FROM @Variantes);
DECLARE @Clientes TABLE (Posicion INT PRIMARY KEY, IDUsuario INT);
INSERT @Clientes SELECT ROW_NUMBER() OVER (ORDER BY IDUsuario), IDUsuario FROM Usuario WHERE IDRol = 1;
DECLARE @NumClientes INT = (SELECT COUNT(*) FROM @Clientes);

DECLARE @Lineas TABLE (NumeroPedido INT, IDVariante INT, SKU NVARCHAR(50), Nombre NVARCHAR(150), Precio DECIMAL(12,2), Cantidad INT);
WITH Numeros AS (
    SELECT TOP (250) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b),
Posiciones AS (SELECT 1 AS l UNION ALL SELECT 2 UNION ALL SELECT 3)
INSERT @Lineas
SELECT n.n, v.IDVariante, v.SKU, v.Nombre, v.Precio, (n.n + p.l) % 3 + 1
FROM Numeros n
JOIN Posiciones p ON p.l <= 1 + n.n % 3
JOIN @Variantes v ON v.Posicion = ((n.n * 7 + p.l * 13) % @Total) + 1;

INSERT Pedido (IDUsuario, IDEstadoPedido, DireccionEntrega, Subtotal, Descuento, Total, ClaveIdempotencia, FechaCreacion)
SELECT c.IDUsuario,
       CASE WHEN l.NumeroPedido % 20 = 0 THEN 5 ELSE 4 END,
       N'6a Avenida 12-34 zona 1, Guatemala, Guatemala - Tel. 55501234',
       SUM(l.Cantidad * l.Precio), 0, SUM(l.Cantidad * l.Precio),
       CONCAT(N'seed-', l.NumeroPedido),
       DATEADD(MINUTE, -((l.NumeroPedido * 517) % 129600), SYSUTCDATETIME())
FROM @Lineas l
JOIN @Clientes c ON c.Posicion = (l.NumeroPedido % @NumClientes) + 1
GROUP BY l.NumeroPedido, c.IDUsuario;

INSERT PedidoDetalle (IDPedido, IDVariante, SKU, NombreProducto, PrecioUnitario, Cantidad, DescuentoLinea, TotalLinea)
SELECT p.IDPedido, l.IDVariante, l.SKU, l.Nombre, l.Precio, l.Cantidad, 0, l.Cantidad * l.Precio
FROM @Lineas l JOIN Pedido p ON p.ClaveIdempotencia = CONCAT(N'seed-', l.NumeroPedido);

INSERT Pago (IDPedido, Monto, Metodo, Estado, Referencia, ClaveIdempotencia, Fecha)
SELECT p.IDPedido, p.Total, N'Tarjeta', CASE WHEN p.IDEstadoPedido = 5 THEN N'Reembolsado' ELSE N'Aprobado' END,
       CONVERT(NVARCHAR(36), NEWID()), p.ClaveIdempotencia, p.FechaCreacion
FROM Pedido p WHERE p.ClaveIdempotencia LIKE N'seed-%';

INSERT HistorialEstadoPedido (IDPedido, IDEstadoAnterior, IDEstadoNuevo, IDUsuario, Fecha)
SELECT p.IDPedido, NULL, 1, p.IDUsuario, p.FechaCreacion FROM Pedido p WHERE p.ClaveIdempotencia LIKE N'seed-%'
UNION ALL
SELECT p.IDPedido, 1, 5, 2, DATEADD(HOUR, 2, p.FechaCreacion) FROM Pedido p WHERE p.ClaveIdempotencia LIKE N'seed-%' AND p.IDEstadoPedido = 5
UNION ALL
SELECT p.IDPedido, 1, 2, 2, DATEADD(HOUR, 2, p.FechaCreacion) FROM Pedido p WHERE p.ClaveIdempotencia LIKE N'seed-%' AND p.IDEstadoPedido = 4
UNION ALL
SELECT p.IDPedido, 2, 3, 2, DATEADD(DAY, 1, p.FechaCreacion) FROM Pedido p WHERE p.ClaveIdempotencia LIKE N'seed-%' AND p.IDEstadoPedido = 4
UNION ALL
SELECT p.IDPedido, 3, 4, 2, DATEADD(DAY, 3, p.FechaCreacion) FROM Pedido p WHERE p.ClaveIdempotencia LIKE N'seed-%' AND p.IDEstadoPedido = 4;

INSERT MovimientoInventario (IDVariante, Tipo, Cantidad, Motivo, IDUsuario, IDPedido, Fecha)
SELECT d.IDVariante, N'Salida', -d.Cantidad, CONCAT(N'Venta - pedido #', p.IDPedido), p.IDUsuario, p.IDPedido, p.FechaCreacion
FROM Pedido p JOIN PedidoDetalle d ON d.IDPedido = p.IDPedido
WHERE p.ClaveIdempotencia LIKE N'seed-%' AND p.IDEstadoPedido = 4;

UPDATE v SET ExistenciaFisica = k.Saldo
FROM Variante v
JOIN (SELECT IDVariante, SUM(Cantidad) AS Saldo FROM MovimientoInventario GROUP BY IDVariante) k ON k.IDVariante = v.IDVariante;
GO
