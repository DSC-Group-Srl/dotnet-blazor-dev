# C# Testing Guidelines

## Test Types

- **xUnit** — services, business logic, sync strategies, anything not directly rendering UI
- **bUnit** — Razor component rendering and interaction behavior (does the component render the expected markup, does clicking a button raise the expected `EventCallback`)
- **Playwright** (via the **playwright** MCP server or a Playwright test project) — critical end-to-end user flows only; not a substitute for unit/component coverage

## Structure

- Given/When/Then naming or `MethodUnderTest_Scenario_ExpectedResult` — match whatever the project's existing test suite already uses
- One assertion concern per test where practical; use `Assert.Multiple`/FluentAssertions grouping when checking several related properties of one result

## TDD Cycle (enforced by blazor-conductor)

1. **RED** — write the failing test first, run it, confirm it fails for the right reason
2. **GREEN** — minimal code to pass
3. **REFACTOR** — clean up with tests still green

## What to Test

- Every new service method with a non-trivial return path (including the failure path — what does `ServiceResponse<T>.Success == false` look like)
- Every new/changed component's rendered output and any parameter/EventCallback behavior
- Tenant-isolation-sensitive code: a test that proves data for tenant A cannot leak into a call scoped to tenant B
- AOT/trimming-sensitive serialization: a test exercising the source-generated (not reflection-based) serialization path if the project uses `PublishTrimmed`

## Test Data

Use builder/factory helpers for test data rather than inline object literals repeated across tests — keeps tenant-scoping and required-field changes to one place.
