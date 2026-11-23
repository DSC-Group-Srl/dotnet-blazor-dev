# Template — Plan (work-package graph + wave log)

`requirements/{req}/{req}.plan.md`, written by blazor-conductor after plan approval and appended
to after every wave. It is also the resume point: a restarted conductor reads it and continues
after the last logged wave. Replace placeholders; drop sections that are empty.

```markdown
# Plan: {req} — {title}

{1–2 sentences: what gets built, why.}

**Tier:** {MEDIUM|HIGH} · **Base:** {commit sha the run started from} · **Branch:** {integration branch}
**Test scope:** {isolated + integration (database: …) | isolated only — integration tests not executed (accepted by user)}
**Data access:** {stored-proc | EF Core} · **Projects:** {Client / Server / Shared / Shared.Server / ServiceFn}
**Approved:** {date}

## Work packages

| WP | Title | Wave | Depends on | Owns (globs) | Types / components | Test classes | Domains | Review |
|----|-------|------|-----------|--------------|--------------------|--------------|---------|--------|
| WP-1 | Contracts + data access | 1 | — | `src/Shared/Leave/**`, `src/Shared.Server/Leave/**`, `tests/Shared.Server.Tests/Leave/**` | `LeaveRequestDto`, `ILeaveRepository`, `LeaveRepository` | `LeaveRepositoryTests` | data, multitenancy | full |
| WP-2 | SQL scripts | 1 | — | `db/Leave/**` | `usp_LeaveRequest_Insert`, `usp_LeaveRequest_List` | — | data | light |
| WP-3 | API endpoints | 2 | WP-1, WP-2 | `src/Server/Leave/**`, `tests/Server.Tests/Leave/**` | `LeaveController` | `LeaveControllerTests` | api, auth | full |
| WP-4 | UI | 2 | WP-1 | `src/Client/Pages/Leave/**`, `tests/Client.Tests/Leave/**` | `LeaveList.razor`, `LeaveRequestDialog.razor` | `LeaveListTests` | ui, aot | light |

**Shared single-writer files** (applied by the conductor per wave, never by a WP):
`*.sln`, `Directory.Packages.props`, `Directory.Build.props`, `*.csproj`, `Program.cs` and DI
registration classes, `appsettings*.json`, `_Imports.razor`, the navigation menu, shared `.resx`,
EF Core migrations + snapshot, `.vscode/*`.

**Test class → WP:** `LeaveRepositoryTests` → WP-1 · `LeaveControllerTests` → WP-3 · `LeaveListTests` → WP-4

## Planned objects

| Object type | New/Ext | Count | Est. complexity (S/M/L) |
|-------------|---------|------:|-------------------------|
| class | New | 3 | M |
| class | Ext | 1 | S |
| component | New | 1 | M |
| razor page | New | 1 | M |
| test class | New | 3 | M |
| other | New | 2 | S |

## Open questions

1. {question — options} → {answer, once given}

## Wave log

### Wave 1 — {date}
- WPs: WP-1, WP-2 · review: {verdict} ({critical}/{major}/{minor}) · tests: {passed/total | integration not executed} · fix rounds: {n}
- Shared files applied: {… | none}
- Skills: 🧠 {skill·pattern, …}

## Deferred

- {what} — surfaced in wave {k} by {WP-n | review} — {later wave | backlog}
```

## Rules

- WP `owns` globs must not overlap; shared files appear in no WP. An existing file that changes
  is owned by exactly one WP.
- **Planned objects** is read by a script (`emit.py BlzEstimate --plan`), not by a person: one
  row per object type × New/Ext, filled from the WP table. It is the ex-ante size the duration
  estimate learns from, so it must be complete before wave 1.
  - *Object type*: `class` (any C# type: class, record, interface, enum), `component` (a
    non-routable `.razor`), `razor page` (a `.razor` with `@page`), `test class`, `other` (SQL
    scripts, migrations, static assets).
  - *New/Ext*: `New` = a new file; `Ext` = an existing file of this solution that changes.
  - *Count*: a plain integer. *Est. complexity*: `S`, `M` or `L` for the row as a whole.
- MEDIUM: 1–3 WPs in ≤2 waves. HIGH: ≤6 WPs in ≤3 waves. Split only for disjoint files or a
  real dependency.
- No code blocks, no step-by-step TDD recipes (the implementer owns the method).
