CREATE TABLE Cupon (
    IDCupon              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Cupon PRIMARY KEY,
    Codigo               NVARCHAR(30)      NOT NULL CONSTRAINT UQ_Cupon_Codigo UNIQUE,
    Tipo                 NVARCHAR(12)      NOT NULL,
    Valor                DECIMAL(12,2)     NOT NULL,
    FechaInicio          DATETIME2(0)      NOT NULL,
    FechaFin             DATETIME2(0)      NOT NULL,
    MontoMinimo          DECIMAL(12,2)     NOT NULL CONSTRAINT DF_Cupon_MontoMinimo DEFAULT 0,
    LimiteUsosTotal      INT               NOT NULL,
    LimiteUsosPorCliente INT               NOT NULL,
    IDCategoria          INT               NULL CONSTRAINT FK_Cupon_Categoria REFERENCES Categoria (IDCategoria),
    UsosActuales         INT               NOT NULL CONSTRAINT DF_Cupon_UsosActuales DEFAULT 0,
    Activo               BIT               NOT NULL CONSTRAINT DF_Cupon_Activo DEFAULT 1,
    CONSTRAINT CK_Cupon_Tipo CHECK (Tipo IN (N'Porcentaje', N'MontoFijo')),
    CONSTRAINT CK_Cupon_Valor CHECK (Valor > 0 AND (Tipo <> N'Porcentaje' OR Valor <= 100)),
    CONSTRAINT CK_Cupon_Vigencia CHECK (FechaFin > FechaInicio),
    CONSTRAINT CK_Cupon_MontoMinimo CHECK (MontoMinimo >= 0),
    CONSTRAINT CK_Cupon_Limites CHECK (LimiteUsosTotal > 0 AND LimiteUsosPorCliente > 0),
    CONSTRAINT CK_Cupon_Usos CHECK (UsosActuales >= 0 AND UsosActuales <= LimiteUsosTotal)
);
GO

CREATE TABLE Carrito (
    IDCarrito           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Carrito PRIMARY KEY,
    IDUsuario           INT               NULL CONSTRAINT FK_Carrito_Usuario REFERENCES Usuario (IDUsuario),
    TokenInvitado       UNIQUEIDENTIFIER  NULL,
    IDCupon             INT               NULL CONSTRAINT FK_Carrito_Cupon REFERENCES Cupon (IDCupon),
    Estado              NVARCHAR(12)      NOT NULL CONSTRAINT DF_Carrito_Estado DEFAULT N'Activo',
    FechaCreacion       DATETIME2(3)      NOT NULL CONSTRAINT DF_Carrito_FechaCreacion DEFAULT SYSUTCDATETIME(),
    FechaActualizacion  DATETIME2(3)      NOT NULL CONSTRAINT DF_Carrito_FechaActualizacion DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Carrito_Estado CHECK (Estado IN (N'Activo', N'Convertido', N'Fusionado')),
    CONSTRAINT CK_Carrito_Propietario CHECK ((IDUsuario IS NOT NULL AND TokenInvitado IS NULL) OR (IDUsuario IS NULL AND TokenInvitado IS NOT NULL))
);
CREATE UNIQUE INDEX UX_Carrito_UsuarioActivo ON Carrito (IDUsuario) WHERE Estado = N'Activo' AND IDUsuario IS NOT NULL;
CREATE UNIQUE INDEX UX_Carrito_TokenInvitado ON Carrito (TokenInvitado) WHERE TokenInvitado IS NOT NULL;
CREATE INDEX IX_Carrito_Actividad ON Carrito (Estado, FechaActualizacion);
GO

CREATE TABLE CarritoItem (
    IDCarritoItem INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CarritoItem PRIMARY KEY,
    IDCarrito     INT               NOT NULL CONSTRAINT FK_CarritoItem_Carrito REFERENCES Carrito (IDCarrito) ON DELETE CASCADE,
    IDVariante    INT               NOT NULL CONSTRAINT FK_CarritoItem_Variante REFERENCES Variante (IDVariante),
    Cantidad      INT               NOT NULL,
    CONSTRAINT UQ_CarritoItem_Variante UNIQUE (IDCarrito, IDVariante),
    CONSTRAINT CK_CarritoItem_Cantidad CHECK (Cantidad > 0)
);
GO

CREATE TABLE Checkout (
    IDCheckout        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Checkout PRIMARY KEY,
    IDCarrito         INT               NOT NULL CONSTRAINT FK_Checkout_Carrito REFERENCES Carrito (IDCarrito),
    IDUsuario         INT               NOT NULL CONSTRAINT FK_Checkout_Usuario REFERENCES Usuario (IDUsuario),
    IDDireccion       INT               NOT NULL CONSTRAINT FK_Checkout_Direccion REFERENCES Direccion (IDDireccion),
    IDCupon           INT               NULL CONSTRAINT FK_Checkout_Cupon REFERENCES Cupon (IDCupon),
    Estado            NVARCHAR(12)      NOT NULL CONSTRAINT DF_Checkout_Estado DEFAULT N'Activo',
    Subtotal          DECIMAL(12,2)     NOT NULL,
    Descuento         DECIMAL(12,2)     NOT NULL,
    Total             DECIMAL(12,2)     NOT NULL,
    FechaCreacion     DATETIME2(3)      NOT NULL CONSTRAINT DF_Checkout_FechaCreacion DEFAULT SYSUTCDATETIME(),
    FechaExpiracion   DATETIME2(3)      NOT NULL,
    CONSTRAINT CK_Checkout_Estado CHECK (Estado IN (N'Activo', N'Pagado', N'Expirado', N'Reemplazado')),
    CONSTRAINT CK_Checkout_Montos CHECK (Subtotal >= 0 AND Descuento >= 0 AND Descuento <= Subtotal AND Total = Subtotal - Descuento)
);
CREATE INDEX IX_Checkout_Vigencia ON Checkout (Estado, FechaExpiracion);
CREATE INDEX IX_Checkout_IDCarrito ON Checkout (IDCarrito, Estado);
GO

CREATE TABLE ReservaExistencia (
    IDReservaExistencia INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ReservaExistencia PRIMARY KEY,
    IDCheckout          INT               NOT NULL CONSTRAINT FK_ReservaExistencia_Checkout REFERENCES Checkout (IDCheckout),
    IDVariante          INT               NOT NULL CONSTRAINT FK_ReservaExistencia_Variante REFERENCES Variante (IDVariante),
    Cantidad            INT               NOT NULL,
    PrecioUnitario      DECIMAL(12,2)     NOT NULL,
    DescuentoLinea      DECIMAL(12,2)     NOT NULL,
    CONSTRAINT UQ_ReservaExistencia_Variante UNIQUE (IDCheckout, IDVariante),
    CONSTRAINT CK_ReservaExistencia_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT CK_ReservaExistencia_Montos CHECK (PrecioUnitario > 0 AND DescuentoLinea >= 0 AND DescuentoLinea <= Cantidad * PrecioUnitario)
);
GO

CREATE TABLE EstadoPedido (
    IDEstadoPedido TINYINT      NOT NULL CONSTRAINT PK_EstadoPedido PRIMARY KEY,
    Nombre         NVARCHAR(30) NOT NULL CONSTRAINT UQ_EstadoPedido_Nombre UNIQUE
);
GO

CREATE TABLE TransicionPedido (
    IDEstadoOrigen  TINYINT NOT NULL CONSTRAINT FK_TransicionPedido_Origen  REFERENCES EstadoPedido (IDEstadoPedido),
    IDEstadoDestino TINYINT NOT NULL CONSTRAINT FK_TransicionPedido_Destino REFERENCES EstadoPedido (IDEstadoPedido),
    CONSTRAINT PK_TransicionPedido PRIMARY KEY (IDEstadoOrigen, IDEstadoDestino),
    CONSTRAINT CK_TransicionPedido_Distinto CHECK (IDEstadoOrigen <> IDEstadoDestino)
);
GO

CREATE TABLE Pedido (
    IDPedido          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Pedido PRIMARY KEY,
    IDUsuario         INT               NOT NULL CONSTRAINT FK_Pedido_Usuario REFERENCES Usuario (IDUsuario),
    IDEstadoPedido    TINYINT           NOT NULL CONSTRAINT FK_Pedido_EstadoPedido REFERENCES EstadoPedido (IDEstadoPedido),
    IDCheckout        INT               NULL CONSTRAINT FK_Pedido_Checkout REFERENCES Checkout (IDCheckout),
    IDCupon           INT               NULL CONSTRAINT FK_Pedido_Cupon REFERENCES Cupon (IDCupon),
    CodigoCupon       NVARCHAR(30)      NULL,
    DireccionEntrega  NVARCHAR(600)     NOT NULL,
    Subtotal          DECIMAL(12,2)     NOT NULL,
    Descuento         DECIMAL(12,2)     NOT NULL,
    Total             DECIMAL(12,2)     NOT NULL,
    MontoDevuelto     DECIMAL(12,2)     NOT NULL CONSTRAINT DF_Pedido_MontoDevuelto DEFAULT 0,
    ClaveIdempotencia NVARCHAR(100)     NOT NULL,
    FechaCreacion     DATETIME2(3)      NOT NULL CONSTRAINT DF_Pedido_FechaCreacion DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Pedido_Montos CHECK (Subtotal >= 0 AND Descuento >= 0 AND Descuento <= Subtotal AND Total = Subtotal - Descuento),
    CONSTRAINT CK_Pedido_MontoDevuelto CHECK (MontoDevuelto >= 0 AND MontoDevuelto <= Total)
);
CREATE UNIQUE INDEX UX_Pedido_Checkout ON Pedido (IDCheckout) WHERE IDCheckout IS NOT NULL;
CREATE UNIQUE INDEX UX_Pedido_ClaveIdempotencia ON Pedido (IDUsuario, ClaveIdempotencia);
CREATE INDEX IX_Pedido_Estado_Fecha ON Pedido (IDEstadoPedido, FechaCreacion) INCLUDE (Total, MontoDevuelto, IDUsuario);
CREATE INDEX IX_Pedido_Usuario_Fecha ON Pedido (IDUsuario, FechaCreacion DESC);
GO

CREATE TABLE PedidoDetalle (
    IDPedidoDetalle  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PedidoDetalle PRIMARY KEY,
    IDPedido         INT               NOT NULL CONSTRAINT FK_PedidoDetalle_Pedido REFERENCES Pedido (IDPedido),
    IDVariante       INT               NOT NULL CONSTRAINT FK_PedidoDetalle_Variante REFERENCES Variante (IDVariante),
    SKU              NVARCHAR(50)      NOT NULL,
    NombreProducto   NVARCHAR(250)     NOT NULL,
    PrecioUnitario   DECIMAL(12,2)     NOT NULL,
    Cantidad         INT               NOT NULL,
    DescuentoLinea   DECIMAL(12,2)     NOT NULL,
    TotalLinea       DECIMAL(12,2)     NOT NULL,
    CantidadDevuelta INT               NOT NULL CONSTRAINT DF_PedidoDetalle_CantidadDevuelta DEFAULT 0,
    MontoDevuelto    DECIMAL(12,2)     NOT NULL CONSTRAINT DF_PedidoDetalle_MontoDevuelto DEFAULT 0,
    CONSTRAINT CK_PedidoDetalle_Cantidad CHECK (Cantidad > 0 AND CantidadDevuelta >= 0 AND CantidadDevuelta <= Cantidad),
    CONSTRAINT CK_PedidoDetalle_Montos CHECK (DescuentoLinea >= 0 AND TotalLinea = Cantidad * PrecioUnitario - DescuentoLinea AND MontoDevuelto >= 0 AND MontoDevuelto <= TotalLinea)
);
CREATE INDEX IX_PedidoDetalle_IDPedido ON PedidoDetalle (IDPedido);
CREATE INDEX IX_PedidoDetalle_IDVariante ON PedidoDetalle (IDVariante);
GO

CREATE TABLE HistorialEstadoPedido (
    IDHistorialEstadoPedido INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_HistorialEstadoPedido PRIMARY KEY,
    IDPedido                INT               NOT NULL CONSTRAINT FK_HistorialEstadoPedido_Pedido REFERENCES Pedido (IDPedido),
    IDEstadoAnterior        TINYINT           NULL CONSTRAINT FK_HistorialEstadoPedido_Anterior REFERENCES EstadoPedido (IDEstadoPedido),
    IDEstadoNuevo           TINYINT           NOT NULL CONSTRAINT FK_HistorialEstadoPedido_Nuevo REFERENCES EstadoPedido (IDEstadoPedido),
    IDUsuario               INT               NULL CONSTRAINT FK_HistorialEstadoPedido_Usuario REFERENCES Usuario (IDUsuario),
    Fecha                   DATETIME2(3)      NOT NULL CONSTRAINT DF_HistorialEstadoPedido_Fecha DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_HistorialEstadoPedido_IDPedido ON HistorialEstadoPedido (IDPedido, Fecha);
GO

CREATE TABLE Pago (
    IDPago            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Pago PRIMARY KEY,
    IDPedido          INT               NOT NULL CONSTRAINT FK_Pago_Pedido REFERENCES Pedido (IDPedido) CONSTRAINT UQ_Pago_Pedido UNIQUE,
    Monto             DECIMAL(12,2)     NOT NULL,
    Metodo            NVARCHAR(30)      NOT NULL,
    Estado            NVARCHAR(12)      NOT NULL CONSTRAINT DF_Pago_Estado DEFAULT N'Aprobado',
    Referencia        NVARCHAR(50)      NOT NULL,
    ClaveIdempotencia NVARCHAR(100)     NOT NULL,
    Fecha             DATETIME2(3)      NOT NULL CONSTRAINT DF_Pago_Fecha DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Pago_Estado CHECK (Estado IN (N'Aprobado', N'Reembolsado')),
    CONSTRAINT CK_Pago_Monto CHECK (Monto >= 0)
);
GO

CREATE TABLE Devolucion (
    IDDevolucion    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Devolucion PRIMARY KEY,
    IDPedido        INT               NOT NULL CONSTRAINT FK_Devolucion_Pedido REFERENCES Pedido (IDPedido),
    IDPedidoDetalle INT               NOT NULL CONSTRAINT FK_Devolucion_PedidoDetalle REFERENCES PedidoDetalle (IDPedidoDetalle),
    Cantidad        INT               NOT NULL,
    Monto           DECIMAL(12,2)     NOT NULL,
    Motivo          NVARCHAR(250)     NOT NULL,
    IDUsuario       INT               NOT NULL CONSTRAINT FK_Devolucion_Usuario REFERENCES Usuario (IDUsuario),
    Fecha           DATETIME2(3)      NOT NULL CONSTRAINT DF_Devolucion_Fecha DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_Devolucion_Cantidad CHECK (Cantidad > 0 AND Monto >= 0)
);
CREATE INDEX IX_Devolucion_IDPedido ON Devolucion (IDPedido);
GO

CREATE TABLE CuponUso (
    IDCuponUso INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CuponUso PRIMARY KEY,
    IDCupon    INT               NOT NULL CONSTRAINT FK_CuponUso_Cupon REFERENCES Cupon (IDCupon),
    IDUsuario  INT               NOT NULL CONSTRAINT FK_CuponUso_Usuario REFERENCES Usuario (IDUsuario),
    IDPedido   INT               NOT NULL CONSTRAINT FK_CuponUso_Pedido REFERENCES Pedido (IDPedido) CONSTRAINT UQ_CuponUso_Pedido UNIQUE,
    Anulado    BIT               NOT NULL CONSTRAINT DF_CuponUso_Anulado DEFAULT 0,
    Fecha      DATETIME2(3)      NOT NULL CONSTRAINT DF_CuponUso_Fecha DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_CuponUso_Cliente ON CuponUso (IDCupon, IDUsuario) WHERE Anulado = 0;
GO

CREATE TABLE MovimientoInventario (
    IDMovimientoInventario INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_MovimientoInventario PRIMARY KEY,
    IDVariante             INT               NOT NULL CONSTRAINT FK_MovimientoInventario_Variante REFERENCES Variante (IDVariante),
    Tipo                   NVARCHAR(12)      NOT NULL,
    Cantidad               INT               NOT NULL,
    Motivo                 NVARCHAR(250)     NOT NULL,
    IDUsuario              INT               NULL CONSTRAINT FK_MovimientoInventario_Usuario REFERENCES Usuario (IDUsuario),
    IDPedido               INT               NULL CONSTRAINT FK_MovimientoInventario_Pedido REFERENCES Pedido (IDPedido),
    Fecha                  DATETIME2(3)      NOT NULL CONSTRAINT DF_MovimientoInventario_Fecha DEFAULT SYSUTCDATETIME(),
    CONSTRAINT CK_MovimientoInventario_Tipo CHECK (Tipo IN (N'Entrada', N'Salida', N'Ajuste', N'Devolucion')),
    CONSTRAINT CK_MovimientoInventario_Cantidad CHECK (
        (Tipo IN (N'Entrada', N'Devolucion') AND Cantidad > 0)
        OR (Tipo = N'Salida' AND Cantidad < 0)
        OR (Tipo = N'Ajuste' AND Cantidad <> 0)),
    CONSTRAINT CK_MovimientoInventario_Motivo CHECK (LEN(LTRIM(RTRIM(Motivo))) > 0)
);
CREATE INDEX IX_MovimientoInventario_Variante ON MovimientoInventario (IDVariante, IDMovimientoInventario) INCLUDE (Cantidad);
GO
