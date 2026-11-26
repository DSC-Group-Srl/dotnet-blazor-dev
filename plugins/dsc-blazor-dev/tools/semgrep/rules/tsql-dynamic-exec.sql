/// ruleid: dsc-tsql-tenant-param-missing
CREATE PROCEDURE dbo.usp_SearchEmployee
    @Name NVARCHAR(100),
    @OrderBy NVARCHAR(50)
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM dbo.Employee WHERE Name = ''' + @Name + N''' ORDER BY ' + @OrderBy;
    /// ruleid: dsc-tsql-dynamic-exec
    EXEC (@sql);
    /// ruleid: dsc-tsql-dynamic-exec
    EXEC ('SELECT * FROM dbo.Employee WHERE Name = ''' + @Name + '''');
    /// ruleid: dsc-tsql-dynamic-exec
    EXEC sp_executesql @sql;
END
GO

/// ok: dsc-tsql-tenant-param-missing
CREATE OR ALTER PROCEDURE dbo.usp_SearchEmployeeSafe
    @TenantId UNIQUEIDENTIFIER,
    @Name NVARCHAR(100)
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM dbo.Employee WHERE TenantId = @TenantId AND Name = @Name';
    /// ok: dsc-tsql-dynamic-exec
    EXEC sp_executesql @sql, N'@TenantId UNIQUEIDENTIFIER, @Name NVARCHAR(100)', @TenantId = @TenantId, @Name = @Name;
    /// ok: dsc-tsql-dynamic-exec
    EXEC dbo.usp_LogSearch @TenantId = @TenantId;
END
GO
