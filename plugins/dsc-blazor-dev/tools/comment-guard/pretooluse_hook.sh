#!/usr/bin/env bash
#
# DSC comment guard -- PreToolUse, routed by tools/hooks/pretooluse.sh for Write|Edit.
# Denies an edit that adds a comment other than a documentation comment to code
# (.cs, .razor, .cshtml, .js, .ts, .css, .sql, and .al / C/AL when bc-dev or nav-dev code is
# edited here). The rules and their exceptions live in comment_guard.py; self-test:
# python tools/comment-guard/test_comment_guard.py
# Kill switch: DSC_COMMENT_GUARD_DISABLE=1. No working python on PATH -> silent.
set -uo pipefail
[ "${DSC_COMMENT_GUARD_DISABLE:-}" = "1" ] && exit 0
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for c in python3 python py; do
  command -v "$c" >/dev/null 2>&1 || continue
  "$c" -c '' >/dev/null 2>&1 || continue
  exec "$c" "$here/comment_guard.py" hook
done
exit 0
