---
description: >
  Prepare a clean, documented pull request draft for Blazor/.NET features or
  fixes with summary, testing notes, and checklist.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash
---

# Blazor Pull Request Preparation

## Step 1: Gather Changes

```bash
git status
git diff main...HEAD
git log main..HEAD --oneline
```

Also read the relevant `requirements/{req_name}/{req_name}-complete.md` if this PR closes out a `blazor-conductor` plan.

## Step 2: Draft the PR

```markdown
## Summary
{1-3 bullets: what changed and why}

## Components/Services Changed
- {list, grouped by project: Client / Server / Shared / Shared.Server / Domain}

## Testing
- [ ] `dotnet build` clean
- [ ] `dotnet test` — {X}/{X} passing
- [ ] Playwright E2E run (if a critical UI flow changed)
- [ ] Manual check against a dev/staging tenant (if data-access or auth changed)

## Data/Tenant Impact
- {Any schema/stored-procedure change, migration needed, tenant-isolation implication — or "None"}

## Checklist
- [ ] No secrets/connection strings in `Client/`-side code
- [ ] Package versions only in `Directory.Packages.props`
- [ ] Rules from `.claude/rules/` followed
```

## Step 3: Present

Show the draft to the user. Do not push, create, or open the PR yourself unless explicitly asked — this is a human/CI action.
