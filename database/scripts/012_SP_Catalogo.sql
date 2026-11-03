CREATE OR ALTER PROCEDURE SP_Categorias_Crear
    @Nombre      NVARCHAR(100),
    @Descripcion NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT Categoria (Nombre, Descripcion) VALUES (@Nombre, @Descripcion);
    SELECT c.IDCategoria, c.Nombre, c.Descripcion, c.Activo FROM Categoria c WHERE c.IDCategoria = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE SP_Categorias_Actualizar
    @IDCategoria INT,
    @Nombre      NVARCHAR(100),
    @Descripcion NVARCHAR(500) = NULL,
    @Activo      BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Categoria SET Nombre = @Nombre, Descripcion = @Descripcion, Activo = @Activo WHERE IDCategoria = @IDCategoria;
    IF @@ROWCOUNT = 0 THROW 51001, N'Categoría no encontrada.', 1;
    SELECT c.IDCategoria, c.Nombre, c.Descripcion, c.Activo FROM Categoria c WHERE c.IDCategoria = @IDCategoria;
END
GO

CREATE OR ALTER PROCEDURE SP_Categorias_Listar
    @IncluirInactivas BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.IDCategoria, c.Nombre, c.Descripcion, c.Activo
    FROM Categoria c
    WHERE @IncluirInactivas = 1 OR c.Activo = 1
    ORDER BY c.Nombre;
END
GO

CREATE OR ALTER PROCEDURE SP_Categorias_Eliminar
    @IDCategoria INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM Categoria WHERE IDCategoria = @IDCategoria)
        THROW 51001, N'Categoría no encontrada.', 1;
    IF EXISTS (SELECT 1 FROM Producto WHERE IDCategoria = @IDCategoria)
        THROW 51002, N'La categoría tiene productos asociados; desactívala en su lugar.', 1;
    IF EXISTS (SELECT 1 FROM Cupon WHERE IDCategoria = @IDCategoria)
        THROW 51002, N'La categoría tiene cupones asociados; desactívala en su lugar.', 1;
    DELETE FROM Categoria WHERE IDCategoria = @IDCategoria;
END
GO

CREATE OR ALTER PROCEDURE SP_Productos_Crear
    @IDCategoria   INT,
    @Nombre        NVARCHAR(150),
    @Descripcion   NVARCHAR(2000),
    @VariantesJson NVARCHAR(MAX),
    @ImagenesJson  NVARCHAR(MAX) = NULL,
    @IDUsuario     INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF ISJSON(@VariantesJson) <> 1 OR NOT EXISTS (SELECT 1 FROM OPENJSON(@VariantesJson))
        THROW 51000, N'El producto debe tener al menos una variante.', 1;
    IF NOT EXISTS (SELECT 1 FROM Categoria WHERE IDCategoria = @IDCategoria AND Activo = 1)
        THROW 51001, N'La categoría no existe o está inactiva.', 1;

    DECLARE @IDProducto INT;
    DECLARE @Nuevas TABLE (IDVariante INT, Existencia INT);

    BEGIN TRAN;

    INSERT Producto (IDCategoria, Nombre, Descripcion) VALUES (@IDCategoria, @Nombre, @Descripcion);
    SET @IDProducto = SCOPE_IDENTITY();

    INSERT Variante (IDProducto, SKU, Atributos, Precio, ExistenciaFisica)
    OUTPUT inserted.IDVariante, inserted.ExistenciaFisica INTO @Nuevas
    SELECT @IDProducto, v.SKU, ISNULL(v.Atributos, N'{}'), v.Precio, ISNULL(v.Existencia, 0)
    FROM OPENJSON(@VariantesJson) WITH (
        SKU        NVARCHAR(50)  '$.sku',
        Atributos  NVARCHAR(MAX) '$.atributos' AS JSON,
        Precio     DECIMAL(12,2) '$.precio',
        Existencia INT           '$.existenciaInicial') v;

    INSERT MovimientoInventario (IDVariante, Tipo, Cantidad, Motivo, IDUsuario)
    SELECT IDVariante, N'Entrada', Existencia, N'Existencia inicial', @IDUsuario FROM @Nuevas WHERE Existencia > 0;

    IF @ImagenesJson IS NOT NULL
        INSERT ImagenProducto (IDProducto, Url, Orden)
        SELECT @IDProducto, [value], [key] FROM OPENJSON(@ImagenesJson);

    DECLARE @Nuevo NVARCHAR(MAX) = (
        SELECT p.IDProducto, p.IDCategoria, p.Nombre, p.Descripcion, p.Activo,
               Variantes = (SELECT v.SKU, v.Precio, v.ExistenciaFisica FROM Variante v WHERE v.IDProducto = p.IDProducto FOR JSON PATH)
        FROM Producto p WHERE p.IDProducto = @IDProducto FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    EXEC SP_Bitacora_Registrar @IDUsuario, N'Productos', N'Producto', @IDProducto, N'Crear', NULL, @Nuevo;

    COMMIT;

    SELECT @IDProducto AS IDProducto;
END
GO

CREATE OR ALTER PROCEDURE SP_Productos_Actualizar
    @IDProducto   INT,
    @IDCategoria  INT,
    @Nombre       NVARCHAR(150),
    @Descripcion  NVARCHAR(2000),
    @Activo       BIT,
    @ImagenesJson NVARCHAR(MAX) = NULL,
    @IDUsuario    INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Anterior NVARCHAR(MAX) = (
        SELECT p.IDCategoria, p.Nombre, p.Descripcion, p.Activo
        FROM Producto p WHERE p.IDProducto = @IDProducto FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    IF @Anterior IS NULL THROW 51001, N'Producto no encontrado.', 1;
    IF NOT EXISTS (SELECT 1 FROM Categoria WHERE IDCategoria = @IDCategoria)
        THROW 51001, N'La categoría no existe.', 1;

    BEGIN TRAN;

    UPDATE Producto
    SET IDCategoria = @IDCategoria, Nombre = @Nombre, Descripcion = @Descripcion, Activo = @Activo
    WHERE IDProducto = @IDProducto;

    IF @ImagenesJson IS NOT NULL
    BEGIN
        DELETE FROM ImagenProducto WHERE IDProducto = @IDProducto;
        INSERT ImagenProducto (IDProducto, Url, Orden)
        SELECT @IDProducto, [value], [key] FROM OPENJSON(@ImagenesJson);
    END

    DECLARE @Nuevo NVARCHAR(MAX) = (
        SELECT p.IDCategoria, p.Nombre, p.Descripcion, p.Activo
        FROM Producto p WHERE p.IDProducto = @IDProducto FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    DECLARE @Accion NVARCHAR(20) = CASE WHEN @Activo = 0 THEN N'Desactivar' ELSE N'Actualizar' END;
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Productos', N'Producto', @IDProducto, @Accion, @Anterior, @Nuevo;

    COMMIT;
END
GO

CREATE OR ALTER PROCEDURE SP_Productos_Eliminar
    @IDProducto INT,
    @IDUsuario  INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Producto WHERE IDProducto = @IDProducto)
        THROW 51001, N'Producto no encontrado.', 1;

    DECLARE @TieneHistorial BIT = CASE WHEN EXISTS (
        SELECT 1 FROM Variante v
        WHERE v.IDProducto = @IDProducto
          AND (EXISTS (SELECT 1 FROM PedidoDetalle d WHERE d.IDVariante = v.IDVariante)
            OR EXISTS (SELECT 1 FROM MovimientoInventario m WHERE m.IDVariante = v.IDVariante)
            OR EXISTS (SELECT 1 FROM ReservaExistencia r WHERE r.IDVariante = v.IDVariante)))
        THEN 1 ELSE 0 END;

    BEGIN TRAN;

    IF @TieneHistorial = 1
    BEGIN
        UPDATE Producto SET Activo = 0 WHERE IDProducto = @IDProducto;
        EXEC SP_Bitacora_Registrar @IDUsuario, N'Productos', N'Producto', @IDProducto, N'Desactivar', N'{"Activo":true}', N'{"Activo":false}';
        COMMIT;
        SELECT N'Desactivado' AS Resultado;
        RETURN;
    END

    DELETE ci FROM CarritoItem ci JOIN Variante v ON v.IDVariante = ci.IDVariante WHERE v.IDProducto = @IDProducto;
    DELETE FROM Variante WHERE IDProducto = @IDProducto;
    DELETE FROM Producto WHERE IDProducto = @IDProducto;
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Productos', N'Producto', @IDProducto, N'Eliminar', NULL, NULL;

    COMMIT;
    SELECT N'Eliminado' AS Resultado;
END
GO

CREATE OR ALTER PROCEDURE SP_Productos_Obtener
    @IDProducto        INT,
    @IncluirInactivos  BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM Producto p JOIN Categoria c ON c.IDCategoria = p.IDCategoria
        WHERE p.IDProducto = @IDProducto AND (@IncluirInactivos = 1 OR (p.Activo = 1 AND c.Activo = 1)))
        THROW 51001, N'Producto no encontrado.', 1;

    SELECT p.IDProducto, p.Nombre, p.Descripcion, p.IDCategoria, c.Nombre AS Categoria, p.Activo
    FROM Producto p JOIN Categoria c ON c.IDCategoria = p.IDCategoria
    WHERE p.IDProducto = @IDProducto;

    SELECT v.IDVariante, v.SKU, v.Atributos, v.Precio, v.ExistenciaFisica, v.ExistenciaReservada, v.ExistenciaDisponible, v.Activo
    FROM Variante v
    WHERE v.IDProducto = @IDProducto AND (@IncluirInactivos = 1 OR v.Activo = 1)
    ORDER BY v.IDVariante;

    SELECT i.Url, i.Orden FROM ImagenProducto i WHERE i.IDProducto = @IDProducto ORDER BY i.Orden;
END
GO

CREATE OR ALTER PROCEDURE SP_Productos_Buscar
    @Texto             NVARCHAR(100) = NULL,
    @IDCategoria       INT = NULL,
    @PrecioMinimo      DECIMAL(12,2) = NULL,
    @PrecioMaximo      DECIMAL(12,2) = NULL,
    @SoloDisponibles   BIT = 0,
    @IncluirInactivos  BIT = 0,
    @Orden             NVARCHAR(10) = N'nombre',
    @Direccion         NVARCHAR(4) = N'asc',
    @Pagina            INT = 1,
    @TamanoPagina      INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.IDProducto, p.Nombre, p.Descripcion, p.IDCategoria, c.Nombre AS Categoria, p.Activo,
           agg.PrecioMinimo, agg.PrecioMaximo, agg.ExistenciaDisponible, img.Url AS ImagenPrincipal,
           COUNT(*) OVER () AS TotalRegistros
    FROM Producto p
    JOIN Categoria c ON c.IDCategoria = p.IDCategoria
    CROSS APPLY (
        SELECT MIN(v.Precio) AS PrecioMinimo, MAX(v.Precio) AS PrecioMaximo, SUM(v.ExistenciaDisponible) AS ExistenciaDisponible
        FROM Variante v
        WHERE v.IDProducto = p.IDProducto AND (@IncluirInactivos = 1 OR v.Activo = 1)) agg
    OUTER APPLY (SELECT TOP 1 i.Url FROM ImagenProducto i WHERE i.IDProducto = p.IDProducto ORDER BY i.Orden) img
    WHERE (@IncluirInactivos = 1 OR (p.Activo = 1 AND c.Activo = 1 AND agg.PrecioMinimo IS NOT NULL))
      AND (@Texto IS NULL OR CHARINDEX(@Texto, p.Nombre) > 0 OR CHARINDEX(@Texto, p.Descripcion) > 0)
      AND (@IDCategoria IS NULL OR p.IDCategoria = @IDCategoria)
      AND (@PrecioMinimo IS NULL OR agg.PrecioMaximo >= @PrecioMinimo)
      AND (@PrecioMaximo IS NULL OR agg.PrecioMinimo <= @PrecioMaximo)
      AND (@SoloDisponibles = 0 OR agg.ExistenciaDisponible > 0)
    ORDER BY
        CASE WHEN @Orden = N'precio' AND @Direccion = N'asc'  THEN agg.PrecioMinimo END ASC,
        CASE WHEN @Orden = N'precio' AND @Direccion = N'desc' THEN agg.PrecioMinimo END DESC,
        CASE WHEN @Orden = N'nombre' AND @Direccion = N'desc' THEN p.Nombre END DESC,
        CASE WHEN @Orden = N'nombre' AND @Direccion = N'asc'  THEN p.Nombre END ASC,
        p.IDProducto
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE SP_Variantes_Crear
    @IDProducto        INT,
    @SKU               NVARCHAR(50),
    @Atributos         NVARCHAR(500),
    @Precio            DECIMAL(12,2),
    @ExistenciaInicial INT = 0,
    @IDUsuario         INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Producto WHERE IDProducto = @IDProducto)
        THROW 51001, N'Producto no encontrado.', 1;
    IF @ExistenciaInicial < 0
        THROW 51000, N'La existencia inicial no puede ser negativa.', 1;

    DECLARE @IDVariante INT;

    BEGIN TRAN;

    INSERT Variante (IDProducto, SKU, Atributos, Precio, ExistenciaFisica)
    VALUES (@IDProducto, @SKU, @Atributos, @Precio, @ExistenciaInicial);
    SET @IDVariante = SCOPE_IDENTITY();

    IF @ExistenciaInicial > 0
        INSERT MovimientoInventario (IDVariante, Tipo, Cantidad, Motivo, IDUsuario)
        VALUES (@IDVariante, N'Entrada', @ExistenciaInicial, N'Existencia inicial', @IDUsuario);

    DECLARE @Nuevo NVARCHAR(MAX) = (
        SELECT v.SKU, v.Atributos, v.Precio, v.ExistenciaFisica FROM Variante v WHERE v.IDVariante = @IDVariante
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC SP_Bitacora_Registrar @IDUsuario, N'Productos', N'Variante', @IDVariante, N'Crear', NULL, @Nuevo;

    COMMIT;

    SELECT @IDVariante AS IDVariante;
END
GO

CREATE OR ALTER PROCEDURE SP_Variantes_Actualizar
    @IDVariante INT,
    @Atributos  NVARCHAR(500),
    @Precio     DECIMAL(12,2),
    @Activo     BIT,
    @IDUsuario  INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @PrecioAnterior DECIMAL(12,2), @ActivoAnterior BIT;
    SELECT @PrecioAnterior = Precio, @ActivoAnterior = Activo FROM Variante WHERE IDVariante = @IDVariante;
    IF @PrecioAnterior IS NULL THROW 51001, N'Variante no encontrada.', 1;

    BEGIN TRAN;

    UPDATE Variante SET Atributos = @Atributos, Precio = @Precio, Activo = @Activo WHERE IDVariante = @IDVariante;

    IF @Precio <> @PrecioAnterior
        EXEC SP_Bitacora_Registrar @IDUsuario, N'Precios', N'Variante', @IDVariante, N'Actualizar',
             @PrecioAnterior, @Precio;

    IF @Activo <> @ActivoAnterior
        EXEC SP_Bitacora_Registrar @IDUsuario, N'Productos', N'Variante', @IDVariante,
             N'Desactivar', @ActivoAnterior, @Activo;

    COMMIT;
END
GO
