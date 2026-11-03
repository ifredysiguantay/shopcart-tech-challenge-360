INSERT Rol (IDRol, Nombre) VALUES (1, N'Cliente'), (2, N'Operador'), (3, N'Administrador');

INSERT EstadoPedido (IDEstadoPedido, Nombre)
VALUES (1, N'Pagado'), (2, N'EnPreparacion'), (3, N'Despachado'), (4, N'Entregado'), (5, N'Cancelado'), (6, N'Devuelto');

INSERT TransicionPedido (IDEstadoOrigen, IDEstadoDestino)
VALUES (1, 2), (1, 5), (2, 3), (2, 5), (3, 4), (4, 6);

-- Contraseñas de prueba: Admin#2026, Operador#2026 y Cliente#2026 (documentadas en el README).
INSERT Usuario (Correo, PasswordHash, Nombre, IDRol)
VALUES
 (N'admin@shopcart.test',    N'scrypt:e37adb00f2376446a827661af0cb74d8:4b610324c814499b031bcc43bbf4e2c7c424de204e4c2487a9fb93f73a843435781e91d82d083ac85c1e7e018dec23b3a9fbcb264b9ca4c7645c9d2cb797ba53', N'Administrador Demo', 3),
 (N'operador@shopcart.test', N'scrypt:9856102f1c06492cb74d25dcfc799e34:465699717c695d85370a7d87408a6fea006830fbc8be8c5f60ce73d88592b621ba8456490c8dc0ce937d3d4596613fa0407f764ca767d4153716eb43e6cba311', N'Operador Demo', 2),
 (N'cliente@shopcart.test',  N'scrypt:5fc6ed40e6e8b7b856a4474968413a11:d89fe72a1e122f573da46709b958096468a6eb1e7995f64d1f81cc14af453e74ca6b9a1faf399d8c3b4c15687e1296db5036c2d724b18a6fffa671845428d991', N'Cliente Demo', 1),
 (N'cliente2@shopcart.test', N'scrypt:5fc6ed40e6e8b7b856a4474968413a11:d89fe72a1e122f573da46709b958096468a6eb1e7995f64d1f81cc14af453e74ca6b9a1faf399d8c3b4c15687e1296db5036c2d724b18a6fffa671845428d991', N'Cliente Dos', 1),
 (N'cliente3@shopcart.test', N'scrypt:5fc6ed40e6e8b7b856a4474968413a11:d89fe72a1e122f573da46709b958096468a6eb1e7995f64d1f81cc14af453e74ca6b9a1faf399d8c3b4c15687e1296db5036c2d724b18a6fffa671845428d991', N'Cliente Tres', 1);

INSERT Direccion (IDUsuario, Alias, Direccion, Ciudad, Departamento, Telefono)
SELECT IDUsuario, N'Casa', N'6a Avenida 12-34 zona 1', N'Guatemala', N'Guatemala', N'55501234'
FROM Usuario WHERE IDRol = 1;

INSERT Categoria (Nombre, Descripcion)
VALUES (N'Ropa', N'Prendas de vestir'), (N'Calzado', N'Zapatos y sandalias'), (N'Hogar', N'Artículos para el hogar'),
       (N'Electrónica', N'Dispositivos y accesorios'), (N'Deportes', N'Equipo deportivo'), (N'Juguetes', N'Juegos y juguetes');

DECLARE @Productos TABLE (Categoria NVARCHAR(100), Nombre NVARCHAR(150), PrecioBase DECIMAL(12,2));
INSERT @Productos VALUES
 (N'Ropa', N'Camiseta básica', 89.00), (N'Ropa', N'Pantalón de mezclilla', 249.00), (N'Ropa', N'Sudadera con capucha', 299.00),
 (N'Ropa', N'Chumpa impermeable', 399.00), (N'Ropa', N'Camisa casual', 179.00),
 (N'Calzado', N'Tenis urbanos', 449.00), (N'Calzado', N'Botas de cuero', 649.00), (N'Calzado', N'Sandalias', 129.00),
 (N'Calzado', N'Zapatos formales', 549.00), (N'Calzado', N'Zapatillas running', 599.00),
 (N'Hogar', N'Juego de sábanas', 289.00), (N'Hogar', N'Lámpara de mesa', 159.00), (N'Hogar', N'Set de toallas', 199.00),
 (N'Hogar', N'Organizador modular', 119.00), (N'Hogar', N'Cobija térmica', 249.00),
 (N'Electrónica', N'Audífonos inalámbricos', 349.00), (N'Electrónica', N'Cargador rápido', 99.00), (N'Electrónica', N'Parlante portátil', 279.00),
 (N'Electrónica', N'Teclado compacto', 229.00), (N'Electrónica', N'Mouse ergonómico', 149.00),
 (N'Deportes', N'Balón de fútbol', 139.00), (N'Deportes', N'Mochila deportiva', 189.00), (N'Deportes', N'Pesas ajustables', 329.00),
 (N'Deportes', N'Colchoneta de yoga', 119.00), (N'Deportes', N'Botella térmica', 79.00),
 (N'Juguetes', N'Bloques de construcción', 169.00), (N'Juguetes', N'Muñeca articulada', 129.00), (N'Juguetes', N'Carro a control remoto', 219.00),
 (N'Juguetes', N'Rompecabezas 1000 piezas', 99.00), (N'Juguetes', N'Juego de mesa familiar', 189.00);

INSERT Producto (IDCategoria, Nombre, Descripcion)
SELECT c.IDCategoria, p.Nombre, CONCAT(N'Producto de la categoría ', p.Categoria, N': ', p.Nombre, N'.')
FROM @Productos p JOIN Categoria c ON c.Nombre = p.Categoria;

INSERT ImagenProducto (IDProducto, Url, Orden)
SELECT IDProducto, CONCAT(N'https://picsum.photos/seed/shopcart-', IDProducto, N'/600/600'), 0 FROM Producto;

DECLARE @Variantes TABLE (Talla NVARCHAR(10), Color NVARCHAR(20), Incremento DECIMAL(12,2));
INSERT @Variantes VALUES (N'S', N'Negro', 0), (N'M', N'Azul', 10), (N'L', N'Rojo', 20);

INSERT Variante (IDProducto, SKU, Atributos, Precio, ExistenciaFisica)
SELECT p.IDProducto,
       CONCAT(N'SKU-', RIGHT(CONCAT(N'000', p.IDProducto), 3), N'-', v.Talla, LEFT(v.Color, 1)),
       CONCAT(N'{"talla":"', v.Talla, N'","color":"', v.Color, N'"}'),
       pb.PrecioBase + v.Incremento,
       1000
FROM Producto p
JOIN @Productos pb ON pb.Nombre = p.Nombre
CROSS JOIN @Variantes v;

INSERT MovimientoInventario (IDVariante, Tipo, Cantidad, Motivo, IDUsuario, Fecha)
SELECT IDVariante, N'Entrada', ExistenciaFisica, N'Existencia inicial', 1, DATEADD(DAY, -100, SYSUTCDATETIME()) FROM Variante;

-- Variante con una sola unidad para probar la compra concurrente de la última existencia.
DECLARE @IDProductoUltima INT = (SELECT TOP 1 IDProducto FROM Producto ORDER BY IDProducto);
INSERT Variante (IDProducto, SKU, Atributos, Precio, ExistenciaFisica)
VALUES (@IDProductoUltima, N'SKU-ULTIMA-UNIDAD', N'{"talla":"XL","color":"Edición limitada"}', 99.00, 1);
INSERT MovimientoInventario (IDVariante, Tipo, Cantidad, Motivo, IDUsuario)
VALUES (SCOPE_IDENTITY(), N'Entrada', 1, N'Existencia inicial', 1);

INSERT Cupon (Codigo, Tipo, Valor, FechaInicio, FechaFin, MontoMinimo, LimiteUsosTotal, LimiteUsosPorCliente, IDCategoria)
SELECT N'BIENVENIDA10', N'Porcentaje', 10, DATEADD(DAY, -30, SYSUTCDATETIME()), DATEADD(YEAR, 1, SYSUTCDATETIME()), 100, 1000, 1, NULL
UNION ALL
SELECT N'Q50FIJO', N'MontoFijo', 50, DATEADD(DAY, -30, SYSUTCDATETIME()), DATEADD(YEAR, 1, SYSUTCDATETIME()), 300, 500, 3, NULL
UNION ALL
SELECT N'ROPA20', N'Porcentaje', 20, DATEADD(DAY, -30, SYSUTCDATETIME()), DATEADD(YEAR, 1, SYSUTCDATETIME()), 0, 200, 2, (SELECT IDCategoria FROM Categoria WHERE Nombre = N'Ropa')
UNION ALL
SELECT N'UNSOLOUSO', N'MontoFijo', 25, DATEADD(DAY, -30, SYSUTCDATETIME()), DATEADD(YEAR, 1, SYSUTCDATETIME()), 0, 1, 1, NULL
UNION ALL
SELECT N'VENCIDO', N'Porcentaje', 15, DATEADD(DAY, -60, SYSUTCDATETIME()), DATEADD(DAY, -1, SYSUTCDATETIME()), 0, 100, 1, NULL;
GO
