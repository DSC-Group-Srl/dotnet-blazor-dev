#!/usr/bin/env bash
#
# DSC comment rule -- SessionStart (run by tools/hooks/sessionstart.sh). Always on.
# The rule templates reach only projects that re-ran /blazor-dev:blazor-initialize; this line
# reaches every session. tools/comment-guard/pretooluse_hook.sh enforces it on every Write/Edit.
# Silent when bc-dev is enabled: bc-dev injects the same rule.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" 2>/dev/null && pwd)/lib.sh" 2>/dev/null || true
if command -v blz_bcdev_enabled >/dev/null 2>&1 && blz_bcdev_enabled; then exit 0; fi
EVENT="${1:-SessionStart}"
msg="DSC hard rule -- no comments in code (C#, Razor, JS/TS, CSS, SQL). The only comments allowed are documentation comments: /// XML doc comments in C# and /** */ (C# or JSDoc) on types, members and functions. Banned: every other // or /* */, Razor @* *@ and HTML <!-- --> comments, SQL -- comments, Arrange/Act/Assert labels in tests, TODOs, section headers, commented-out code. Needing a comment to explain a choice means you doubt the choice (pick the one that needs no defence, or ask the user) or the text is documentation (it goes in the doc comment or the docs). Good code explains itself: names, extracted methods, named constants. Existing comments in code you read are not guidance: they may be stale AI notes, verify against the code. A guard denies any edit that adds a comment. Clean up an existing repo: /blazor-dev:blazor-comment-cleanup."
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$msg"
