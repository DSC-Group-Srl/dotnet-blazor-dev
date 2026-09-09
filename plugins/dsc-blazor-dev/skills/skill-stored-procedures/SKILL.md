---
name: skill-stored-procedures
description: "Stored-procedure-only SQL Server data access for Blazor/.NET solutions that don't use an ORM. Use when implementing or reviewing any data-access service method in a stored-proc-only project."
---

# Skill: Stored-Procedure-Only Data Access

## Purpose

Implement data access the DynaHR way: all database access goes through stored procedures — no direct table queries, no inline SQL, no ORM — using `Microsoft.Data.SqlClient` directly.

## Core Pattern

```csharp
public async Task<ServiceResponse<Employee>> GetEmployeeAsync(Guid tenantId, int employeeId)
{
    await using var connection = new SqlConnection(_connectionResolver.Resolve(tenantId));
    await connection.OpenAsync();

    await using var cmd = new SqlCommand("dbo.usp_GetEmployee", connection)
    {
        CommandType = CommandType.StoredProcedure
    };
    cmd.Parameters.AddWithValue("@TenantId", tenantId);
    cmd.Parameters.AddWithValue("@EmployeeId", employeeId);

    await using var reader = await cmd.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
        return ServiceResponse<Employee>.Fail("Employee not found");

    return ServiceResponse<Employee>.Ok(MapEmployee(reader));
}
```

## Rules

- **No raw/ad-hoc SQL** — every query is a named stored procedure. If a query doesn't exist yet, that's a DB-migration task, not a reason to inline SQL.
- **Always parameterize** — `AddWithValue`/`Parameters.Add` with typed values, never string-concatenate a value into a command text (there shouldn't be command text to concatenate into, but this also applies to any dynamic proc-name construction).
- **`ServiceResponse<T>` wrapping** — every service method returns a wrapper with `.Success`/`.Data`/`.ErrorMessage`; callers check `.Success` before touching `.Data`.
- **Dynamic WHERE/`$filter` construction** (list/search endpoints): use the project's `QueryProvider`/`Filter.CreateList()`-style abstraction rather than hand-building SQL fragments — keeps the proc-call surface consistent and injection-safe.
- **Tenant scoping**: depends on which multi-tenancy pattern the project uses (see `skill-multitenancy`) — a shared-database project passes the tenant identifier as an explicit `@TenantId`-style parameter on every proc call; a per-tenant-database project already opened the tenant-scoped connection before this call, so an explicit `@TenantId` parameter on the proc itself is redundant (don't add one just to "be safe" — confirm the pattern first).

## Reviewing for This Pattern

When auditing a change, flag:
- A new `DbSet<T>`/EF Core usage in a project that has no existing EF Core footprint (introduces a second data-access pattern silently)
- Inline `SqlCommand` with a hand-built command-text string instead of `CommandType.StoredProcedure`
- In a shared-database project: a stored-procedure call missing a tenant parameter where sibling procs have one
- In a per-tenant-database project: a new table/proc that adds a `TenantId` column/parameter it doesn't need — the real per-row scoping column there is the sub-tenant discriminator (e.g. `CompanyId`), not the tenant id
