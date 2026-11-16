# Azure Functions Conventions

## Isolated Worker Model

Use the isolated-worker model (`Microsoft.Azure.Functions.Worker`), not the deprecated in-process model, for new Functions.

## Background Sync Workers

If the project has a sync engine pattern (syncing local entities against an external system such as an ERP):
- Keep the sync strategy per-status as separate service classes, selected at runtime by a factory (e.g. `{Entity}SyncFactory` selecting `SyncOk`/`SyncToUpdate`/`SyncToCreate`/`SyncError*` handlers) rather than one large branching method
- Log every sync attempt's outcome for observability — sync failures are silent by default otherwise

## Cold-Start Mitigation

If a heartbeat/warmup timer-triggered Function exists to prevent cold starts on the main worker Function, verify the heartbeat interval stays shorter than the target Function's timeout window whenever either changes.

## Secrets

Function configuration secrets come from Azure Key Vault (via Key Vault references in the Function App's configuration), not from `local.settings.json`/`appsettings.json` in a deployed environment — those files are for local development only and must not contain production secrets.

## Multi-Tenancy

Same rule as elsewhere in this plugin: every sync/processing loop that touches tenant data must be explicitly scoped by tenant identifier, never assume a single-tenant context.
