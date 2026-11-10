#!/usr/bin/env bash
#
# blazor-dev metrics — session heartbeat (PreToolUse, every tool; started in the background by
# tools/hooks/pretooluse.sh).
#
# Sends "BlzAlive" at most once every $BLZ_ALIVE_INTERVAL_S (default 120) per session, so
# the GITCloner team view can tell a session that is working from one that is gone, and see
# which agent is active. Sessions on this machine are also visible locally without it
# (`claude agents --json`); this exists for other machines and the team.
#
# The common case — throttled — costs one stat-free `cat` of a stamp file and no python. The
# send runs in the background so a tool call never waits on the network.
#
# NEVER BLOCKS, always exits 0 and prints nothing (PreToolUse output would be read as a
# decision).

set -uo pipefail
[ "${BLZ_METRICS_ALIVE_DISABLE:-}" = "1" ] && exit 0
# Only sessions in a .NET workspace: bc-dev and other plugins report their own.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" 2>/dev/null && pwd)/lib.sh" 2>/dev/null || true
if command -v blz_is_dotnet_ws >/dev/null 2>&1 && ! blz_is_dotnet_ws; then exit 0; fi

INPUT="$(cat 2>/dev/null || true)"
session=$(printf '%s' "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_-]*"' | head -1 | sed -E 's/.*"([A-Za-z0-9_-]+)"$/\1/')
[ -z "$session" ] && exit 0

live_dir="${BLZ_LIVE_DIR:-${HOME:-${USERPROFILE:-.}}/.claude/blz-plugin-data/live}"
stamp="$live_dir/.alive-$session"
interval="${BLZ_ALIVE_INTERVAL_S:-120}"
now=$(date +%s 2>/dev/null || echo 0)
last=$(cat "$stamp" 2>/dev/null || echo 0)
case "$last" in ''|*[!0-9]*) last=0 ;; esac
[ $((now - last)) -lt "$interval" ] && exit 0

mkdir -p "$live_dir" 2>/dev/null || true
printf '%s' "$now" > "$stamp" 2>/dev/null || true

tool=$(printf '%s' "$INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_.:-]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
agent=$(printf '%s' "$INPUT" | grep -o '"agent_type"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_.:-]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/')
cwd_json=$(printf '%s' "$INPUT" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)"$/\1/' | sed 's/\\\\/\\/g')

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo .)"
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then
    (
      [ -n "$cwd_json" ] && export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$cwd_json}"
      nohup "$c" "$script_dir/emit.py" BlzAlive ${agent:+agent=$agent} ${tool:+tool=$tool} \
        --session "$session" >/dev/null 2>&1 &
    )
    break
  fi
done
exit 0
