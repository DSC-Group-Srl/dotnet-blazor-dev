---
description: >
  Report the blazor-dev efficiency metrics collected on this machine: tokens, time, turns,
  builds and estimated cost per agent and per session, tokens per changed line of C#/Razor,
  and review verdicts. Use when you want to know what a feature cost, which agent is the
  expensive one, or whether whole-file reads are creeping back.
allowed-tools: Bash, Read
argument-hint: "optional: --days 30 · --project <name> · --json"
---

# blazor-dev Metrics

Aggregate and interpret what the `SubagentStop` and `SessionEnd` hooks have been collecting.

## Run it

```bash
"${CLAUDE_PLUGIN_ROOT}/tools/metrics/report.sh" $ARGUMENTS
```

Pass `--days 30` to window the report, `--project <name>` to narrow to one project, `--json`
for the raw aggregate.

## Then interpret

Render what the script prints, and add the judgement it cannot make:

1. **Read the EFFICIENCY block first** — it is what this plugin measures. Per agent: average
   tokens, output tokens, seconds, turns, builds, whole-file-read share and estimated USD
   (from `tools/metrics/prices.json`). Per session (SessionEnd, subagents included): total
   tokens, minutes and **tokens per changed line of C#/Razor**, the headline KPI.
2. **Call out**: a whole-read share above ~40% (the read-guard or `blazor-file-reader` is not
   being used), builds per implementer above ~4 (guessing instead of reading the compiler
   output or the binlog), and any version-over-version regression in tokens per changed line.
3. **The quality block is mostly empty here, and that is expected.** It was built for bc-dev's
   BCQuality accounting, which blazor-dev does not have. What does apply: the review verdict
   mix (`APPROVED` / `NEEDS_REVISION` / `FAILED`) per phase. Do not read the BCQuality ratios.
4. **Note thin data honestly.** Under about five sessions these averages are noise. Say so
   rather than reading a trend into four data points.

## Where the data lives

- `$CLAUDE_PLUGIN_DATA/metrics/blz-metrics.jsonl` — always written, survives plugin updates.
- `<project>/.github/metrics/blz-metrics.jsonl` — only when that directory exists. Create it
  to version metrics with the project.
- **Azure Application Insights** — on when a connection string is present: the file
  `tools/metrics/appinsights.connection` (added by the marketplace distribution, not part of the
  public source repo), or `$APPLICATIONINSIGHTS_CONNECTION_STRING`, which overrides it.
  `BLZ_METRICS_APPINSIGHTS_DISABLE=1` turns it off per machine. Events: `BlzPhase` (one per
  subagent, with `u*` token/time measurements), `BlzSession`, `BlzRunStart` / `BlzRun`
  (blazor-conductor), `BlzRead`, `BlzHook`, `BlzAlive`, `BlzHeartbeat`. That is the estate-wide
  view: this command reports the local machine.

Only sessions in a .NET workspace (a solution or project file) are recorded. Records hold
counts, verdicts and allowlisted identifiers (agent, skill and tool names, model ids, a salted
hash of the solution name). **No message bodies, no source code, no repo paths** — enforced
in the parser, not merely intended, because these files travel.

If nothing has been collected, the script says where to look; the usual cause is no python
interpreter on `PATH`, which the capture hook records in `metrics/capture.log` rather than
failing the session.
