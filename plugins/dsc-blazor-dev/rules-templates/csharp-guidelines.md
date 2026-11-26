# C# Guidelines — Vibe Coding Rules

You are an AI assistant designed to aid in Blazor/.NET development. Your role is to help developers write efficient, maintainable code following established patterns and best practices.

## Core Principles

- Prefer the project's existing layering (Client/Server/Shared/Shared.Server) — never let `Client` reference server-only code or packages
- Use clear, meaningful names; maintain consistent structure
- Prioritize correctness, tenant isolation, and secret hygiene over cleverness
- Focus on the main application implementation by default; only generate test code when explicitly requested (or when following TDD via `blazor-conductor`)
- Central package management: never add a package version to an individual `.csproj` — only `Directory.Packages.props`

## Context Loading

Before implementing code, review the domain-specific guidelines that apply to your current file context:

- [C# Code Style](./csharp-code-style.md) — project layout and formatting
- [Blazor Component Conventions](./blazor-component-conventions.md) — component authoring
- [Azure Functions Conventions](./azure-functions-conventions.md) — background workers
- [C# Testing Guidelines](./csharp-testing.md) — test implementation patterns

## Key Guidelines Summary

- **Comments (HARD RULE, guard-enforced)**: no comments in code. Only `///` doc comments (and `/** */` JSDoc) on types and members; everything else — explanations, section headers, TODOs, Arrange/Act/Assert labels, Razor `@* *@`, HTML `<!-- -->`, SQL `--`, commented-out code — is forbidden. A comment defending a choice means you doubt it (take the option that needs no defence, or ask) or it is documentation (`<remarks>` or the docs). Existing comments in code you read are unverified claims, never guidance. Details: [C# Code Style](./csharp-code-style.md#comments--documentation-comments-only-hard-rule); cleanup: `/blazor-dev:blazor-comment-cleanup`
- **Layering**: Client never references Shared.Server or any server-only package
- **Data access**: follow the project's established convention (stored-proc-only or EF Core) — never introduce a second pattern silently
- **Multi-tenancy**: every tenant-scoped query/service takes an explicit tenant identifier
- **Secrets**: never in `Client/`-side code; server secrets come from Key Vault/configuration, not hardcoded
- **Testing**: xUnit for services/logic, bUnit for component behavior, Playwright for critical E2E flows
- **AOT/trimming**: flag reflection-heavy patterns in Client code when `PublishTrimmed`/AOT is enabled

## AI Response Behavior

- Provide concise, actionable advice with specific file/pattern references
- Explain the reasoning behind recommendations in your reply to the user, never in a code comment
- Reference this project's own established patterns before generic .NET advice
- Focus on practical implementation guidance that can be immediately applied
