---
name: skill-azure-functions-sync
description: "Isolated-worker Azure Functions background sync engine patterns for Blazor SaaS solutions — strategy-pattern sync services, heartbeat cold-start mitigation. Use when implementing or reviewing a background worker that syncs local entities against an external system."
---

# Skill: Azure Functions Sync Engine

## Purpose

Implement the DynaHR-style background sync pattern: a timer/queue-triggered isolated-worker Azure Function that reconciles local entities against an external system (an ERP, in DynaHR's case Business Central via OData), plus a heartbeat Function to prevent cold starts.

## Strategy-Pattern Sync

Keyed on a status enum (e.g. `EmployeePerCompanySynchStatus`: `SyncOk`, `SyncToUpdate`, `SyncToCreate`, `SyncErrorCreating`, `SyncErrorUpdating`, `SyncToDelete`, `SyncOpenInBc`, `SyncErrorMailChange`), with each strategy implemented as a separate service class and selected at runtime by a factory:

```csharp
public interface IEmployeeSyncStrategy
{
    Task<SyncResult> SyncAsync(Guid tenantId, Employee employee, CancellationToken ct);
}

public class EmployeeSyncFactory
{
    public IEmployeeSyncStrategy Resolve(EmployeeSyncStatus status) => status switch
    {
        EmployeeSyncStatus.SyncToCreate => _createStrategy,
        EmployeeSyncStatus.SyncToUpdate => _updateStrategy,
        EmployeeSyncStatus.SyncToDelete => _deleteStrategy,
        _ => throw new InvalidOperationException($"No sync strategy for status {status}")
    };
}
```

Avoid one large branching method — each strategy is independently testable and reviewable.

## Isolated Worker Model

Use `Microsoft.Azure.Functions.Worker` (isolated process), not the deprecated in-process model, for new Functions. Configure DI in `Program.cs` via `HostBuilder`.

## Cold-Start Mitigation

A timer-triggered heartbeat Function calls the main sync Function (and any other latency-sensitive dependency) on an interval **shorter than** the target Function's timeout window. When either interval changes, re-verify that ordering holds.

## Secrets

Function App configuration secrets (connection strings, API keys) come from Azure Key Vault references, never hardcoded in `local.settings.json`/`appsettings.json` for a deployed environment — those are local-dev-only.

## Multi-Tenancy

Every sync loop iterates per-tenant explicitly — never assume a single-tenant context in a background worker. See `skill-multitenancy`.

## Observability

Log the outcome of every sync attempt (success, and which error category on failure) — sync failures in a background worker are silent to the end user by default; logging is the only visibility unless the failure also surfaces a status field the UI reads.
