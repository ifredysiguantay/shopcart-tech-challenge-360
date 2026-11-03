CREATE TABLE Rol (
    IDRol  TINYINT      NOT NULL CONSTRAINT PK_Rol PRIMARY KEY,
    Nombre NVARCHAR(30) NOT NULL CONSTRAINT UQ_Rol_Nombre UNIQUE
);
GO

CREATE TABLE Usuario (
    IDUsuario     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Usuario PRIMARY KEY,
    Correo        NVARCHAR(256)     NOT NULL CONSTRAINT UQ_Usuario_Correo UNIQUE,
    PasswordHash  NVARCHAR(255)     NOT NULL,
    Nombre        NVARCHAR(100)     NOT NULL,
    IDRol         TINYINT           NOT NULL CONSTRAINT FK_Usuario_Rol REFERENCES Rol (IDRol),
    Activo        BIT               NOT NULL CONSTRAINT DF_Usuario_Activo DEFAULT 1,
    FechaCreacion DATETIME2(3)      NOT NULL CONSTRAINT DF_Usuario_FechaCreacion DEFAULT SYSUTCDATETIME()
);
GO

CREATE TABLE RefreshToken (
    IDRefreshToken  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RefreshToken PRIMARY KEY,
    IDUsuario       INT               NOT NULL CONSTRAINT FK_RefreshToken_Usuario REFERENCES Usuario (IDUsuario),
    TokenHash       CHAR(64)          NOT NULL CONSTRAINT UQ_RefreshToken_TokenHash UNIQUE,
    FechaExpiracion DATETIME2(3)      NOT NULL,
    Revocado        BIT               NOT NULL CONSTRAINT DF_RefreshToken_Revocado DEFAULT 0,
    FechaCreacion   DATETIME2(3)      NOT NULL CONSTRAINT DF_RefreshToken_FechaCreacion DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_RefreshToken_IDUsuario ON RefreshToken (IDUsuario);
GO

CREATE TABLE Direccion (
    IDDireccion  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Direccion PRIMARY KEY,
    IDUsuario    INT               NOT NULL CONSTRAINT FK_Direccion_Usuario REFERENCES Usuario (IDUsuario),
    Alias        NVARCHAR(50)      NOT NULL,
    Direccion    NVARCHAR(250)     NOT NULL,
    Ciudad       NVARCHAR(100)     NOT NULL,
    Departamento NVARCHAR(100)     NOT NULL,
    Telefono     NVARCHAR(20)      NOT NULL,
    Activo       BIT               NOT NULL CONSTRAINT DF_Direccion_Activo DEFAULT 1
);
CREATE INDEX IX_Direccion_IDUsuario ON Direccion (IDUsuario) WHERE Activo = 1;
GO
