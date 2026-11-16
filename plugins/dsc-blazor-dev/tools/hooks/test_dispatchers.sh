#!/usr/bin/env bash
# Self-test for the two hook dispatchers (issue #77):
#   pretooluse.sh   — a deny from each real guard still comes through, allows stay silent,
#                     the metrics heartbeat never prints, the first deny wins and exit 2 passes
#   sessionstart.sh — the merged additionalContext is ONE valid JSON payload, also when the
#                     scripts emit Windows paths, quotes, tabs and newlines; silent, garbage,
#                     crashing and timed-out scripts contribute nothing and do not block.
# Exits non-zero if any assertion fails. Needs python or node only to VALIDATE the JSON (the
# dispatchers themselves need neither); a missing read-guard python skips that one case.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="$(cd "$HERE/.." && pwd)"
PRE="$HERE/pretooluse.sh"
SS="$HERE/sessionstart.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export TMPDIR="$T"
# Nothing a test does may reach telemetry or the user's real state.
export BLZ_METRICS_EXCLUDE=1 BLZ_METRICS_APPINSIGHTS_DISABLE=1 BLZ_READ_GUARD_NO_METRICS=1
export CLAUDE_PLUGIN_DATA="$T/plugin-data" BLZ_LIVE_DIR="$T/live"
export BLZ_ASSUME_DOTNET_WS=1   # alive.sh only runs in a .NET workspace
unset BLZ_READ_GUARD_DISABLE BLZ_MAIN_THREAD_GUARD_DISABLE BLZ_FAST_PATH_DISABLE BLZ_SESSIONSTART_SCRIPTS

FAIL=0
ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1"; FAIL=1; }

PY=""
for c in python3 python py; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
NODE=""; command -v node >/dev/null 2>&1 && NODE=node

# winpath <posix path> -> a path python/node on this OS can open (C:/x/y on Git Bash).
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# json_get <json> <dotted.path> -> prints the value, exit 1 if invalid JSON.
json_get() {
  if [ -n "$PY" ]; then
    printf '%s' "$1" | "$PY" -c 'import json,sys
d=json.load(sys.stdin)
for k in sys.argv[1].split("."): d=d[k]
sys.stdout.buffer.write((d if isinstance(d,str) else json.dumps(d)).encode("utf-8"))' "$2"
  elif [ -n "$NODE" ]; then
    printf '%s' "$1" | "$NODE" -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{let d=JSON.parse(s);for(const k of process.argv[1].split("."))d=d[k];process.stdout.write(typeof d==="string"?d:JSON.stringify(d))})' "$2"
  else
    return 2
  fi
}

# pre <label> <expect DENY|ASK|SILENT> <json>  [expected substring of the reason]
pre() {
  local label="$1" want="$2" json="$3" needle="${4:-}" out rc dec
  out="$(printf '%s' "$json" | bash "$PRE")"; rc=$?
  if [ "$rc" -ne 0 ]; then bad "$label (exit $rc)"; return; fi
  if [ "$want" = SILENT ]; then
    [ -z "$out" ] && ok "$label" || bad "$label (expected silence, got: ${out:0:120})"
    return
  fi
  local wantdec; wantdec="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')"
  dec="$(json_get "$out" hookSpecificOutput.permissionDecision 2>/dev/null)"
  if [ "$dec" != "$wantdec" ]; then bad "$label (expected $wantdec, got: ${out:0:160})"; return; fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF "$needle"; then
    bad "$label (deny without '$needle')"; return
  fi
  [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && ok "$label" || bad "$label (more than one decision printed)"
}

echo "=== pretooluse.sh: real guards ==="
# The guards bind only in a project that ran /blazor-dev:blazor-initialize.
WS="$T/ws"; mkdir -p "$WS/.claude/rules" "$WS/src/App.Server"
: > "$WS/.claude/rules/csharp-guidelines.md"; : > "$WS/App.sln"
for i in $(seq 1 400); do echo "    // line $i"; done > "$WS/src/App.Server/BigService.cs"
WSW="$(winpath "$WS")"
cd "$WS" || exit 1
pre "conductor-guard deny (blazor-conductor writes .cs)" DENY \
  '{"session_id":"s1","agent_type":"blazor-conductor","agent_id":"x","tool_name":"Write","tool_input":{"file_path":"C:\\app\\src\\A.cs","content":"x"}}' \
  "blazor-conductor is an orchestrator"
pre "main-thread-guard deny (main thread writes .razor)" DENY \
  '{"session_id":"s2","tool_name":"Write","tool_input":{"file_path":"C:\\app\\src\\Pages\\A.razor","content":"x"}}' \
  "blazor-dev routing"
pre "main-thread-guard fast path stays silent" SILENT \
  '{"session_id":"s3","tool_name":"Edit","tool_input":{"file_path":"/a/b.cs","old_string":"// tpyo","new_string":"// typo"}}'
pre "subagent Edit of .cs is allowed" SILENT \
  '{"session_id":"s4","agent_type":"blazor-dev:blazor-developer","agent_id":"y","tool_name":"Edit","tool_input":{"file_path":"/a/b.cs","old_string":"a","new_string":"b"}}'
pre "main thread Write of .md is allowed" SILENT \
  '{"session_id":"s5","tool_name":"Write","tool_input":{"file_path":"/a/README.md","content":"x"}}'
pre "unguarded tool (Glob) is silent" SILENT \
  '{"session_id":"s6","tool_name":"Glob","tool_input":{"pattern":"**/*.cs"}}'
pre "ranged Read is silent" SILENT \
  '{"session_id":"s7","tool_name":"Read","tool_input":{"file_path":"/a/b.cs","offset":1,"limit":20}}'
pre "harmless shell command is silent" SILENT \
  '{"session_id":"s8","tool_name":"Bash","tool_input":{"command":"git status"}}'

# read-guard needs python and a large file in the initialized project.
if [ -n "$PY" ]; then
  pre "read-guard deny (whole Read of a 400-line .cs)" DENY \
    "{\"session_id\":\"s9\",\"cwd\":\"$WSW\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WSW/src/App.Server/BigService.cs\"}}" \
    "read-guard:"
  pre "read-guard denies the repeat and says a ranged read is enough to Edit" DENY \
    "{\"session_id\":\"s9\",\"cwd\":\"$WSW\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WSW/src/App.Server/BigService.cs\"}}" \
    "ranged Read of the lines you will change is enough"
  pre "read-guard lets a third identical attempt through" SILENT \
    "{\"session_id\":\"s9\",\"cwd\":\"$WSW\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WSW/src/App.Server/BigService.cs\"}}"
  pre "read-guard: a ranged Read is never denied" SILENT \
    "{\"session_id\":\"s9b\",\"cwd\":\"$WSW\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$WSW/src/App.Server/BigService.cs\",\"offset\":120,\"limit\":40}}"
  pre "read-guard deny via shell cat" DENY \
    "{\"session_id\":\"s10\",\"cwd\":\"$WSW\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cat src/App.Server/BigService.cs\"}}" \
    "don't dump it through the shell"
else
  echo "skip read-guard deny cases (no python: the read-guard fails open by design)"
fi

# The same calls in a project that never ran blazor-initialize: nothing is guarded.
PLAIN="$T/plain"; mkdir -p "$PLAIN/src"; : > "$PLAIN/Plain.sln"
cp "$WS/src/App.Server/BigService.cs" "$PLAIN/src/BigService.cs"
PLW="$(winpath "$PLAIN")"
cd "$PLAIN" || exit 1
pre "uninitialized project: main thread may write .cs" SILENT \
  '{"session_id":"p1","tool_name":"Write","tool_input":{"file_path":"C:\\x\\A.cs","content":"x"}}'
pre "uninitialized project: whole Read of a big .cs is allowed" SILENT \
  "{\"session_id\":\"p2\",\"cwd\":\"$PLW\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$PLW/src/BigService.cs\"}}"
cd "$WS" || exit 1

# alive.sh runs in the background and writes its throttle stamp; it must never print.
rm -rf "$T/live"
out="$(printf '%s' '{"session_id":"alive-1","tool_name":"Glob","tool_input":{}}' | bash "$PRE")"
for _ in $(seq 1 50); do [ -f "$T/live/.alive-alive-1" ] && break; sleep 0.1; done
[ -z "$out" ] && [ -f "$T/live/.alive-alive-1" ] && ok "alive.sh ran in the background, printed nothing" \
  || bad "alive.sh (output='${out:0:80}', stamp present: $([ -f "$T/live/.alive-alive-1" ] && echo yes || echo no))"

echo
echo "=== pretooluse.sh: dispatch contract (fake guards) ==="
F="$T/fake/tools"; mkdir -p "$F/hooks" "$F/metrics" "$F/read-guard" "$F/conductor-guard" "$F/main-thread-guard"
cp "$PRE" "$F/hooks/pretooluse.sh"
printf '#!/usr/bin/env bash\ncat >/dev/null; exit 0\n' > "$F/metrics/alive.sh"
cat > "$F/conductor-guard/pretooluse_hook.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"first"}}\n'
EOF
cat > "$F/main-thread-guard/pretooluse_hook.sh" <<EOF
#!/usr/bin/env bash
cat >/dev/null
touch "$T/second-ran"
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"second"}}\n'
EOF
cat > "$F/read-guard/pretooluse_hook.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo "blocked by exit-2 guard" >&2
exit 2
EOF
out="$(printf '%s' '{"tool_name":"Write","tool_input":{}}' | bash "$F/hooks/pretooluse.sh")"
reason="$(json_get "$out" hookSpecificOutput.permissionDecisionReason 2>/dev/null)"
[ "$reason" = first ] && [ ! -f "$T/second-ran" ] && ok "first deny wins, later guard not run" \
  || bad "first deny wins (reason='$reason', second ran: $([ -f "$T/second-ran" ] && echo yes || echo no))"
err="$(printf '%s' '{"tool_name":"Read","tool_input":{}}' | bash "$F/hooks/pretooluse.sh" 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && [ "$err" = "blocked by exit-2 guard" ] && ok "exit 2 + stderr from a guard passes through" \
  || bad "exit 2 passthrough (rc=$rc, stderr='$err')"
cat > "$F/conductor-guard/pretooluse_hook.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null; exit 1
EOF
rm -f "$T/second-ran"
out="$(printf '%s' '{"tool_name":"Edit","tool_input":{}}' | bash "$F/hooks/pretooluse.sh")"; rc=$?
reason="$(json_get "$out" hookSpecificOutput.permissionDecisionReason 2>/dev/null)"
[ "$rc" -eq 0 ] && [ "$reason" = second ] && ok "a crashing guard does not hide the next guard's deny" \
  || bad "crashing guard (rc=$rc, reason='$reason')"

echo
echo "=== sessionstart.sh: merge ==="
S="$T/ss"; mkdir -p "$S"
# emit() as in tools/routing/precondition_hook.sh (backslash/quote literals built with octal escapes).
export EMIT_INC="$S/emit.inc"
cat > "$EMIT_INC" <<'EOF'
emit() {
  local esc bs dq
  bs=$(printf '\134'); dq=$(printf '\042'); esc="$1"
  esc="${esc//"$bs"/"$bs$bs"}"; esc="${esc//"$dq"/"$bs$dq"}"
  esc="${esc//$'\r'/}"; esc="${esc//$'\n'/${bs}n}"; esc="${esc//$'\t'/${bs}t}"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
}
EOF
# printf format: Windows paths, a UNC path, double quotes, a newline and a tab.
export FMT='Analyzers in C:\\Users\\t.celano\\.alcops\\ and "quoted" \\\\server\\share.\nSecond line\tTabbed. arg=%s'
cat > "$S/paths.sh" <<'EOF'
#!/usr/bin/env bash
. "$EMIT_INC"; emit "$(printf "$FMT" "$1")"
EOF
cat > "$S/silent.sh"  <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$S/garbage.sh" <<'EOF'
#!/usr/bin/env bash
echo "not json at all"; echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
EOF
cat > "$S/crash.sh"   <<'EOF'
#!/usr/bin/env bash
echo '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"half'
exit 1
EOF
cat > "$S/slow.sh"    <<'EOF'
#!/usr/bin/env bash
sleep 8
. "$EMIT_INC"; emit "TOO LATE"
EOF
cat > "$S/plain.sh"   <<'EOF'
#!/usr/bin/env bash
. "$EMIT_INC"; emit "Routing nudge: it's fine -- 100% plain."
EOF
# shellcheck disable=SC2059 — FMT is the format on purpose
expected="$(printf "$FMT" SessionStart)"$'\n\n'"Routing nudge: it's fine -- 100% plain."

start=$(date +%s)
out="$(BLZ_SESSIONSTART_SCRIPTS="5 $S/paths.sh SessionStart
5 $S/silent.sh
5 $S/garbage.sh
5 $S/crash.sh
1 $S/slow.sh
5 $S/missing.sh
5 $S/plain.sh" bash "$SS" SessionStart </dev/null)"; rc=$?
elapsed=$(( $(date +%s) - start ))
[ "$rc" -eq 0 ] && ok "dispatcher exits 0" || bad "dispatcher exit $rc"
[ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && ok "exactly one payload line" || bad "payload lines: $(printf '%s\n' "$out" | wc -l)"
ctx="$(json_get "$out" hookSpecificOutput.additionalContext)"; vrc=$?
if [ "$vrc" -eq 2 ]; then
  echo "skip JSON validation (neither python nor node on PATH)"
elif [ "$vrc" -ne 0 ]; then
  bad "merged payload is not valid JSON: ${out:0:300}"
else
  ok "merged payload is valid JSON"
  ev="$(json_get "$out" hookSpecificOutput.hookEventName)"
  [ "$ev" = SessionStart ] && ok "hookEventName is SessionStart" || bad "hookEventName='$ev'"
  [ "$ctx" = "$expected" ] && ok "backslashes, quotes, tabs, newlines round-trip; contexts joined by a blank line, in order" \
    || { bad "merged text differs"; printf -- '--- got\n%s\n--- want\n%s\n' "$ctx" "$expected"; }
fi
printf '%s' "$out" | grep -q "TOO LATE" && bad "timed-out script leaked into the payload" || ok "timed-out script contributes nothing"
[ "$elapsed" -le 5 ] && ok "per-script timeout honored (${elapsed}s total, slow script capped at 1s)" \
  || bad "took ${elapsed}s - the 1s timeout was not enforced"

# Same timeout without coreutils `timeout`: the sleep/kill watchdog fallback.
start=$(date +%s)
out="$(BLZ_SESSIONSTART_NO_TIMEOUT=1 BLZ_SESSIONSTART_SCRIPTS="1 $S/slow.sh
5 $S/plain.sh" bash "$SS" SessionStart </dev/null)"
elapsed=$(( $(date +%s) - start ))
ctx="$(json_get "$out" hookSpecificOutput.additionalContext 2>/dev/null)"
[ "$elapsed" -le 6 ] && [ "$ctx" = "Routing nudge: it's fine -- 100% plain." ] \
  && ok "watchdog fallback (no timeout binary) enforces the cap (${elapsed}s)" \
  || bad "watchdog fallback (${elapsed}s, ctx='$ctx')"

out="$(BLZ_SESSIONSTART_SCRIPTS="5 $S/silent.sh" bash "$SS" SessionStart </dev/null)"
[ -z "$out" ] && ok "no context at all -> prints nothing" || bad "expected silence, got: $out"

# The real, read-only SessionStart scripts (rules + routing) in a .NET workspace, through the
# real merge. The installers (.NET tools, Node, python) are not run: they install software.
out="$(cd "$WS" && BLZ_SESSIONSTART_SCRIPTS="15 rules/precondition_hook.sh SessionStart
15 routing/precondition_hook.sh SessionStart" bash "$SS" SessionStart </dev/null)"
ctx="$(json_get "$out" hookSpecificOutput.additionalContext)"; vrc=$?
if [ "$vrc" -eq 2 ]; then echo "skip real-scripts JSON validation (no python/node)"
elif [ "$vrc" -eq 0 ] && printf '%s' "$ctx" | grep -q "blazor-dev routing" && printf '%s' "$ctx" | grep -qi "rules"; then
  ok "real rules + routing hooks merge into valid JSON"
else
  bad "real rules + routing merge: ${out:0:300}"
fi

echo
[ "$FAIL" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAIL"
