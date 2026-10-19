---
name: skill-multitenancy
description: "Multi-tenant SaaS data-access patterns for Blazor/.NET solutions. Use when designing or implementing any query, service, or cache that touches tenant-scoped data."
---

# Skill: Multi-Tenancy

## Purpose

Prevent cross-tenant data leakage in a multi-tenant SaaS Blazor solution, modeled on DSC's DynaHR platform: every tenant is identified by a `CustomerTenant` Guid, and every piece of tenant-scoped data access must be explicitly scoped by it.

## Core Pattern

- **Tenant identifier**: a `Guid` (`CustomerTenant` in DynaHR), passed explicitly into every service method that reads or writes tenant data — never inferred from ambient/global/static state.
- **Per-tenant database connections**: resolved via a `DatabaseUtilities`-style helper that maps `CustomerTenant` → connection string, rather than a single shared connection string plus a `WHERE TenantId = @X` filter bolted on inconsistently. Both patterns exist in the wild — confirm which the project uses before implementing.
- **Never mix tenant data**: any in-memory cache, static field, or singleton service that could accidentally hold data from tenant A while serving a request for tenant B is a bug, full stop — scope cache keys by tenant identifier.

## Implementation Checklist

First confirm which of the two patterns above the project actually uses (check `DatabaseUtilities`
or equivalent) — the rest of this checklist branches on that:

**If shared database (single connection string, rows discriminated by a tenant column):**
- [ ] Every stored procedure/EF query touching tenant data takes the tenant identifier as an explicit parameter
- [ ] No `static`/singleton field holds tenant-specific state without being keyed by tenant

**If per-tenant database (connection itself resolved from the tenant identifier):**
- [ ] Tenant scope is NOT re-added as a column/parameter on tables/procs/DTOs living inside that
  tenant's own database — it's already implicit in which connection was opened. Adding it anyway
  is not "extra safety", it's a redundant/misleading column that invites the two mistakes below.
- [ ] The identifier actually used to scope rows *within* a tenant's own database is the
  sub-tenant discriminator that really varies there (e.g. `CompanyId`), not the tenant id
- [ ] No `static`/singleton field holds tenant-specific state without being keyed by tenant

**Always:**
- [ ] Server-side session/claims carry the authenticated user's tenant, and every request handler derives the tenant from that (never from a client-supplied, unvalidated parameter)
- [ ] Tests exist that prove tenant A's request cannot see tenant B's data (see `skill-dotnet-testing`)

## Anti-Patterns to Flag

```csharp
// ❌ Tenant inferred from ambient/ThreadStatic state — fragile under async, easy to get wrong
private static Guid CurrentTenant;

// ❌ Cache keyed only by entity ID, not tenant — leaks across tenants
private static readonly Dictionary<int, Employee> _cache = new();

// ✅ Explicit tenant parameter, cache (if any) keyed by (tenant, entity)
public async Task<ServiceResponse<Employee>> GetEmployeeAsync(Guid tenantId, int employeeId)

// ❌ Redundant TenantId column on a table that already lives in a per-tenant database — the
// connection itself is the tenant boundary; a TenantId column here is dead weight at best and,
// once someone starts filtering by it "for safety", a source of silent bugs at worst (e.g. a
// caller passing the wrong tenant id alongside the right connection). This exact mistake has
// shipped twice in DynaHR (an Outbox table, then a Draft table) before being caught in review —
// don't repeat it. The real per-row discriminator inside a tenant's own database is CompanyId.
CREATE TABLE dbo.SomeTable (
    Id UNIQUEIDENTIFIER PRIMARY KEY,
    TenantId UNIQUEIDENTIFIER NOT NULL,  -- ❌ redundant in a per-tenant-database project
    CompanyId UNIQUEIDENTIFIER NOT NULL, -- ✅ this is the real scoping column here
    ...
);
```

## Cross-References

- `skill-stored-procedures` — the data-access layer this pattern most often lives in
- `skill-b2c-auth` — where the authenticated tenant claim originates
