CREATE TABLE Categoria (
    IDCategoria INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Categoria PRIMARY KEY,
    Nombre      NVARCHAR(100)     NOT NULL CONSTRAINT UQ_Categoria_Nombre UNIQUE,
    Descripcion NVARCHAR(500)     NULL,
    Activo      BIT               NOT NULL CONSTRAINT DF_Categoria_Activo DEFAULT 1
);
GO

CREATE TABLE Producto (
    IDProducto    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Producto PRIMARY KEY,
    IDCategoria   INT               NOT NULL CONSTRAINT FK_Producto_Categoria REFERENCES Categoria (IDCategoria),
    Nombre        NVARCHAR(150)     NOT NULL,
    Descripcion   NVARCHAR(2000)    NOT NULL CONSTRAINT DF_Producto_Descripcion DEFAULT N'',
    Activo        BIT               NOT NULL CONSTRAINT DF_Producto_Activo DEFAULT 1,
    FechaCreacion DATETIME2(3)      NOT NULL CONSTRAINT DF_Producto_FechaCreacion DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_Producto_IDCategoria ON Producto (IDCategoria, Activo);
GO

CREATE TABLE ImagenProducto (
    IDImagenProducto INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ImagenProducto PRIMARY KEY,
    IDProducto       INT               NOT NULL CONSTRAINT FK_ImagenProducto_Producto REFERENCES Producto (IDProducto) ON DELETE CASCADE,
    Url              NVARCHAR(500)     NOT NULL,
    Orden            TINYINT           NOT NULL CONSTRAINT DF_ImagenProducto_Orden DEFAULT 0
);
CREATE INDEX IX_ImagenProducto_IDProducto ON ImagenProducto (IDProducto, Orden);
GO

CREATE TABLE Variante (
    IDVariante           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Variante PRIMARY KEY,
    IDProducto           INT               NOT NULL CONSTRAINT FK_Variante_Producto REFERENCES Producto (IDProducto),
    SKU                  NVARCHAR(50)      NOT NULL CONSTRAINT UQ_Variante_SKU UNIQUE,
    Atributos            NVARCHAR(500)     NOT NULL CONSTRAINT DF_Variante_Atributos DEFAULT N'{}',
    Precio               DECIMAL(12,2)     NOT NULL,
    ExistenciaFisica     INT               NOT NULL CONSTRAINT DF_Variante_ExistenciaFisica DEFAULT 0,
    ExistenciaReservada  INT               NOT NULL CONSTRAINT DF_Variante_ExistenciaReservada DEFAULT 0,
    ExistenciaDisponible AS (ExistenciaFisica - ExistenciaReservada) PERSISTED,
    Activo               BIT               NOT NULL CONSTRAINT DF_Variante_Activo DEFAULT 1,
    CONSTRAINT CK_Variante_Atributos CHECK (ISJSON(Atributos) = 1),
    CONSTRAINT CK_Variante_Precio CHECK (Precio > 0),
    CONSTRAINT CK_Variante_ExistenciaFisica CHECK (ExistenciaFisica >= 0),
    CONSTRAINT CK_Variante_ExistenciaReservada CHECK (ExistenciaReservada >= 0 AND ExistenciaReservada <= ExistenciaFisica)
);
CREATE INDEX IX_Variante_IDProducto ON Variante (IDProducto) INCLUDE (Precio, ExistenciaDisponible, Activo);
GO
