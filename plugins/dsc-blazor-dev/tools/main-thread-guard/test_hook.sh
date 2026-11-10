#!/usr/bin/env bash
# Self-test for pretooluse_hook.sh (deny path + fast path guardrails).
set -u
H="$(cd "$(dirname "$0")" && pwd)/pretooluse_hook.sh"
export TMPDIR="$(mktemp -d)"
P="$(mktemp -d)"; mkdir -p "$P/.claude/rules"; : > "$P/.claude/rules/csharp-guidelines.md"; cd "$P"
FAIL=0

# decision <expected ALLOW|DENY> <label> <session> <tool> <old> <new> [extra-json-field]
decision() {
  local want="$1" label="$2" sid="$3" tool="$4" old="$5" new="$6" extra="${7:-}" out got
  out="$(printf '{"session_id":"%s","tool_name":"%s","tool_input":{"file_path":"/a/Svc.cs","old_string":"%s","new_string":"%s"%s}}' \
    "$sid" "$tool" "$old" "$new" "$extra" | bash "$H")"
  if [ -n "$out" ]; then got=DENY; else got=ALLOW; fi
  if [ "$got" = "$want" ]; then echo "ok   $label"; else echo "FAIL $label (want $want, got $got)"; FAIL=1; fi
}

decision ALLOW "doc comment typo"    a Edit "    /// <summary>Custmer</summary>" "    /// <summary>Customer</summary>"
decision ALLOW "comment typo"        a Edit "// tpyo" "// typo"
decision ALLOW "second comment"      a Edit "// one" "// two"
decision DENY  "4th edit (budget 3)" a Edit "// a" "// b"
decision DENY  "logic change"        b Edit "await repo.DeleteAsync(id);" "await repo.UpdateAsync(id);"
decision DENY  "code smuggled after comment" b Edit "// a" "// b\\nrepo.Delete();"
decision DENY  "multi-line old"      b Edit "// a\\n// b" "// c"
decision DENY  "replace_all"         b Edit "// a" "// b" ',"replace_all":true'
decision DENY  "string literal"      b Edit "Title = \\\"a\\\";" "Title = \\\"b\\\";"
decision DENY  "Write tool"          b Write "// a" "// b"
decision DENY  "no session id"       "" Edit "// a" "// b"
decision DENY  "non-text property"   b Edit "Dense = true;" "Dense = false;"

out="$(printf '{"session_id":"c","agent_type":"blazor-dev:blazor-developer","tool_name":"Write","tool_input":{"file_path":"/a/Svc.cs"}}' | bash "$H")"
if [ -z "$out" ]; then echo "ok   subagent passes"; else echo "FAIL subagent passes"; FAIL=1; fi

cd /; mkdir -p "$P/other"; cd "$P/other"
out="$(printf '{"session_id":"d","tool_name":"Write","tool_input":{"file_path":"/a/Svc.cs"}}' | bash "$H")"
if [ -n "$out" ]; then echo "ok   nested folder of an initialized project is guarded"; else echo "FAIL nested folder guarded"; FAIL=1; fi
Q="$(mktemp -d)"; cd "$Q"
out="$(printf '{"session_id":"e","tool_name":"Write","tool_input":{"file_path":"/a/Svc.cs"}}' | bash "$H")"
if [ -z "$out" ]; then echo "ok   project without blazor-dev rules is left alone"; else echo "FAIL uninitialized project left alone"; FAIL=1; fi
cd /; rm -rf "$TMPDIR" "$P" "$Q"
exit "$FAIL"
