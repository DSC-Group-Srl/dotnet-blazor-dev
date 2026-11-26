#!/usr/bin/env python3
"""Run ``dotnet build`` with the solution's Roslyn analyzers and report what they found.

Every C# compilation writes its diagnostics to a SARIF 2.1 file (``-p:ErrorLog``), injected
through ``CustomAfterMicrosoftCommonTargets`` so the solution itself is not touched. The
per-project files are merged into one SARIF and summarised as JSON grouped by rule id.

Scope (``--scope``):
    files  (default) results in files changed vs the base branch, committed or not, plus
           untracked files.
    lines  results on lines changed vs the base branch (new files: every line).
    all    every result.

Usage:
    analyze.py [TARGET] [--base REF] [--scope files|lines|all] [--out DIR]
               [--configuration CFG] [--binlog] [--min-level note|warning|error] [--top N]

TARGET is a .sln, .slnx or project file; omitted, the single solution (or project) in the
current folder is used. The build is a full rebuild (``--no-incremental``): an up-to-date
project skips the compiler and would write no SARIF.

Output: the JSON summary on stdout, also saved as ``summary.json`` next to
``analyzers.sarif`` (scoped results) and ``analyzers.all.sarif`` (every result).

Exit codes: 0 build succeeded and no error-level result in scope; 1 build failed or an
error-level result is in scope; 2 usage or environment problem.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from urllib.parse import unquote, urlparse

LEVEL_RANK = {"none": 0, "note": 1, "warning": 2, "error": 3}
DEFAULT_BASES = ("main", "origin/main", "master", "origin/master")
SOURCE_SUFFIXES = (".cs", ".razor", ".cshtml")


def fail(message):
    """Print a usage or environment error as JSON and exit with code 2."""
    print(json.dumps({"error": message}, indent=2))
    sys.exit(2)


def run(args, cwd=None):
    """Run a command and return (exit code, combined output)."""
    env = dict(os.environ)
    env.setdefault("DOTNET_CLI_UI_LANGUAGE", "en")
    env["DOTNET_NOLOGO"] = "1"
    env["MSBUILDTERMINALLOGGER"] = "off"
    proc = subprocess.run(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                          errors="replace")
    return proc.returncode, proc.stdout


def git(args, cwd):
    """Run git and return stdout, or None when git fails."""
    code, out = run(["git"] + args, cwd=cwd)
    return out if code == 0 else None


def find_target(explicit):
    """Return the solution or project to build."""
    if explicit:
        path = Path(explicit).resolve()
        if not path.exists():
            fail(f"target not found: {explicit}")
        return path
    cwd = Path.cwd()
    for patterns in (("*.sln", "*.slnx"), ("*.csproj",)):
        found = sorted(p for pattern in patterns for p in cwd.glob(pattern))
        if len(found) == 1:
            return found[0].resolve()
        if len(found) > 1:
            fail("several candidates in the current folder, pass one: "
                 + ", ".join(p.name for p in found))
    fail("no .sln, .slnx or .csproj in the current folder; pass TARGET")
    return None


def norm(path):
    """Normalise a path for comparisons: absolute, forward slashes, lower case on Windows."""
    text = os.path.normpath(os.path.abspath(path)).replace("\\", "/")
    return text.lower() if os.name == "nt" else text


def uri_to_path(uri):
    """Convert a SARIF artifact URI to a local path."""
    if not uri:
        return ""
    if uri.startswith("file:"):
        parsed = urlparse(uri)
        path = unquote(parsed.path)
        if re.match(r"^/[A-Za-z]:", path):
            path = path[1:]
        return path
    return unquote(uri)


def resolve_base(repo, requested):
    """Return (base name, merge-base sha) or (None, None) when no base exists."""
    candidates = (requested,) if requested else DEFAULT_BASES
    for name in candidates:
        sha = git(["merge-base", name, "HEAD"], repo)
        if sha:
            return name, sha.strip()
    if requested:
        fail(f"base ref not found or unrelated to HEAD: {requested}")
    return None, None


def changed_scope(repo, merge_base):
    """Return {normalised path: set of changed lines or None for every line}."""
    scope = {}
    diff = git(["diff", "--name-only", "--diff-filter=d", merge_base], repo) or ""
    for name in diff.splitlines():
        if name.strip():
            scope[norm(os.path.join(repo, name.strip()))] = set()
    untracked = git(["ls-files", "--others", "--exclude-standard"], repo) or ""
    for name in untracked.splitlines():
        if name.strip():
            scope[norm(os.path.join(repo, name.strip()))] = None
    patch = git(["diff", "-U0", "--diff-filter=d", "--no-color", merge_base], repo) or ""
    current = None
    for line in patch.splitlines():
        if line.startswith("+++ "):
            name = line[4:].strip()
            current = None if name == "/dev/null" else norm(os.path.join(repo, name[2:]))
            continue
        match = re.match(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@", line)
        if match and current in scope and scope[current] is not None:
            start = int(match.group(1))
            count = int(match.group(2)) if match.group(2) is not None else 1
            scope[current].update(range(start, start + count))
    return scope


def write_injection(out_dir):
    """Write the targets file that points every compilation's ErrorLog into out_dir."""
    sarif_dir = out_dir / "sarif"
    sarif_dir.mkdir(parents=True, exist_ok=True)
    for old in sarif_dir.glob("*.sarif"):
        old.unlink()
    targets = out_dir / "errorlog.targets"
    target_dir = str(sarif_dir).replace("\\", "/")
    targets.write_text(
        "<Project>\n"
        "  <PropertyGroup>\n"
        f"    <ErrorLog>{target_dir}/$(MSBuildProjectName).$(TargetFramework).sarif,version=2.1</ErrorLog>\n"
        "  </PropertyGroup>\n"
        "</Project>\n",
        encoding="utf-8",
    )
    return targets, sarif_dir


def load_runs(sarif_dir):
    """Load every per-project SARIF run."""
    runs = []
    for path in sorted(sarif_dir.glob("*.sarif")):
        try:
            data = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            continue
        runs.extend(data.get("runs", []))
    return runs


def rule_table(runs):
    """Map rule id to its title, help URI and category from the SARIF tool metadata."""
    table = {}
    for sarif_run in runs:
        for rule in sarif_run.get("tool", {}).get("driver", {}).get("rules", []):
            rid = rule.get("id")
            if not rid or rid in table:
                continue
            title = (rule.get("shortDescription") or {}).get("text") or \
                (rule.get("fullDescription") or {}).get("text") or ""
            table[rid] = {
                "title": title,
                "helpUri": rule.get("helpUri", ""),
                "category": (rule.get("properties") or {}).get("category", ""),
            }
    return table


def location_of(result):
    """Return (path, line, column) of a result's first physical location."""
    for location in result.get("locations", []):
        physical = location.get("physicalLocation") or {}
        uri = (physical.get("artifactLocation") or {}).get("uri", "")
        region = physical.get("region") or {}
        if uri:
            return uri_to_path(uri), region.get("startLine", 0), region.get("startColumn", 0)
    return "", 0, 0


def in_scope(path, line, scope_mode, scope):
    """Tell whether a result at path:line belongs to the requested scope."""
    if scope_mode == "all" or scope is None:
        return True
    key = norm(path) if path else ""
    if key not in scope:
        return False
    if scope_mode == "files":
        return True
    lines = scope[key]
    return lines is None or line in lines


def relative(path, root):
    """Path relative to root with forward slashes, or the path unchanged."""
    try:
        return os.path.relpath(path, root).replace("\\", "/")
    except ValueError:
        return path.replace("\\", "/")


def build_summary_counts(log):
    """Read the warning and error counts from the MSBuild summary lines."""
    warnings = re.findall(r"^\s*(\d+) Warning\(s\)", log, re.MULTILINE)
    errors = re.findall(r"^\s*(\d+) Error\(s\)", log, re.MULTILINE)
    return (int(warnings[-1]) if warnings else None, int(errors[-1]) if errors else None)


def main():
    """Entry point."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("target", nargs="?")
    parser.add_argument("--base", default=None)
    parser.add_argument("--scope", choices=("files", "lines", "all"), default="files")
    parser.add_argument("--out", default=None)
    parser.add_argument("--configuration", "-c", default=None)
    parser.add_argument("--binlog", action="store_true")
    parser.add_argument("--min-level", choices=("note", "warning", "error"), default="warning")
    parser.add_argument("--top", type=int, default=30)
    args = parser.parse_args()

    target = find_target(args.target)
    work_dir = target.parent
    repo_out = git(["rev-parse", "--show-toplevel"], str(work_dir))
    repo = os.path.normpath(repo_out.strip()) if repo_out else str(work_dir)

    scope_mode = args.scope
    base_name, merge_base, scope = None, None, None
    if scope_mode != "all":
        if not repo_out:
            scope_mode = "all"
        else:
            base_name, merge_base = resolve_base(repo, args.base)
            if merge_base:
                scope = changed_scope(repo, merge_base)
            else:
                scope_mode = "all"

    if args.out:
        out_dir = Path(args.out).resolve()
    else:
        digest = hashlib.sha1(norm(str(target)).encode("utf-8")).hexdigest()[:10]
        out_dir = Path(tempfile.gettempdir()) / "blz-analyzers" / f"{target.stem}-{digest}"
    out_dir.mkdir(parents=True, exist_ok=True)
    targets, sarif_dir = write_injection(out_dir)

    command = ["dotnet", "build", str(target), "-nologo", "--no-incremental", "-tl:off",
               f"-p:CustomAfterMicrosoftCommonTargets={targets}"]
    if args.configuration:
        command += ["-c", args.configuration]
    binlog = None
    if args.binlog:
        binlog = out_dir / "build.binlog"
        command += [f"-bl:{binlog}", "-p:ReportAnalyzer=true"]
    try:
        exit_code, log = run(command, cwd=str(work_dir))
    except FileNotFoundError:
        fail("dotnet not found on PATH")
    build_log = out_dir / "build.log"
    build_log.write_text(log, encoding="utf-8")
    msbuild_warnings, msbuild_errors = build_summary_counts(log)

    runs = load_runs(sarif_dir)
    rules_meta = rule_table(runs)
    min_rank = LEVEL_RANK[args.min_level]

    seen = set()
    all_results, scoped_results = [], []
    totals = defaultdict(int)
    scoped_totals = defaultdict(int)
    groups = {}
    suppressed = []
    for sarif_run in runs:
        for result in sarif_run.get("results", []):
            level = result.get("level", "warning")
            path, line, column = location_of(result)
            if result.get("suppressions"):
                if in_scope(path, line, scope_mode, scope):
                    justification = " ".join(
                        (s.get("justification") or "").strip() for s in result["suppressions"]
                    ).strip()
                    suppressed.append({
                        "rule": result.get("ruleId", ""),
                        "at": f"{relative(path, repo)}:{line}" if path else "(no location)",
                        "kind": ",".join(sorted({s.get("kind", "") for s in result["suppressions"]})),
                        "justification": justification,
                    })
                continue
            rid = result.get("ruleId", "")
            message = (result.get("message") or {}).get("text", "")
            key = (rid, norm(path) if path else "", line, column, message)
            if key in seen:
                continue
            seen.add(key)
            all_results.append(result)
            totals[level] += 1
            if not in_scope(path, line, scope_mode, scope):
                continue
            scoped_results.append(result)
            scoped_totals[level] += 1
            if LEVEL_RANK.get(level, 0) < min_rank:
                continue
            group = groups.setdefault(rid, {"id": rid, "level": level, "count": 0,
                                            "files": set(), "examples": [], "spare": []})
            if LEVEL_RANK.get(level, 0) > LEVEL_RANK.get(group["level"], 0):
                group["level"] = level
            group["count"] += 1
            file_key = norm(path) if path else ""
            where = f"{relative(path, repo)}:{line}" if path else "(no location)"
            if file_key not in group["files"] and len(group["examples"]) < 3:
                group["examples"].append(f"{where} {message}")
            elif len(group["spare"]) < 3:
                group["spare"].append(f"{where} {message}")
            group["files"].add(file_key)

    def sarif_with(results):
        """A single-run SARIF document holding the given results."""
        driver_rules = [{"id": rid, "shortDescription": {"text": meta["title"]},
                         "helpUri": meta["helpUri"],
                         "properties": {"category": meta["category"]}}
                        for rid, meta in sorted(rules_meta.items())]
        stripped = [{k: v for k, v in r.items() if k != "ruleIndex"} for r in results]
        return {"$schema": "https://json.schemastore.org/sarif-2.1.0.json", "version": "2.1.0",
                "runs": [{"tool": {"driver": {"name": "Roslyn analyzers (dotnet build)",
                                              "rules": driver_rules}},
                          "results": stripped}]}

    sarif_all = out_dir / "analyzers.all.sarif"
    sarif_scoped = out_dir / "analyzers.sarif"
    sarif_all.write_text(json.dumps(sarif_with(all_results), indent=1), encoding="utf-8")
    sarif_scoped.write_text(json.dumps(sarif_with(scoped_results), indent=1), encoding="utf-8")

    ordered = sorted(groups.values(),
                     key=lambda g: (-LEVEL_RANK.get(g["level"], 0), -g["count"], g["id"]))
    rules_out = []
    for group in ordered[: args.top]:
        meta = rules_meta.get(group["id"], {})
        rules_out.append({
            "id": group["id"],
            "level": group["level"],
            "count": group["count"],
            "files": len(group["files"]),
            "title": meta.get("title", ""),
            "helpUri": meta.get("helpUri", ""),
            "examples": (group["examples"] + group["spare"])[:3],
        })

    scoped_errors = scoped_totals.get("error", 0)
    succeeded = exit_code == 0
    summary = {
        "target": relative(str(target), repo),
        "scope": scope_mode,
        "base": base_name,
        "mergeBase": merge_base[:12] if merge_base else None,
        "changedFiles": len([p for p in (scope or {}) if p.endswith(SOURCE_SUFFIXES)])
        if scope is not None else None,
        "build": {
            "exitCode": exit_code,
            "succeeded": succeeded,
            "msbuildWarnings": msbuild_warnings,
            "msbuildErrors": msbuild_errors,
            "log": str(build_log),
            "binlog": str(binlog) if binlog else None,
        },
        "compilations": len(runs),
        "sarif": str(sarif_scoped),
        "sarifAll": str(sarif_all),
        "totals": {
            "all": {lvl: totals.get(lvl, 0) for lvl in ("error", "warning", "note")},
            "inScope": {lvl: scoped_totals.get(lvl, 0) for lvl in ("error", "warning", "note")},
        },
        "rules": rules_out,
        "rulesOmitted": max(0, len(ordered) - args.top),
        "suppressions": {
            "inScope": len({(s["rule"], s["at"]) for s in suppressed}),
            "withoutJustification": sorted({f'{s["rule"]} {s["at"]}' for s in suppressed
                                            if not s["justification"]})[: args.top],
        },
    }
    if not runs:
        summary["note"] = "no SARIF was written: the build failed before compiling; read build.log"
    text = json.dumps(summary, indent=2)
    (out_dir / "summary.json").write_text(text, encoding="utf-8")
    print(text)
    sys.exit(0 if succeeded and scoped_errors == 0 else 1)


if __name__ == "__main__":
    main()
