# blazor-dev metrics on Azure Application Insights

One Application Insights resource receives the events the hooks emit from every developer
machine: `BlzPhase` (one per finished subagent: tokens, turns, seconds, tools, builds, reads,
review verdict), `BlzSession` (the whole session, subagents included, and tokens per changed
line of C#/Razor when a conductor run finished), `BlzRunStart` / `BlzRun` (blazor-conductor),
`BlzRead` and `BlzHook` (the guards), `BlzAlive` and `BlzHeartbeat` (plugin version per machine).

The sending code is `../appinsights.py`: the public ingestion contract over `urllib` and
`gzip`, no SDK to install. Send failures are logged and dropped; the local JSONL in
`$CLAUDE_PLUGIN_DATA/metrics/` always holds every record.

## Where the connection string comes from

Resolved in this order (`resolve_connection_string()`):

1. an explicit argument,
2. `$APPLICATIONINSIGHTS_CONNECTION_STRING`,
3. the file `../appinsights.connection` next to the scripts.

**The file is not in this repository, on purpose.** This source repo is public and a connection
string is a write key. The file is added in the private marketplace copy of the plugin
(`plugins/blazor-dev/tools/metrics/appinsights.connection`); the sync from this repo never
deletes files that exist only there. Without it, and without the environment variable, nothing
is sent anywhere and the local JSONL keeps working.

`BLZ_METRICS_APPINSIGHTS_DISABLE=1` turns the Application Insights lane off on one machine,
whatever is configured. `BLZ_METRICS_EXCLUDE=1` marks every event `exclude=true` (demos, dry
runs, self-tests). `BLZ_METRICS_ANONYMOUS=1` keeps only the hashed user id.

## What is stored

Counts, an enum verdict, and allowlisted identifiers (agent, skill and tool names, model id).
`project` is the solution file's name (else the repository's folder name) and `session` is eight
characters. **Never a message body, never source code, never a path inside a repository.** That
is enforced in `parse_subagent.py`, `usage.py` and `emit.py` and covered by their self-tests
(`bash ../test_metrics.sh`), because this data leaves the developer's machine. Only sessions
in a .NET workspace are recorded.

## Confirm it arrives

```kql
customEvents | where name startswith "Blz" | summarize count() by name, bin(timestamp, 1d)
```

Nothing showing up: look at `$CLAUDE_PLUGIN_DATA/metrics/capture.log`, which records every
send with its status (`appinsights: 200`, an `HTTP 4xx`, `unreachable`) and a missing python.
