#!/usr/bin/env bash
#
# csharp-lsp-launch.sh — resolves the C# language server binary and execs it.
#
# Uses csharp-ls (a lightweight, MIT-licensed .NET global tool wrapping
# Roslyn) rather than Microsoft's own Microsoft.CodeAnalysis.LanguageServer
# package — that one ships through a preview NuGet feed tied to the C# Dev
# Kit's release cadence and isn't a stable standalone install target.
# csharp-ls gives real symbol/diagnostic grounding (hover, go-to-definition,
# find-references, workspace diagnostics) via `dotnet tool install --global
# csharp-ls`. Swap in Microsoft's server here if/when it ships a documented
# standalone distribution — see CLAUDE.md's tool-mapping table.
#
# Same "cmd /c bash" indirection as bc-dev's al-launch.sh — see that file's
# header comment for why a bare "csharp-ls" command can't be trusted to
# resolve on Windows through Claude Code's own PATH lookup.
set -euo pipefail

resolve_csharp_ls() {
  if command -v csharp-ls >/dev/null 2>&1; then
    command -v csharp-ls
    return 0
  fi

  local candidate="$HOME/.dotnet/tools/csharp-ls"
  [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  candidate="$HOME/.dotnet/tools/csharp-ls.exe"
  [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }

  return 1
}

LSP_BIN="$(resolve_csharp_ls)" || {
  echo "csharp-lsp-launch.sh: could not find 'csharp-ls' (checked PATH and ~/.dotnet/tools). Install it with: dotnet tool install --global csharp-ls" >&2
  exit 1
}

exec "$LSP_BIN" "$@"
