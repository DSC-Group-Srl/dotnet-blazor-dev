#!/usr/bin/env bash
#
# blazor-dev agent-routing nudge — SessionStart hook. This plugin ships specialized
# agents (blazor-architect, blazor-developer, blazor-conductor, blazor-triage,
# blazor-audit, blazor-presales) but the main thread
# will happily start editing the code itself unless told otherwise. This hook
# structural gate like tools/conductor-guard/pretooluse_hook.sh for the main
# session, only convention in CLAUDE.md, which competes with the immediate
# pull of "just do the task". This hook re-injects the routing table and the
# ordered agentic loop every session so the main thread reaches for Task
# before Read/Write/Edit on AL work, even when the user did not @-mention an
# agent by name.
#
# Same Layer-2 precondition-hook design and output contract as
# tools/rules/precondition_hook.sh / tools/bcquality/precondition_hook.sh --
# SessionStart, additionalContext via hookSpecificOutput, never blocking.
set -euo pipefail

EVENT="${1:-SessionStart}"

emit() {
  # JSON-escape the message: backslashes, double quotes, CR/LF/TAB.
  # Windows paths interpolated into the text (CLAUDE_PLUGIN_ROOT, analyzer
  # folders) are why this cannot be a bare printf -- a C:\Users\... path
  # emits an invalid \U escape and the harness rejects the whole payload.
  # The backslash and quote literals are built with printf octal escapes so
  # this function contains no raw backslash that an editor or generator can
  # silently halve -- that halving is exactly how the original bug survived.
  local esc bs dq
  bs=$(printf '\134')   # backslash
  dq=$(printf '\042')   # double quote
  esc="$1"
  # NOTE: BOTH pattern and replacement MUST be quoted -- an unquoted $bs is
  # read as the pattern escape character (matches nothing), and an unquoted
  # replacement collapses $bs$bs back to a single backslash.
  esc="${esc//"$bs"/"$bs$bs"}"
  esc="${esc//"$dq"/"$bs$dq"}"
  esc="${esc//$'\r'/}"
  esc="${esc//$'\n'/${bs}n}"
  esc="${esc//$'\t'/${bs}t}"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$esc"
}

# Guard: only nudge in a .NET workspace. This plugin is often enabled next to bc-dev and
# nav-dev on the same machine, so a SessionStart hook that fires unconditionally would inject
# Blazor-agent routing advice into AL or C/AL sessions too.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" 2>/dev/null && pwd)/lib.sh" 2>/dev/null || true
if command -v blz_is_dotnet_ws >/dev/null 2>&1 && ! blz_is_dotnet_ws; then
  exit 0
fi

msg="blazor-dev routing -- for Blazor/.NET work here, launch the matching agent via Task instead of working in the main thread (infer intent; users rarely name one): design/layering/data access/integration -> blazor-architect. Implement/fix code you understand -> blazor-developer. Planned multi-step feature -> blazor-conductor (when it runs as a background Task, check on it and relay its 'phase N/M' progress to the user unprompted). Bug or incident starting from a symptom -> blazor-triage (diagnosis), then blazor-developer (fix). Independent audit -> blazor-audit. Estimate or proposal -> blazor-presales. Tell the user which agent you chose and why. Present the LOW/MEDIUM/HIGH complexity assessment and wait for confirmation; for HIGH also ask whether to switch the session to Opus, and never switch models yourself. Requirement documents go in requirements/{req}/ ({req}.spec.md, {req}.architecture.md, {req}.test-plan.md), never into a claude.ai artifact or a flat file. When you delegate, do not forbid the agent from running dotnet build or dotnet test; your own final verification comes in addition to its tests, not instead of them. Git: the blazor-dev git block (or bc-dev's ALDC git block when that plugin is installed) says whether this repo uses pull requests; never create a branch without asking, and ask once before pushing or opening a PR. Questions from an agent (blazor-architect, blazor-conductor, blazor-triage, a spec's open questions): ask them with the AskUserQuestion tool, at most 4 per call, most blocking first, the rest in a second call. Plain words: each question says what the choice changes for the application or its users; each option is a short label plus a one-line trade-off, your recommendation first. A plan label (phase, section, FR, option letter) never stands alone: if it helps traceability it goes in parentheses after the meaning. Drop questions the spec, the code or an earlier answer already settles, then hand the answers back to the agent."
if command -v blz_is_initialized >/dev/null 2>&1 && blz_is_initialized; then
  msg="$msg Routing is BINDING in this project (it ran /blazor-dev:blazor-initialize): a PreToolUse guard denies Write/Edit of .cs, .razor and .cshtml files from the main thread, so never write that code yourself; only a single-line // comment fix passes. A whole-file Read of a source file over 350 lines is denied too: ask the blazor-file-reader agent (Task) for the exact line ranges, then Read with offset/limit. Editing never needs a full read; a ranged Read of the lines you will change is enough."
fi
emit "$msg"
