---
name: skill-semgrep
description: "Free, local Semgrep Community Edition security scan for Blazor/.NET solutions (C#, Razor, JS/TS, appsettings JSON, T-SQL stored procedures) with DSC's own rule set: SQL built by concatenation, missing tenant filter, MarkupString from data, AllowAnonymous on write endpoints, anonymous Azure Functions, disabled certificate validation, secrets in appsettings, JS interop eval. Use when auditing or reviewing a diff for security, before a PR on code that touches data access, auth, JS interop or settings, when asked for SAST / a security scan / Semgrep, or when adding a Semgrep rule."
---

# Skill: Semgrep CE security scan

## Purpose

A static security scan that runs on the developer's machine, offline, on private code, at no
cost. It complements the compiler and Roslyn analyzers (`skill-roslyn-analyzers`): analyzers see
types and the whole build; these rules see patterns that are specific to DSC's stack (stored
procedures, tenant scoping, B2C endpoints, Blazor `MarkupString`, JS interop, settings files)
and file types the compiler never reads (`.sql`, `appsettings*.json`, `.razor` markup, JS).

Why Semgrep CE and not CodeQL: the CodeQL CLI licence forbids use on private code without a
paid GitHub Advanced Security licence. The Semgrep CE engine is LGPL-2.1 and free for commercial
use on private code. DSC uses **only** the CE engine with its own rules:

- never `semgrep login`, `semgrep ci`, `--pro`, the AppSec Platform or Semgrep Assistant;
- never `--config p/...` or `--config auto` (registry download, see "Licences" below);
- always `--metrics=off` (the wrapper sets it, plus `--oss-only` and `--disable-version-check`).

## When to run it

| Situation | Command (from the repository root) |
|---|---|
| Review of a branch / PR, audit default scope | `python "${CLAUDE_PLUGIN_ROOT}/tools/semgrep/semgrep_scan.py"` (files changed vs `main`, incl. staged, unstaged, untracked) |
| Full audit of a codebase | `python "${CLAUDE_PLUGIN_ROOT}/tools/semgrep/semgrep_scan.py" --all` |
| One folder or file | `... semgrep_scan.py --paths src/Server db/Procedures` |
| Another base branch | `... semgrep_scan.py --base origin/develop` |
| Machine-readable result for an agent | add `--json` (prints the summary JSON) |

Run it before a PR whenever the change touches data access (ADO.NET, Dapper, EF raw SQL,
stored procedures), authentication/authorization attributes, Azure Functions HTTP triggers,
`MarkupString`, JS interop or any `appsettings*.json` / `local.settings.json`.

Exit codes: `0` no unsuppressed ERROR finding (WARNING/INFO never fail); `1` at least one
unsuppressed ERROR finding; `2` Semgrep is missing or the scan failed (the message says why).

Outputs (default folder `<temp>/dsc-semgrep/<repo name>/`, change with `--out`; nothing is
written into the repository):

- `semgrep.sarif` — SARIF 2.1.0, triaged findings carry a SARIF `suppressions` entry. Opens in
  VS Code (SARIF Viewer extension) and can be uploaded by CI tools that read SARIF.
- `semgrep-summary.json` — counts per severity, the findings (rule, severity, path, line,
  message, matched line), suppressed findings, scan errors, Semgrep version.
- `semgrep.json` — Semgrep's raw JSON output.

## Install Semgrep CE

Requires Python 3.10+ (the plugin already ensures a Python on SessionStart).

| OS | Install | Notes |
|---|---|---|
| Windows | `python -m pip install --user semgrep` or `pipx install semgrep` | Native Windows support went GA in autumn 2025. Verified here: Semgrep 1.187.0 installs from PyPI and scans natively on Windows 11 with Python 3.14, no WSL needed. If `semgrep` is not found after a `--user` install, add `%APPDATA%\Python\Python3xx\Scripts` to PATH or set `DSC_SEMGREP_BIN` |
| macOS | `brew install semgrep` or `pipx install semgrep` | |
| Linux / WSL | `pipx install semgrep` or `python3 -m pip install --user semgrep` | |
| Docker (no install) | `docker run --rm -v "${PWD}:/src" -v "<plugin>/tools/semgrep/rules:/rules:ro" -w /src semgrep/semgrep semgrep scan --oss-only --metrics=off --config /rules --sarif-output=/src/semgrep.sarif` | Fallback when Python packages cannot be installed. Scans the whole folder; the wrapper (changed-files scope, triage, summary) does not drive Docker. Delete `semgrep.sarif` afterwards |

Check with `semgrep --version`. A dedicated venv works too: point `DSC_SEMGREP_BIN` at
`<venv>\Scripts\semgrep.exe`.

Known Windows issue: plain `semgrep --test` on a folder with several rules starts parallel
processes that race on `~/.semgrep/settings.yml` (`PermissionError ... settings.yml`). Use the
wrapper's `--self-test`, which gives each run a private read-only settings file.

## Offline

The wrapper only passes local rule files, `--oss-only`, `--metrics=off` and
`--disable-version-check`, and removes `SEMGREP_APP_TOKEN` from the child environment. A scan
with local rules downloads nothing. Installing Semgrep is the only step that needs the network
(PyPI, Homebrew or Docker Hub); for an air-gapped machine, `pip download semgrep` on a
connected machine and `pip install --no-index --find-links <folder> semgrep` on the target.

## Reading the results

1. Start from `counts` in the summary. ERROR findings block a PR; WARNING findings need a human
   decision; INFO findings are prompts to check (e.g. a procedure without `@TenantId`).
2. For each finding open the file at the line. The `message` says what is wrong and what to do,
   and points at the plugin skill with the right pattern.
3. Confirm by reading the code around it. These rules are intra-file and mostly syntactic:
   they do not follow data across methods or files. A `MarkupString` fed by a constant built
   elsewhere is a false positive; a sanitizer in a helper the rule does not know about is too.
4. In an audit verdict, cite the rule id and `file:line`, and say whether you confirmed it.

| Rule | Severity | Catches | Plugin skill |
|---|---|---|---|
| `dsc-sql-string-concat` | ERROR | concatenated / interpolated / `string.Format` SQL into `SqlCommand`, `CommandText`, Dapper `Query*`/`Execute*`, EF `FromSqlRaw`/`ExecuteSqlRaw`/`SqlQueryRaw` | skill-stored-procedures |
| `dsc-tenant-filter-missing` | WARNING | a method that creates a `SqlCommand` but never adds `@TenantId` | skill-multitenancy |
| `dsc-tsql-dynamic-exec` | WARNING | `EXEC(@sql)`, `EXEC('...' + @x)`, `sp_executesql @sql` without parameters in `.sql` | skill-stored-procedures |
| `dsc-tsql-tenant-param-missing` | INFO | `CREATE/ALTER PROCEDURE` without a `@TenantId` parameter | skill-multitenancy |
| `dsc-markupstring-untrusted` / `-razor` | WARNING | `(MarkupString)x` / `new MarkupString(x)` with a non-constant, unsanitized value in `.cs`, `.razor`, `.cshtml` | skill-blazor-author-component |
| `dsc-allow-anonymous-sensitive` | WARNING | `[AllowAnonymous]` on a controller or on POST/PUT/PATCH/DELETE actions; `MapPost/Put/Patch/Delete(...).AllowAnonymous()` | skill-b2c-auth |
| `dsc-function-anonymous-http-trigger` | WARNING | `AuthorizationLevel.Anonymous` in an Azure Functions HTTP trigger | skill-azure-functions-sync |
| `dsc-cert-validation-disabled` | ERROR | certificate callbacks that return `true`, `DangerousAcceptAnyServerCertificateValidator` | skill-bc-integration |
| `dsc-secret-in-appsettings` / `dsc-connection-string-secret` | ERROR | non-empty secret-looking keys and `Password=` / `AccountKey=` connection strings in `appsettings*.json`, `local.settings.json`, `secrets*.json` | skill-b2c-auth |
| `dsc-jsruntime-eval` | ERROR | `IJSRuntime.Invoke*("eval" / "Function" / "setTimeout" ...)` | skill-blazor-js-interop |
| `dsc-jsruntime-dynamic-identifier` | WARNING | `IJSRuntime.Invoke*` with a variable function name | skill-blazor-js-interop |
| `dsc-js-eval` / `dsc-js-html-sink` | ERROR / WARNING | `eval`, string `setTimeout`, `new Function`; `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write` with a non-constant value | skill-blazor-js-interop |

## Triage: false positives and accepted risks

`// nosemgrep` is a code comment: DSC's comment rule forbids it and the comment-guard blocks
it. Triage lives in one reviewed file at the repository root, `.dsc-semgrep-triage.json`
(commit it, review it like code):

```json
{
  "skip_rules": [
    { "rule": "dsc-tenant-filter-missing", "reason": "one database per tenant: the connection is already tenant-scoped" },
    { "rule": "dsc-tsql-tenant-param-missing", "reason": "one database per tenant" }
  ],
  "suppressions": [
    {
      "rule": "dsc-allow-anonymous-sensitive",
      "path": "src/Server/Controllers/B2CCallbackController.cs",
      "match": "[AllowAnonymous]",
      "reason": "B2C API connector callback, authenticated with basic auth in the filter",
      "by": "initials",
      "date": "2026-11-26"
    }
  ]
}
```

- `match` is the trimmed text of the flagged line (copy it from `findings[].match` in the
  summary). A suppression survives line moves but expires when the flagged line changes, so
  the finding comes back for a fresh look.
- `skip_rules` switches a rule off for the repository; use it only when the rule does not apply
  to the architecture (per-tenant databases), never to silence a real issue.
- Every entry needs a `reason`. An agent never adds entries on its own: it proposes them and
  the developer decides.
- Suppressed findings stay in the summary (`suppressed_findings`) and in the SARIF with a
  `suppressions` entry, so an audit can still list them.

## Adding or changing a rule

Rules live in `${CLAUDE_PLUGIN_ROOT}/tools/semgrep/rules/`, one YAML file per topic, each with a
test file of the same name (`<name>.yaml` + `<name>.cs|.razor|.js|.json|.sql`).

1. Write the rule. Id prefix `dsc-`; ids contain no dots (the wrapper strips Semgrep's
   path prefix at the last dot). `severity: ERROR` only for findings that are almost always a
   real vulnerability; otherwise WARNING or INFO. Explanations go in `message` (what is wrong,
   what to do, which plugin skill) and `metadata` (cwe, owasp, confidence); YAML `#` comments
   are not used.
2. Write the test file with a bad and a good example per pattern. Annotations are
   documentation comments, which both Semgrep and the comment rule accept: `/// ruleid: <id>`
   on the line above a line that must match, `/// ok: <id>` above one that must not.
   (`/** ruleid: ... */` is not recognised by Semgrep.) One test file per YAML file: Semgrep
   pairs them by name, so a second fixture with the same name breaks the pairing; put a rule
   for another language in its own YAML file.
3. Use `languages: [csharp]`, `[javascript, typescript]` or `[regex]`. Semgrep has no Razor or
   T-SQL parser: `.razor`/`.cshtml` markup and `.sql` use `regex` rules with
   `paths: include:`. C# object initializers need their own pattern
   (`new SqlCommand(...) { ... }` does not match `new SqlCommand(...)`).
4. Validate and test:
   `semgrep scan --validate --metrics=off --config <rule>.yaml` then
   `python "${CLAUDE_PLUGIN_ROOT}/tools/semgrep/semgrep_scan.py" --self-test` (must end with
   `All tests passed`).
5. Try it on a real repository with `--all` and look at the false positives before you raise a
   rule to ERROR.

Project-only rules go in the project (e.g. `.semgrep/` in the repo) and run with
`--extra-config .semgrep`.

## Licences

| Component | Licence | Use at DSC |
|---|---|---|
| Semgrep CE engine (`semgrep` on PyPI, `semgrep/semgrep` image) | LGPL-2.1 | Free for commercial use on private code. Used as an external tool, not linked into DSC products |
| DSC rules in this plugin | DSC's own | Shipped with the plugin |
| Semgrep Registry / `semgrep-rules` repo (`p/csharp`, `p/default`, `auto`) | Semgrep Rules License v1.0 | "only for your own internal business purposes", "does not allow you to distribute the rules, or to make them available to others as a service". Not vendored here: the plugin's source repository is public and mirrored, which is distribution. Not pulled at run time either: it needs the network and the registry. A developer may run `--config p/csharp` by hand on DSC's own code as internal use; the plugin and its agents do not |
| Semgrep Pro engine, Supply Chain, Secrets, AppSec Platform | Commercial | Not used |

## What this does not cover

- Cross-file / inter-procedural taint (a Pro feature): a value that becomes SQL two methods
  away is not traced. Data-flow problems remain a review item.
- Vulnerable NuGet/npm packages: use `dotnet list package --vulnerable --include-transitive`
  and `npm audit`.
- Build-time .NET analyzers: `skill-roslyn-analyzers`.
- Secrets outside settings files (in code, scripts, history): a dedicated secret scanner such
  as gitleaks.
