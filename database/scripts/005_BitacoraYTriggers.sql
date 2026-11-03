CREATE TABLE Bitacora (
    IDBitacora    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Bitacora PRIMARY KEY,
    IDUsuario     INT               NULL CONSTRAINT FK_Bitacora_Usuario REFERENCES Usuario (IDUsuario),
    Fecha         DATETIME2(3)      NOT NULL CONSTRAINT DF_Bitacora_Fecha DEFAULT SYSUTCDATETIME(),
    Modulo        NVARCHAR(30)      NOT NULL,
    Entidad       NVARCHAR(50)      NOT NULL,
    IDEntidad     INT               NULL,
    Accion        NVARCHAR(20)      NOT NULL,
    ValorAnterior NVARCHAR(MAX)     NULL,
    ValorNuevo    NVARCHAR(MAX)     NULL
);
CREATE INDEX IX_Bitacora_Modulo_Fecha ON Bitacora (Modulo, Fecha DESC);
GO

CREATE OR ALTER TRIGGER TR_Bitacora_Inmutable ON Bitacora
INSTEAD OF UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 51004, N'La bitácora no puede modificarse ni eliminarse.', 1;
END
GO

CREATE OR ALTER TRIGGER TR_Pedido_ValidarTransicion ON Pedido
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(IDEstadoPedido)
       AND EXISTS (
            SELECT 1
            FROM inserted i
            JOIN deleted d ON d.IDPedido = i.IDPedido
            WHERE i.IDEstadoPedido <> d.IDEstadoPedido
              AND NOT EXISTS (
                    SELECT 1 FROM TransicionPedido t
                    WHERE t.IDEstadoOrigen = d.IDEstadoPedido AND t.IDEstadoDestino = i.IDEstadoPedido))
        THROW 51004, N'Transición de estado de pedido no permitida.', 1;
END
GO
