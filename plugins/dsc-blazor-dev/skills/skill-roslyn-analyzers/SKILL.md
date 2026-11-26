---
name: skill-roslyn-analyzers
description: "DSC's standard Roslyn analyzer set for Blazor/.NET solutions (SDK .NET analyzers in security mode, Meziantou.Analyzer, BannedApiAnalyzers with a stack-specific BannedSymbols.txt), how to switch it on, roll it out on a noisy codebase, read the results (SARIF summary script, binlog MCP) and suppress correctly. Use when setting up or auditing a solution's build-time security/quality checks, when a build shows CA/MA/RS0030/EF1002 diagnostics, when reviewing a diff for new analyzer warnings, or when asked about static analysis, SAST in the build, banned APIs or analyzer noise."
---

# Skill: Roslyn analyzers (build-time security and quality checks)

## Purpose

`dotnet build` reports security and quality problems in every Blazor/.NET solution DSC builds
or audits, with one curated, free, low-noise set. Every package is free for commercial use on
private code. Analyzers run inside the compiler: nothing is shipped with the app
(`GlobalPackageReference` is `PrivateAssets=all`).

## The set

| Analyzer | Licence | Why it is in |
|---|---|---|
| **Microsoft.CodeAnalysis.NetAnalyzers** (in the .NET SDK, no package) | MIT | `AnalysisModeSecurity=All` turns on every security rule: CA2100 (string-built SQL command text), CA3001–CA3012 (taint analysis: SQL, XSS, path, command, LDAP, open redirect injection), CA53xx (weak crypto, TLS, certificate checks), CA23xx (insecure deserialization). `AnalysisModeReliability=Recommended` adds reliability rules. |
| **ASP.NET Core and Blazor analyzers** (in the Web/Razor SDK, no package) | MIT | `BL0001`–`BL0010` (component parameters), `ASP0000`+ and `MVC1000`+ (hosting, routing, API misuse). Already on; nothing to add. |
| **Meziantou.Analyzer** | MIT | Async correctness without the noise of a style pack: MA0134 (unobserved task), MA0155 / MA0147 (async void, async lambda to a void delegate), MA0042 (blocking call inside async), MA0100 / MA0129 (task disposed before awaited), MA0009 (regex DoS). Blazor-aware rules (unknown component parameter). Very active (several releases a month). |
| **Microsoft.CodeAnalysis.BannedApiAnalyzers** | MIT | RS0030: the APIs this stack must not call, from `BannedSymbols.txt`. The only one here that also analyses the C# generated from `.razor` markup and `@code` blocks, so `(MarkupString)input` and `.Result` in a component are caught. |
| **EF Core analyzers** (ship with the EF Core package) | MIT | EF1001/EF1002 (interpolated SQL in `FromSqlRaw`/`ExecuteSqlRaw`). On whenever EF Core is referenced. |

### Evaluated and left out

| Candidate | Licence / status | Why it is out |
|---|---|---|
| SonarAnalyzer.CSharp 10.x | **Sonar Source-Available License v1** (since Nov 2024) | The licence's "Non-competitive Purpose" excludes "employing, using, or engaging artificial intelligence technology ... to ingest, interpret, analyze ... the data provided by the Program": AI agents reading its diagnostics is exactly our use. Version 9.32 (last LGPL) is frozen. Also heavy overlap and noise. |
| SecurityCodeScan.VS2019 | LGPL-3.0, last release 5.6.7 (Sep 2022), project unmaintained | Dead upstream. Forks exist (`AdaskoTheBeAsT.SecurityCodeScan.VS2022`, `Dotnetarium.Analyzers.SCS`, both LGPL, single maintainer). Their taint rules overlap CA3001–CA3012 and Semgrep. Optional for a security-critical project; not in the default set. |
| Roslynator.Analyzers | Apache-2.0, active | ~200 rules, mostly style and simplification that overlaps the IDE rules. No security value; churn for agents. Teams may add it per project. |
| Microsoft.VisualStudio.Threading.Analyzers | MIT, active | Its useful rules are covered: VSTHRD110 = MA0134, VSTHRD100 = MA0155, VSTHRD101 = MA0147, VSTHRD103 ≈ MA0042, VSTHRD002 = the `Task.Result`/`Wait` bans. Its messages point at `JoinableTaskFactory`, a Visual Studio extension API. Like Meziantou's async rules it skips generated code, so it adds nothing for `.razor`. |
| Third-party Razor analyzers | none maintained | The SDK's BL/ASP rules plus BannedApiAnalyzers on generated code cover Razor. |

## Switch it on in a solution

Templates: `${CLAUDE_PLUGIN_ROOT}/rules-templates/analyzers/`.

| File | Goes to | What it does |
|---|---|---|
| `Directory.Build.props` | solution root (merge into an existing one) | `AnalysisLevel=latest`, `AnalysisModeSecurity=All`, `AnalysisModeReliability=Recommended`, wires `dsc-analyzers.globalconfig` and `BannedSymbols.txt` into every project |
| `Directory.Packages.props` | solution root (merge the `GlobalPackageReference` lines) | Meziantou.Analyzer and BannedApiAnalyzers for every project, versions in one place |
| `dsc-analyzers.globalconfig` | solution root | Severities: the security and async rules are warnings, the noisy ones are off or suggestions |
| `BannedSymbols.txt` | solution root | The banned APIs for this stack |

```bash
cp "${CLAUDE_PLUGIN_ROOT}/rules-templates/analyzers/dsc-analyzers.globalconfig" .
cp "${CLAUDE_PLUGIN_ROOT}/rules-templates/analyzers/BannedSymbols.txt" .
```

Then merge `Directory.Build.props` and `Directory.Packages.props` by hand when the solution
already has them; copy them when it does not. Without central package management, put the
packages in `Directory.Build.props` instead:

```xml
<ItemGroup>
  <PackageReference Include="Meziantou.Analyzer" Version="3.0.342" PrivateAssets="all" IncludeAssets="runtime; build; native; contentfiles; analyzers" />
  <PackageReference Include="Microsoft.CodeAnalysis.BannedApiAnalyzers" Version="5.6.0" PrivateAssets="all" IncludeAssets="runtime; build; native; contentfiles; analyzers" />
</ItemGroup>
```

Notes:

- The file is named `dsc-analyzers.globalconfig`, not `.globalconfig`, so it never collides
  with one the project already has. It is attached with `<GlobalAnalyzerConfigFiles>`.
- `.editorconfig` entries override the global config for the paths they match: use them for a
  per-folder exception (tests, generated clients), never to switch a rule off solution-wide.
- A project-specific ban (for example `Activator.CreateInstance` in a trimmed WebAssembly
  `Client`) goes in that project's own `BannedSymbols.Client.txt`, added with
  `<AdditionalFiles Include="BannedSymbols.Client.txt" />` in its `.csproj`.
- Keep versions current: bump them in `Directory.Packages.props` with the rest of the packages.
  `Microsoft.CodeAnalysis.NetAnalyzers` follows the SDK; do not add it as a package.

## What `BannedSymbols.txt` bans, and the alternative

| Banned | Use instead |
|---|---|
| `Task<T>.Result`, `Task.Wait(...)`, `Task.WaitAll/WaitAny`, `GetAwaiter().GetResult()` | `await`, `Task.WhenAll`, `Task.WaitAsync(timeout)` |
| `Thread.Sleep` | `await Task.Delay` |
| `new MarkupString(string)`, `(MarkupString)string` | `@value` (encoded). Rendered HTML goes through one audited helper that sanitises or encodes and carries the suppression |
| `System.Data.SqlClient` (namespace) | `Microsoft.Data.SqlClient` |
| EF Core `FromSqlRaw`, `ExecuteSqlRaw(Async)`, `SqlQueryRaw` | `FromSql`, `ExecuteSql(Async)`, `SqlQuery` with an interpolated `FormattableString` (parameterised) |

`SqlCommand` itself is not banned: the stored-procedure pattern (`new SqlCommand("dbo.usp_X",
conn) { CommandType = StoredProcedure }`) is the house style. String-built command text is
caught by **CA2100** (and CA3001 when the string comes from request input).

## Where analyzers see Razor code

Verified on .NET SDK 10.0.404:

- **Markup and `@code` blocks in `.razor`**: only BannedApiAnalyzers and the SDK rules report
  there (for example RS0030 on `(MarkupString)Bio` and on `.Result` in `OnInitialized`, CA5394
  in the template's `Weather.razor`). Meziantou and other third-party rules skip generated code,
  so `async void` in an `@code` block is **not** reported.
- **Code-behind `.razor.cs`**: every analyzer sees it (MA0155 on `async void`, RS0030 on
  `GetAwaiter().GetResult()`).

So logic beyond a few lines goes in the `.razor.cs` partial class or a helper, not in `@code`.

## Roll out on an existing codebase

1. **Measure first.** Add the templates, then run the summary script on the whole solution
   (`--scope all`). Nothing fails yet: every rule is a warning or a suggestion.
2. **Hold the line on new code.** From day one, a change must not add a warning on the lines it
   touches: `analyze.py --scope lines` must show nothing new. Existing warnings are the baseline.
3. **Fix by rule, highest risk first**: RS0030 MarkupString, CA2100/CA3001, EF1002, CA53xx,
   then the async rules. One rule per commit or PR, so the review stays readable.
4. **Ratchet.** When a rule reaches zero, make it an error in `dsc-analyzers.globalconfig`
   (`dotnet_diagnostic.RS0030.severity = error`) so it never comes back. Do not set
   `TreatWarningsAsErrors` for the whole build until every rule is at zero.
5. A rule that is noisy for this codebase and has no security value: set it to `suggestion` or
   `none` in the global config, in its own commit that says why. Never delete the security rows.

## Run it and read the results

```bash
python "${CLAUDE_PLUGIN_ROOT}/tools/analyzers/analyze.py" [solution.sln] [--scope files|lines|all] [--base main] [--binlog] [-c Release] [--out DIR]
```

- Builds with `--no-incremental` (an up-to-date project skips the compiler and would write no
  SARIF) and injects `-p:ErrorLog=...` per compilation through
  `CustomAfterMicrosoftCommonTargets`, so the solution needs no change to produce SARIF.
- Default scope `files`: results in the files changed vs `main` (merge-base, committed or not,
  plus untracked files). `lines`: only on changed lines. `all`: everything.
- Prints a JSON summary (also `summary.json`): build status, totals in and out of scope, rules
  grouped by id with level, count, files, help link and up to three examples
  (`path:line message`), and the in-scope **suppressions without a justification**.
- Writes `analyzers.sarif` (scoped) and `analyzers.all.sarif` next to it, and `build.log`.
  `--binlog` adds `build.binlog` with `ReportAnalyzer=true`.
- Exit code 0: build succeeded and no error-level result in scope. 1: build failed or an
  error-level result is in scope. 2: usage or environment problem.
- `compilations` lower than the project count means a project failed before compiling: its
  dependants have no results. Read `build.log` or the binlog.

With a binlog, the **dotnet-msbuild-binlog** MCP answers the build-side questions:
`binlog_errors` / `binlog_warnings` (diagnostics with project and target),
`binlog_analyzer_summary` and `binlog_expensive_analyzers` (time per analyzer, needs
`ReportAnalyzer=true`, which `--binlog` sets). Plain `dotnet build` output also shows every
warning with its rule id and link.

## Suppress correctly

A suppression is a decision a reviewer must be able to check. Order of preference:

1. **Fix the code.** Most hits have a direct fix (the message names it).
2. **`[SuppressMessage]` on the narrowest member, with `Justification`.** DSC code carries no
   comments, so the justification is the only place the reason lives, and it reaches the SARIF
   (`suppressions[].justification`).

   ```csharp
   [SuppressMessage("ApiDesign", "RS0030:Do not use banned APIs", Justification = "Input is HTML-encoded before it becomes markup; only <br> is added.")]
   public static MarkupString FromText(string text)
   ```

3. **`#pragma warning disable RULE` / `restore RULE`** around the fewest lines, only where an
   attribute cannot go. It carries no justification: the script lists it under
   `suppressions.withoutJustification` and a reviewer must accept it explicitly.
4. **`.editorconfig` section for a path** (`[**/Generated/**.cs]`), for code the team does not
   own.

Never: a solution-wide `severity = none` for a security rule, `<NoWarn>` in a `.csproj`,
`#pragma warning disable` without a matching `restore`, or a suppression whose justification
restates the rule.

## Agents

- **blazor-developer / implement subagent**: after the build passes, run the script with
  `--scope lines`; fix every warning on lines you wrote. Report the in-scope totals.
- **blazor-review-subagent**: run it in the review worktree with `--base <wave base>`; a new
  security warning (RS0030 MarkupString/SQL, CA2100, CA3xxx, CA53xx, EF1002) is MAJOR, an
  unjustified suppression is MAJOR, other new warnings MINOR.
- **blazor-audit**: `--scope files` by default, `--scope all` for a full audit; findings cite
  the rule id and the `path:line` from the summary.
- A solution without the templates still builds with the SDK defaults: say so and offer to add
  them, do not add them unasked in an audit.
