CREATE OR ALTER PROCEDURE SP_Auth_RegistrarCliente
    @Correo       NVARCHAR(256),
    @PasswordHash NVARCHAR(255),
    @Nombre       NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM Usuario WHERE Correo = @Correo)
        THROW 51002, N'El correo ya está registrado.', 1;

    INSERT Usuario (Correo, PasswordHash, Nombre, IDRol)
    VALUES (@Correo, @PasswordHash, @Nombre, 1);

    SELECT u.IDUsuario, u.Correo, u.Nombre, u.IDRol
    FROM Usuario u WHERE u.IDUsuario = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE SP_Auth_ObtenerPorCorreo
    @Correo NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.IDUsuario, u.Correo, u.PasswordHash, u.Nombre, u.IDRol, u.Activo
    FROM Usuario u WHERE u.Correo = @Correo;
END
GO

CREATE OR ALTER PROCEDURE SP_Auth_ObtenerPorID
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.IDUsuario, u.Correo, u.Nombre, u.IDRol, r.Nombre AS Rol, u.Activo
    FROM Usuario u JOIN Rol r ON r.IDRol = u.IDRol
    WHERE u.IDUsuario = @IDUsuario;
END
GO

CREATE OR ALTER PROCEDURE SP_Auth_GuardarRefreshToken
    @IDUsuario       INT,
    @TokenHash       CHAR(64),
    @FechaExpiracion DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT RefreshToken (IDUsuario, TokenHash, FechaExpiracion)
    VALUES (@IDUsuario, @TokenHash, @FechaExpiracion);
END
GO

CREATE OR ALTER PROCEDURE SP_Auth_RotarRefreshToken
    @TokenHashActual CHAR(64),
    @TokenHashNuevo  CHAR(64),
    @FechaExpiracion DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @IDUsuario INT, @Revocado BIT, @Expira DATETIME2(3), @Activo BIT;

    BEGIN TRAN;

    SELECT @IDUsuario = t.IDUsuario, @Revocado = t.Revocado, @Expira = t.FechaExpiracion, @Activo = u.Activo
    FROM RefreshToken t WITH (UPDLOCK, ROWLOCK)
    JOIN Usuario u ON u.IDUsuario = t.IDUsuario
    WHERE t.TokenHash = @TokenHashActual;

    IF @IDUsuario IS NULL
        THROW 51005, N'Refresh token inválido.', 1;

    IF @Revocado = 1
    BEGIN
        UPDATE RefreshToken SET Revocado = 1 WHERE IDUsuario = @IDUsuario AND Revocado = 0;
        COMMIT;
        THROW 51005, N'Refresh token reutilizado: se cerraron todas las sesiones del usuario.', 1;
    END

    IF @Expira <= SYSUTCDATETIME() OR @Activo = 0
        THROW 51005, N'Refresh token expirado o usuario inactivo.', 1;

    UPDATE RefreshToken SET Revocado = 1 WHERE TokenHash = @TokenHashActual;
    INSERT RefreshToken (IDUsuario, TokenHash, FechaExpiracion) VALUES (@IDUsuario, @TokenHashNuevo, @FechaExpiracion);

    COMMIT;

    SELECT u.IDUsuario, u.Correo, u.Nombre, u.IDRol
    FROM Usuario u WHERE u.IDUsuario = @IDUsuario;
END
GO

CREATE OR ALTER PROCEDURE SP_Auth_RevocarRefreshToken
    @TokenHash CHAR(64)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE RefreshToken SET Revocado = 1 WHERE TokenHash = @TokenHash;
END
GO

CREATE OR ALTER PROCEDURE SP_Usuarios_Crear
    @Correo       NVARCHAR(256),
    @PasswordHash NVARCHAR(255),
    @Nombre       NVARCHAR(100),
    @IDRol        TINYINT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM Rol WHERE IDRol = @IDRol)
        THROW 51000, N'El rol indicado no existe.', 1;
    IF EXISTS (SELECT 1 FROM Usuario WHERE Correo = @Correo)
        THROW 51002, N'El correo ya está registrado.', 1;

    INSERT Usuario (Correo, PasswordHash, Nombre, IDRol) VALUES (@Correo, @PasswordHash, @Nombre, @IDRol);

    SELECT u.IDUsuario, u.Correo, u.Nombre, u.IDRol, u.Activo
    FROM Usuario u WHERE u.IDUsuario = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE SP_Usuarios_Listar
    @Pagina       INT = 1,
    @TamanoPagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.IDUsuario, u.Correo, u.Nombre, u.IDRol, r.Nombre AS Rol, u.Activo, u.FechaCreacion,
           COUNT(*) OVER () AS TotalRegistros
    FROM Usuario u JOIN Rol r ON r.IDRol = u.IDRol
    ORDER BY u.IDUsuario
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO

CREATE OR ALTER PROCEDURE SP_Usuarios_CambiarEstado
    @IDUsuario INT,
    @Activo    BIT,
    @IDActor   INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    IF @IDUsuario = @IDActor
        THROW 51004, N'No puedes cambiar el estado de tu propio usuario.', 1;

    BEGIN TRAN;

    UPDATE Usuario SET Activo = @Activo WHERE IDUsuario = @IDUsuario;
    IF @@ROWCOUNT = 0
        THROW 51001, N'Usuario no encontrado.', 1;

    IF @Activo = 0
        UPDATE RefreshToken SET Revocado = 1 WHERE IDUsuario = @IDUsuario AND Revocado = 0;

    COMMIT;

    SELECT u.IDUsuario, u.Correo, u.Nombre, u.IDRol, u.Activo FROM Usuario u WHERE u.IDUsuario = @IDUsuario;
END
GO

CREATE OR ALTER PROCEDURE SP_Direcciones_Crear
    @IDUsuario    INT,
    @Alias        NVARCHAR(50),
    @Direccion    NVARCHAR(250),
    @Ciudad       NVARCHAR(100),
    @Departamento NVARCHAR(100),
    @Telefono     NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT Direccion (IDUsuario, Alias, Direccion, Ciudad, Departamento, Telefono)
    VALUES (@IDUsuario, @Alias, @Direccion, @Ciudad, @Departamento, @Telefono);

    SELECT d.IDDireccion, d.Alias, d.Direccion, d.Ciudad, d.Departamento, d.Telefono
    FROM Direccion d WHERE d.IDDireccion = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE SP_Direcciones_Listar
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.IDDireccion, d.Alias, d.Direccion, d.Ciudad, d.Departamento, d.Telefono
    FROM Direccion d
    WHERE d.IDUsuario = @IDUsuario AND d.Activo = 1
    ORDER BY d.IDDireccion;
END
GO

CREATE OR ALTER PROCEDURE SP_Direcciones_Actualizar
    @IDDireccion  INT,
    @IDUsuario    INT,
    @Alias        NVARCHAR(50),
    @Direccion    NVARCHAR(250),
    @Ciudad       NVARCHAR(100),
    @Departamento NVARCHAR(100),
    @Telefono     NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Propietario INT, @Activo BIT;
    SELECT @Propietario = IDUsuario, @Activo = Activo FROM Direccion WHERE IDDireccion = @IDDireccion;

    IF @Propietario IS NULL OR @Activo = 0 THROW 51001, N'Dirección no encontrada.', 1;
    IF @Propietario <> @IDUsuario THROW 51003, N'No tienes acceso a esta dirección.', 1;

    UPDATE Direccion
    SET Alias = @Alias, Direccion = @Direccion, Ciudad = @Ciudad, Departamento = @Departamento, Telefono = @Telefono
    WHERE IDDireccion = @IDDireccion;

    SELECT d.IDDireccion, d.Alias, d.Direccion, d.Ciudad, d.Departamento, d.Telefono
    FROM Direccion d WHERE d.IDDireccion = @IDDireccion;
END
GO

CREATE OR ALTER PROCEDURE SP_Direcciones_Desactivar
    @IDDireccion INT,
    @IDUsuario   INT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;

    DECLARE @Propietario INT, @Activo BIT;
    SELECT @Propietario = IDUsuario, @Activo = Activo FROM Direccion WHERE IDDireccion = @IDDireccion;

    IF @Propietario IS NULL OR @Activo = 0 THROW 51001, N'Dirección no encontrada.', 1;
    IF @Propietario <> @IDUsuario THROW 51003, N'No tienes acceso a esta dirección.', 1;

    UPDATE Direccion SET Activo = 0 WHERE IDDireccion = @IDDireccion;
END
GO
