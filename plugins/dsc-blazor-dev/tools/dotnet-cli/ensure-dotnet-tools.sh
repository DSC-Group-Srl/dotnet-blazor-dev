#!/usr/bin/env bash
#
# .NET SDK / csharp-ls bootstrap hook — ensures `dotnet` is on PATH and the
# csharp-ls LSP global tool is installed, so csharp-lsp-launch.sh (invoked
# by .lsp.json) has something to find. Wired from hooks/hooks.json on
# SessionStart. Emits the Copilot hook output contract on stdout, same
# shape as bc-dev's tools/al-cli/ensure-al-tool.sh.
set -euo pipefail

EVENT="${1:-SessionStart}"

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$1"
}

if ! command -v dotnet >/dev/null 2>&1; then
  emit "The .NET SDK ('dotnet' command) is not on PATH. blazor-developer/blazor-conductor cannot build or test until it is installed — see https://dotnet.microsoft.com/download."
  exit 0
fi

if command -v csharp-ls >/dev/null 2>&1 || [ -x "$HOME/.dotnet/tools/csharp-ls" ] || [ -x "$HOME/.dotnet/tools/csharp-ls.exe" ]; then
  exit 0
fi

if dotnet tool install --global csharp-ls >/dev/null 2>&1; then
  emit "csharp-ls (the C# language server this plugin uses for symbol/diagnostic grounding) was missing and has been installed via 'dotnet tool install --global csharp-ls'. If the C# LSP server did not start this session, restart it so the refreshed PATH takes effect."
else
  emit "csharp-ls is not installed and automatic install via 'dotnet tool install --global csharp-ls' failed. Run that command manually — the C# LSP server will not start until it succeeds. Agents can still work from Grep/Glob/dotnet build output in the meantime."
fi
