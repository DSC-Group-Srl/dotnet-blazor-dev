#!/usr/bin/env bash
#
# Structural backstop for blazor-conductor's "orchestrator only" rule: a
# prompt-level instruction can drift under long context, so this PreToolUse
# hook denies Write/Edit on any *.cs/*.razor file when the active agent is
# blazor-conductor, forcing it to delegate implementation to
# blazor-implement-subagent instead of writing/editing code itself. Every
# other agent (blazor-developer, blazor-implement-subagent, ...) is
# unaffected. Mirrors bc-dev's tools/conductor-guard/pretooluse_hook.sh.
#
# Wired from hooks/hooks.json on PreToolUse (matcher: Write|Edit).
set -euo pipefail

INPUT="$(cat)"

extract_str_field() {
  printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
    | sed -E 's/^"[^"]+"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
}

AGENT_TYPE="$(extract_str_field "$INPUT" "agent_type")"
TOOL_NAME="$(extract_str_field "$INPUT" "tool_name")"
FILE_PATH="$(extract_str_field "$INPUT" "file_path")"

if [ "$AGENT_TYPE" != "blazor-conductor" ]; then
  exit 0
fi

case "$TOOL_NAME" in
  Write|Edit) ;;
  *) exit 0 ;;
esac

LOWER_PATH="$(printf '%s' "$FILE_PATH" | tr '[:upper:]' '[:lower:]')"
case "$LOWER_PATH" in
  *.cs|*.razor|*.cshtml) ;;
  *) exit 0 ;;
esac

JSON_SAFE_PATH="$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')"

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"blazor-conductor is an orchestrator and must not write or edit C#/Razor source itself (path: %s). Delegate this change to blazor-implement-subagent via the Task tool instead."}}\n' "$JSON_SAFE_PATH"
