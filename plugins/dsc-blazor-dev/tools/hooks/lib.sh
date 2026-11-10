#!/usr/bin/env bash
#
# Shared tests for blazor-dev hook scripts. Source it; it defines functions and prints nothing.
#
#   blz_is_dotnet_ws      a solution or project file at the session folder or one level down
#   blz_is_initialized    /blazor-dev:blazor-initialize ran here (rules marker at the session
#                         folder or an ancestor, up to the repository root)
#   blz_bcdev_enabled     the bc-dev plugin is enabled for this user. bc-dev ships the same
#                         generic nudges (git branch policy, VS Code workspace folders) for any
#                         repo, so with both plugins installed blazor-dev leaves those to it
#                         instead of saying everything twice.
#
# Test overrides: BLZ_ASSUME_DOTNET_WS, BLZ_ASSUME_INITIALIZED, BLZ_ASSUME_BCDEV = 1 | 0.

blz_is_dotnet_ws() {
  case "${BLZ_ASSUME_DOTNET_WS:-}" in 1) return 0 ;; 0) return 1 ;; esac
  local f
  for f in ./*.sln ./*.slnx ./*.csproj ./*.fsproj ./*/*.sln ./*/*.slnx ./*/*.csproj ./*/*.fsproj; do
    [ -f "$f" ] && return 0
  done
  return 1
}

blz_is_initialized() {
  case "${BLZ_ASSUME_INITIALIZED:-}" in 1) return 0 ;; 0) return 1 ;; esac
  local d p i
  d="$(pwd)"
  for i in 1 2 3 4 5 6; do
    [ -f "$d/.claude/rules/csharp-guidelines.md" ] && return 0
    [ -e "$d/.git" ] && return 1
    p="$(dirname "$d")"
    [ "$p" = "$d" ] && return 1
    d="$p"
  done
  return 1
}

blz_bcdev_enabled() {
  case "${BLZ_ASSUME_BCDEV:-}" in 1) return 0 ;; 0) return 1 ;; esac
  local cfg="${CLAUDE_CONFIG_DIR:-${HOME:-${USERPROFILE:-.}}/.claude}/settings.json"
  [ -f "$cfg" ] || return 1
  grep -qE '"bc-dev@[^"]*"[[:space:]]*:[[:space:]]*true' "$cfg" 2>/dev/null
}
