---
description: >
  Create a detailed technical specification (.spec.md) that serves as an
  implementable blueprint for Blazor/.NET features. Reads architecture.md if
  it exists. Outputs to requirements/{req_name}/.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, Skill
---

# Blazor Technical Specification Workflow

Your goal is to produce `requirements/{req_name}/{req_name}.spec.md` — an implementable blueprint.

## Step 1: Gather Context

- If `requirements/{req_name}/{req_name}.architecture.md` exists, read it and use its decisions as ground truth (layering, data-access convention, tenant model).
- Otherwise, analyze the existing codebase directly: `Grep`/`Glob` + the C# LSP server for similar existing components/services, check `Directory.Packages.props` and each project's `.csproj` for what's already in use.

## Step 2: Write the Spec

```markdown
# Spec: <Feature Name>

**Date**: YYYY-MM-DD
**Complexity**: [LOW/MEDIUM/HIGH]

## Overview
## Components/Services
- {Component/service name} — {project it lives in: Client/Server/Shared/Shared.Server}
  - Parameters/properties, DI dependencies, render mode (if a component)
## Data Access
- {Stored procedure names + parameters, or EF Core entity/query shape}
- Tenant scoping: {how the tenant identifier flows through}
## API Surface (if applicable)
- {Endpoint/route, request/response shape, auth requirement}
## Integration Points
- {External API, Azure Function trigger, event}
## Test Plan
- xUnit: {service/logic test names}
- bUnit: {component render/interaction test names}
- Playwright E2E (if the feature has a critical user flow): {scenario}
## Open Questions
```

## Step 3: Handoff

- **LOW complexity** → recommend `agent "blazor-dev:blazor-developer"`
- **MEDIUM/HIGH complexity** → recommend `agent "blazor-dev:blazor-conductor"`

Present the spec to the user before recommending next steps — do not auto-delegate.
