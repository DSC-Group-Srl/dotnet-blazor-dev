# C# Code Style

## Project Layout

- **Feature-based organization** within each project (`Services/{Feature}/`, `Components/{Feature}/`) over type-based folders where the project's own convention already does this
- **Central package management**: all `<PackageReference>` versions live in `Directory.Packages.props` (`ManagePackageVersionsCentrally=true`). Never add `Version="..."` to a `<PackageReference>` in an individual `.csproj`.
- **Project reference direction**: `Client` → `Shared` only. `Server`/`Shared.Server`/`ServiceFn` may reference `Shared` and each other as appropriate, but `Client` must never reference `Shared.Server` or pull in a server-only package (`Microsoft.Data.SqlClient`, Azure SDKs, etc.) — this is a common accidental leak that breaks WASM trimming/AOT and risks secret exposure.

## Formatting

- 4-space indentation, PascalCase for types/members/public properties, camelCase for locals/private fields (`_camelCase` for private fields is acceptable if the project already uses it — match existing convention)
- Nullable reference types: honor the project's `<Nullable>` setting; don't suppress warnings with `!` without a documented reason
- File-scoped namespaces (`namespace Foo.Bar;`) for new files unless the project's existing files use block-scoped

## Result Wrapping

- Service methods that can fail return a `ServiceResponse<T>`-style wrapper (`.Success`, `.Data`, `.ErrorMessage`) — always check `.Success` before using `.Data`, never assume success

## Async

- `Async` suffix on every async method; `ConfigureAwait(false)` in library/service code (not required in Blazor component code, which needs the sync context)
- Avoid `async void` except for true event handlers

## Data Access (follow whichever convention the project has already established)

**Stored-procedure-only** (the DynaHR default):
```csharp
await using var cmd = new SqlCommand("dbo.usp_GetEmployee", connection) { CommandType = CommandType.StoredProcedure };
cmd.Parameters.AddWithValue("@TenantId", tenantId);
```
No raw inline SQL, no ORM, unless the project has explicitly adopted one.

**EF Core** (only if the project uses it): keep query logic in repository/service classes, not directly in components; use `AsNoTracking()` for read-only queries.

## Multi-Tenancy

Every tenant-scoped table/query/service takes an explicit tenant identifier (typically a `Guid`) as a parameter — never rely on ambient/global state to determine tenant scope, and never share a connection/cache instance across tenants without keying it by tenant.
