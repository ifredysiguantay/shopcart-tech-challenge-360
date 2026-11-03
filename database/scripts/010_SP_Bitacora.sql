-- Códigos de error de negocio (THROW): 51000 validación, 51001 no encontrado, 51002 conflicto,
-- 51003 prohibido, 51004 regla de negocio, 51005 no autenticado.

CREATE OR ALTER PROCEDURE SP_Bitacora_Registrar
    @IDUsuario     INT,
    @Modulo        NVARCHAR(30),
    @Entidad       NVARCHAR(50),
    @IDEntidad     INT,
    @Accion        NVARCHAR(20),
    @ValorAnterior NVARCHAR(MAX) = NULL,
    @ValorNuevo    NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT Bitacora (IDUsuario, Modulo, Entidad, IDEntidad, Accion, ValorAnterior, ValorNuevo)
    VALUES (@IDUsuario, @Modulo, @Entidad, @IDEntidad, @Accion, @ValorAnterior, @ValorNuevo);
END
GO

CREATE OR ALTER PROCEDURE SP_Bitacora_Listar
    @Modulo         NVARCHAR(30) = NULL,
    @Pagina         INT = 1,
    @TamanoPagina   INT = 20
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.IDBitacora, b.Fecha, b.Modulo, b.Entidad, b.IDEntidad, b.Accion,
           b.IDUsuario, u.Correo AS Usuario, b.ValorAnterior, b.ValorNuevo,
           COUNT(*) OVER () AS TotalRegistros
    FROM Bitacora b
    LEFT JOIN Usuario u ON u.IDUsuario = b.IDUsuario
    WHERE @Modulo IS NULL OR b.Modulo = @Modulo
    ORDER BY b.Fecha DESC, b.IDBitacora DESC
    OFFSET (@Pagina - 1) * @TamanoPagina ROWS FETCH NEXT @TamanoPagina ROWS ONLY;
END
GO
