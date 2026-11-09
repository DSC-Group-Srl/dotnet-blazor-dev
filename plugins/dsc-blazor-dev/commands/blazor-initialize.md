---
description: >
  Initialize the Blazor/.NET development environment and workspace. Use when
  setting up a new project or configuring an existing one for this plugin's
  agents/skills/rules.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch
---

# Blazor Environment Initialization

Your goal is to initialize the Blazor development environment and workspace for `${input:ProjectName}`.

## Phase 0: Rules Injection (Plugin Mode)

A `SessionStart` hook (`tools/rules/precondition_hook.sh`) checks for `.claude/rules/csharp-guidelines.md` on every session and nudges agents to offer this command when it's missing.

```bash
mkdir -p .claude/rules
cp "${CLAUDE_PLUGIN_ROOT}/rules-templates/"*.md .claude/rules/
```

**Rules installed:**

| Rule | Scope | Purpose |
|------|-------|---------|
| `csharp-guidelines.md` | `**/*.cs`, `**/*.razor` | Core hub |
| `csharp-code-style.md` | `**/*.cs` | Project layout, central package management, nullable reference types |
| `blazor-component-conventions.md` | `**/*.razor` | Component authoring, parameter binding, render modes |
| `azure-functions-conventions.md` | `**/*Fn/**/*.cs` | Isolated-worker Azure Functions patterns |
| `csharp-testing.md` | `**/*Tests*/**/*.cs` | xUnit/bUnit test structure |

### CLAUDE.md Generation

```markdown
# ${input:ProjectName} — Claude Code Instructions

## Framework
This project uses the **blazor-dev** plugin for Claude Code.
Agents, skills, and workflows are available via the `blazor-dev:` namespace.

## Quick Start
- `/blazor-dev:blazor-spec-create` — Create specifications
- `/blazor-dev:blazor-build` — Build the solution
- `agent "blazor-dev:blazor-architect"` — Architecture design
- `agent "blazor-dev:blazor-developer"` — Implementation

## Project-Specific Notes
[Add your project-specific instructions here]
```

**Human Review:** confirm rules were copied correctly before proceeding.

## Phase 1: Environment Check

**Required:**
- [ ] .NET SDK matching the solution's target framework (`dotnet --version`)
- [ ] `csharp-ls` global tool for LSP support (`dotnet tool install --global csharp-ls` — the SessionStart hook attempts this automatically)
- [ ] Git for version control

**Recommended:**
- [ ] Node.js (for `npx @playwright/mcp` — Playwright E2E via MCP)
- [ ] Azure CLI, if the project deploys to Azure
- [ ] `dab` (Data API Builder CLI), if the project exposes SQL Server via the `dab --mcp-stdio` MCP pattern (see DynaHR's `.mcp.json` for a working example)

## Phase 2: Project Structure

For a new solution, prefer the reference layering unless the project has its own established shape:

```
${input:ProjectName}.sln
├── ${input:ProjectName}.Portal/
│   ├── Client/            # Blazor WASM frontend (browser-safe only)
│   ├── Server/             # ASP.NET Core API + host
│   ├── Shared/              # Browser-safe models, enums, DTOs
│   ├── Shared.Server/       # Server-side services, DB access, Azure SDK
│   └── ServiceFn/           # Azure Functions (isolated worker, background sync)
├── ${input:ProjectName}.Domain/
│   ├── .Model / .Calculations / .Validation / .MasterData
├── ${input:ProjectName}.Tests/    # xUnit + bUnit
├── Directory.Packages.props       # Central package management — never per-.csproj versions
└── README.md
```

**Human Review:** validate the layering matches the project's actual needs before scaffolding.

## Phase 3: Data Access Convention Decision

**🔒 Human Gate**: confirm with the stakeholder whether this project uses stored-procedure-only data access (the DynaHR default — `Microsoft.Data.SqlClient` + named procs, no ORM) or Entity Framework Core. Document the decision in the project's `CLAUDE.md` — every subsequent agent invocation reads this to avoid introducing a second, inconsistent pattern.

## Phase 4: MCP Recommendations

Wire project-specific MCP servers in the project's own `.mcp.json` (not this plugin's) when applicable:
- **Data API Builder** (`dab start --mcp-stdio --config <dab-config.json>`) if the project exposes SQL Server for agent inspection — see DynaHR's `.mcp.json` for the exact shape
- **Azure MCP Server** if the project has a meaningful Azure footprint (Functions, Key Vault, Blob, Service Bus) the agent needs to inspect

## Phase 5: Verification

- ✅ `.claude/rules/csharp-guidelines.md` exists
- ✅ `dotnet build` succeeds on the solution
- ✅ `csharp-ls` resolves (C# LSP active — check hover/go-to-definition works in a `.cs` file)
- ✅ `dotnet test` runs (even with zero tests, the harness should execute cleanly)
- ✅ Data-access convention documented in `CLAUDE.md`

## Next Steps

```
agent "blazor-dev:blazor-architect"    # Design solutions
agent "blazor-dev:blazor-developer"    # Implement features directly (LOW complexity)
agent "blazor-dev:blazor-conductor"    # Plan → Implement → Review → Commit (MEDIUM/HIGH)
/blazor-dev:blazor-build               # Build and validate
```

## Security Considerations

- Never put secrets, connection strings, or API keys in `Client/`-side code — it runs in the browser
- Review your organization's AI usage policy before pasting customer data into a session
- Use `.gitignore` for `bin/`, `obj/`, `TestResults/`, and any local `appsettings.Development.json` secrets

---

**Environment Initialization Complete.**
