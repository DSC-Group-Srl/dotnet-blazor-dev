using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

public class EmployeeRepository
{
    public async Task Bad(SqlConnection connection, AppDbContext db, string name, string tableName, Guid tenantId)
    {
        /// ruleid: dsc-sql-string-concat
        var cmd = new SqlCommand("SELECT * FROM Employee WHERE Name = '" + name + "'", connection);

        /// ruleid: dsc-sql-string-concat
        var cmd2 = new SqlCommand($"SELECT * FROM Employee WHERE Name = '{name}'", connection);

        /// ruleid: dsc-sql-string-concat
        await using var cmd4 = new SqlCommand("SELECT * FROM " + tableName, connection)
        {
            CommandTimeout = 30
        };

        var cmd3 = connection.CreateCommand();
        /// ruleid: dsc-sql-string-concat
        cmd3.CommandText = "DELETE FROM Employee WHERE TenantId = '" + tenantId + "'";

        /// ruleid: dsc-sql-string-concat
        var rows = await connection.QueryAsync<Employee>($"SELECT * FROM Employee WHERE Name = '{name}'");

        /// ruleid: dsc-sql-string-concat
        var list = db.Employees.FromSqlRaw("SELECT * FROM Employee WHERE Name = '" + name + "'").ToList();

        /// ruleid: dsc-sql-string-concat
        await db.Database.ExecuteSqlRawAsync(string.Format("DELETE FROM Employee WHERE Name = '{0}'", name));
    }

    public async Task Good(SqlConnection connection, AppDbContext db, string name, Guid tenantId)
    {
        /// ok: dsc-sql-string-concat
        await using var cmd = new SqlCommand("dbo.usp_GetEmployee", connection)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.AddWithValue("@TenantId", tenantId);

        /// ok: dsc-sql-string-concat
        var rows = await connection.QueryAsync<Employee>("dbo.usp_FindEmployee", new { TenantId = tenantId, Name = name }, commandType: CommandType.StoredProcedure);

        /// ok: dsc-sql-string-concat
        var list = db.Employees.FromSqlInterpolated($"SELECT * FROM Employee WHERE Name = {name}").ToList();

        /// ok: dsc-sql-string-concat
        var list2 = db.Employees.FromSqlRaw("SELECT * FROM Employee WHERE Name = {0}", name).ToList();
    }
}
