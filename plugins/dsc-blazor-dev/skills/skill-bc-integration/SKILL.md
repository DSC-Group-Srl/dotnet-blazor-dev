---
name: skill-bc-integration
description: "Syncing a Blazor SaaS solution's entities against Microsoft Dynamics 365 Business Central via OData. Use when implementing or reviewing a Business Central integration/sync layer."
---

# Skill: Business Central OData Integration

## Purpose

Many DSC Blazor solutions integrate with Microsoft Dynamics 365 Business Central as the ERP of record (DynaHR syncs employees and expense notes with BC this way). This skill captures the integration-layer patterns.

## Core Pattern

- **OData API calls**: server-side only (never from `Client/`), authenticated via the server-to-server `AzureAD` app registration (see `skill-b2c-auth`) — not the consumer-facing B2C flow.
- **Sync direction and conflict handling**: define explicitly per entity whether BC or the Blazor app is the source of truth for each field, and what happens on a conflicting concurrent edit — don't leave this implicit.
- **Strategy-pattern sync** (see `skill-azure-functions-sync`): each sync status (create/update/delete/error-variants) is its own service, selected by a factory, running inside an Azure Functions background worker.
- **Idempotency**: BC API calls in a sync loop must be safe to retry — a transient failure followed by a retry should not create duplicate records in BC.

## Cross-Plugin Integration

If the **bc-dev** plugin is also installed in this session, its `al-mcp` MCP server (`mcp__plugin_bc-dev_al-mcp__*`) gives symbol-level visibility into the Business Central side of the integration — API pages, OData entity definitions, custom fields exposed for sync. Use it (when available) to verify the exact shape of the BC-side API contract before implementing the Blazor-side sync code, rather than guessing at field names/types. This is optional — the skill and the sync pattern work standalone if `bc-dev` isn't installed; only wire this cross-reference if the tool is actually available in the current session.

## Reviewing for This Pattern

Flag: OData calls made from `Client/`-side code (leaks the server-to-server credential path and CORS-exposes the ERP), a sync loop with no idempotency guard, or a sync status enum missing an explicit error-variant for a failure mode the code can actually hit.
