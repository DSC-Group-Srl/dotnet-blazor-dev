#!/usr/bin/env bash
#
# blazor-dev rules-injection precondition hook — detects whether
# /blazor-dev:blazor-initialize has already copied the always-on rule
# templates into this project's .claude/rules/ directory, and INJECTS a
# directive into the agent session via additionalContext. Same
# precondition-hook design as bc-dev's tools/rules/precondition_hook.sh.
#
# Wired from hooks/hooks.json on SessionStart.
set -euo pipefail

EVENT="${1:-SessionStart}"
MARKER=".claude/rules/csharp-guidelines.md"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-.}"

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$1"
}

if [ -f "$MARKER" ]; then
  emit "blazor-dev rules are INSTALLED at .claude/rules/ (this project has run /blazor-dev:blazor-initialize). Read the always-on rule files there (csharp-guidelines.md, csharp-code-style.md, blazor-component-conventions.md, azure-functions-conventions.md, csharp-testing.md) once per session and apply them; do not re-run init and do not re-read the same file twice this session."
else
  emit "blazor-dev rules are NOT installed (no ${MARKER}). Before writing, editing, or reviewing any C#/Razor code this session, tell the user that /blazor-dev:blazor-initialize has not been run for this project and offer to run it now - it copies the always-on rule templates from ${PLUGIN_ROOT}/rules-templates/ into .claude/rules/ so they persist and stay editable per project. Until the user responds, still apply the baselines yourself by reading the templates directly from ${PLUGIN_ROOT}/rules-templates/. NEVER block or fail the task for the missing install - this is a human-in-the-loop nudge, not a hard gate."
fi
