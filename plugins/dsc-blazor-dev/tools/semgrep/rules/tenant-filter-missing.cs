using System.Data;
using Microsoft.Data.SqlClient;

public class EmployeeService
{
    public async Task<int> CountWithoutTenant(SqlConnection connection, int departmentId)
    {
        /// ruleid: dsc-tenant-filter-missing
        await using var cmd = new SqlCommand("dbo.usp_CountEmployees", connection)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.AddWithValue("@DepartmentId", departmentId);
        return (int)await cmd.ExecuteScalarAsync();
    }

    public async Task<int> CountWithTenant(SqlConnection connection, Guid tenantId, int departmentId)
    {
        /// ok: dsc-tenant-filter-missing
        await using var cmd = new SqlCommand("dbo.usp_CountEmployees", connection)
        {
            CommandType = CommandType.StoredProcedure
        };
        cmd.Parameters.AddWithValue("@TenantId", tenantId);
        cmd.Parameters.AddWithValue("@DepartmentId", departmentId);
        return (int)await cmd.ExecuteScalarAsync();
    }

    public async Task<int> CountWithTypedTenant(SqlConnection connection, Guid tenantId)
    {
        /// ok: dsc-tenant-filter-missing
        await using var cmd = new SqlCommand("dbo.usp_CountEmployees", connection);
        cmd.CommandType = CommandType.StoredProcedure;
        cmd.Parameters.Add("@TenantId", SqlDbType.UniqueIdentifier).Value = tenantId;
        return (int)await cmd.ExecuteScalarAsync();
    }
}
