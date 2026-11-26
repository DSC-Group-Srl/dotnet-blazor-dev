#!/usr/bin/env python3
"""DSC Semgrep CE wrapper: local, offline security scan with the plugin's own rules.

Runs Semgrep Community Edition (``--oss-only``, ``--metrics=off``, no login, no registry)
with the rules in ``tools/semgrep/rules`` on the files changed against ``main`` (default)
or on the whole repository, and writes a SARIF file plus a short JSON summary.

Usage:
    semgrep_scan.py                       files changed vs main (committed, staged, unstaged, untracked)
    semgrep_scan.py --all                 the whole repository
    semgrep_scan.py --paths A B ...       only these files or folders
    semgrep_scan.py --base origin/develop compare with another ref
    semgrep_scan.py --out DIR             where semgrep.sarif / semgrep-summary.json go
                                          (default: <temp>/dsc-semgrep/<repo name>)
    semgrep_scan.py --json                print the summary JSON instead of the text report
    semgrep_scan.py --self-test           run ``semgrep --test`` on the plugin's rules

Triage file: ``<repo>/.dsc-semgrep-triage.json``::

    {"suppressions": [{"rule": "dsc-tenant-filter-missing", "path": "src/Server/LookupService.cs",
                       "match": "new SqlCommand(\\"dbo.usp_GetCountries\\", connection)",
                       "reason": "shared lookup table, no tenant data"}]}

Add ``"skip_rules": [{"rule": "dsc-tenant-filter-missing", "reason": "one database per tenant"}]``
to switch a rule off for the whole repository.

A suppression matches on rule id, repository-relative path and the trimmed text of the first
matched line, so it survives line moves but not a change to the flagged line.

Exit codes: 0 no unsuppressed ERROR finding; 1 at least one unsuppressed ERROR finding;
2 Semgrep missing or the scan itself failed.

Environment: ``DSC_SEMGREP_BIN`` overrides the semgrep executable.
"""

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RULES_DIR = os.path.join(HERE, "rules")
TRIAGE_FILE = ".dsc-semgrep-triage.json"
SCANNED_EXTENSIONS = (
    ".cs", ".razor", ".cshtml", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".json", ".sql",
)
EXCLUDES = (
    "bin", "obj", "node_modules", ".git", ".vs", "wwwroot/lib", "*.min.js", "*.g.cs",
    "*.designer.cs", "packages.lock.json", "package-lock.json",
)
MAX_CMDLINE_CHARS = 24000
SEVERITIES = ("ERROR", "WARNING", "INFO")

INSTALL_HINT = """Semgrep is not installed (or not on PATH).

Install Semgrep Community Edition (free, LGPL-2.1), no login needed:
  Windows (native, Python 3.10+):  python -m pip install --user semgrep
                                   or: pipx install semgrep
  macOS:                           brew install semgrep   or: pipx install semgrep
  Linux / WSL:                     pipx install semgrep   or: python3 -m pip install --user semgrep
  Docker (no local install):       docker run --rm -v "$PWD:/src" semgrep/semgrep semgrep scan ...

Then check: semgrep --version
If it is installed somewhere else, set DSC_SEMGREP_BIN to the executable.
Never run 'semgrep login' or 'semgrep ci' for this scan: it is meant to stay local."""


def run(cmd, cwd=None, env=None, check=False):
    """Run a command and return (returncode, stdout, stderr) as text."""
    proc = subprocess.run(
        cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )
    if check and proc.returncode != 0:
        raise RuntimeError("%s failed: %s" % (" ".join(cmd[:3]), proc.stderr.strip()))
    return proc.returncode, proc.stdout, proc.stderr


def find_semgrep():
    """Return the semgrep executable path, or None."""
    override = os.environ.get("DSC_SEMGREP_BIN")
    if override and os.path.isfile(override):
        return override
    return shutil.which("semgrep")


def semgrep_env(settings_file=None):
    """Environment that keeps Semgrep local: no metrics, no version check, no app token."""
    env = dict(os.environ)
    env["SEMGREP_SEND_METRICS"] = "off"
    env["SEMGREP_ENABLE_VERSION_CHECK"] = "0"
    env["PYTHONIOENCODING"] = "utf-8"
    env.pop("SEMGREP_APP_TOKEN", None)
    if settings_file:
        env["SEMGREP_SETTINGS_FILE"] = settings_file
    return env


def git_root(start):
    """Repository root for ``start``, or ``start`` itself outside git."""
    code, out, _ = run(["git", "-C", start, "rev-parse", "--show-toplevel"])
    return os.path.normpath(out.strip()) if code == 0 and out.strip() else os.path.abspath(start)


def resolve_base(repo, base):
    """First existing ref among the requested base and its usual fallbacks."""
    candidates = [base] if base else []
    candidates += ["main", "origin/main", "master", "origin/master"]
    for ref in candidates:
        code, _, _ = run(["git", "-C", repo, "rev-parse", "--verify", "--quiet", ref + "^{commit}"])
        if code == 0:
            return ref
    return None


def changed_files(repo, base):
    """Files changed since the merge base with ``base``, plus staged, unstaged and untracked ones."""
    code, mb, err = run(["git", "-C", repo, "merge-base", "HEAD", base])
    if code != 0:
        raise RuntimeError("git merge-base HEAD %s failed: %s" % (base, err.strip()))
    files = set()
    _, out, _ = run(["git", "-C", repo, "diff", "--name-only", "--diff-filter=ACMRT", mb.strip()])
    files.update(line.strip() for line in out.splitlines() if line.strip())
    _, out, _ = run(["git", "-C", repo, "ls-files", "--others", "--exclude-standard"])
    files.update(line.strip() for line in out.splitlines() if line.strip())
    return sorted(
        f for f in files
        if f.lower().endswith(SCANNED_EXTENSIONS) and os.path.isfile(os.path.join(repo, f))
    )


def norm_path(path, repo):
    """Repository-relative path with forward slashes."""
    full = path if os.path.isabs(path) else os.path.join(repo, path)
    try:
        rel = os.path.relpath(full, repo)
    except ValueError:
        rel = full
    return rel.replace("\\", "/")


def short_rule_id(check_id):
    """Semgrep prefixes local rule ids with the config path; keep only the rule id."""
    return check_id.rsplit(".", 1)[-1]


def line_text(repo, path, line, cache):
    """Trimmed text of one source line (Semgrep CE hides ``lines`` without a login)."""
    if path not in cache:
        try:
            with open(os.path.join(repo, path), encoding="utf-8", errors="replace") as fh:
                cache[path] = fh.read().splitlines()
        except OSError:
            cache[path] = []
    lines = cache[path]
    return re.sub(r"\s+", " ", lines[line - 1]).strip() if 0 < line <= len(lines) else ""


def load_triage(repo):
    """Suppressions and skipped rules from the repository's triage file."""
    path = os.path.join(repo, TRIAGE_FILE)
    if not os.path.isfile(path):
        return [], {}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    result = []
    for item in data.get("suppressions", []):
        result.append({
            "rule": item.get("rule", ""),
            "path": item.get("path", "").replace("\\", "/"),
            "match": re.sub(r"\s+", " ", item.get("match", "")).strip(),
            "reason": item.get("reason", ""),
        })
    skipped = {}
    for item in data.get("skip_rules", []):
        if isinstance(item, str):
            skipped[item] = "rule skipped for this repository"
        elif isinstance(item, dict) and item.get("rule"):
            skipped[item["rule"]] = item.get("reason") or "rule skipped for this repository"
    return result, skipped


def suppression_for(finding, suppressions, skipped):
    """The suppression that covers ``finding``, or None."""
    if finding["rule"] in skipped:
        return {"reason": skipped[finding["rule"]]}
    for sup in suppressions:
        if sup["rule"] == finding["rule"] and sup["path"] == finding["path"] and \
                sup["match"] and sup["match"] == finding["match"]:
            return sup
    return None


def mark_sarif(sarif_path, suppressed, repo):
    """Add SARIF ``suppressions`` to the results that the triage file covers."""
    if not suppressed or not os.path.isfile(sarif_path):
        return
    with open(sarif_path, encoding="utf-8") as fh:
        sarif = json.load(fh)
    for sarif_run in sarif.get("runs", []):
        for res in sarif_run.get("results", []):
            try:
                loc = res["locations"][0]["physicalLocation"]
                key = (
                    short_rule_id(res.get("ruleId", "")),
                    norm_path(loc["artifactLocation"]["uri"], repo),
                    loc["region"]["startLine"],
                )
            except (KeyError, IndexError):
                continue
            if key in suppressed:
                res["suppressions"] = [{"kind": "external", "justification": suppressed[key]}]
    with open(sarif_path, "w", encoding="utf-8") as fh:
        json.dump(sarif, fh, indent=2)


def build_command(semgrep, targets, out_dir, extra_configs):
    """The semgrep scan command line."""
    cmd = [
        semgrep, "scan", "--oss-only", "--metrics=off", "--disable-version-check", "--quiet",
        "--config", RULES_DIR,
        "--sarif-output=" + os.path.join(out_dir, "semgrep.sarif"),
        "--json-output=" + os.path.join(out_dir, "semgrep.json"),
    ]
    for cfg in extra_configs:
        cmd += ["--config", cfg]
    for pattern in EXCLUDES:
        cmd += ["--exclude", pattern]
    return cmd + targets


def semgrep_version(semgrep):
    """``semgrep --version`` output, or None when it cannot run."""
    try:
        code, out, _ = run([semgrep, "--version"], env=semgrep_env())
    except OSError:
        return None
    return out.strip().splitlines()[-1] if code == 0 and out.strip() else None


def self_test(semgrep):
    """Run ``semgrep --test`` on the rules folder; return the exit code."""
    tmp = tempfile.mkdtemp(prefix="dsc-semgrep-test-")
    settings = os.path.join(tmp, "settings.yml")
    with open(settings, "w", encoding="utf-8") as fh:
        fh.write("has_shown_metrics_notification: true\n"
                 "anonymous_user_id: 00000000-0000-0000-0000-000000000000\n")
    os.chmod(settings, stat.S_IREAD)
    try:
        proc = subprocess.run(
            [semgrep, "--test", "--metrics=off", "--disable-version-check", RULES_DIR],
            env=semgrep_env(settings), cwd=RULES_DIR, text=True, encoding="utf-8",
            errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        sys.stdout.buffer.write(proc.stdout.encode(sys.stdout.encoding or "utf-8", "replace"))
        sys.stdout.flush()
        return 0 if proc.returncode == 0 else 1
    finally:
        os.chmod(settings, stat.S_IREAD | stat.S_IWRITE)
        shutil.rmtree(tmp, ignore_errors=True)


def summarize(repo, out_dir, scope, base, targets, raw, triage, version):
    """Build the summary dict from Semgrep's JSON output."""
    cache = {}
    suppressions, skipped = triage
    target_set = None if targets is None else {norm_path(t, repo) for t in targets}
    findings, suppressed_list, suppressed_keys = [], [], {}
    for res in raw.get("results", []):
        path = norm_path(res["path"], repo)
        if target_set is not None and not any(
                path == t or path.startswith(t.rstrip("/") + "/") for t in target_set):
            continue
        line = res["start"]["line"]
        extra = res.get("extra", {})
        finding = {
            "rule": short_rule_id(res["check_id"]),
            "severity": extra.get("severity", "INFO").upper(),
            "path": path,
            "line": line,
            "message": " ".join(extra.get("message", "").split())[:300],
            "match": line_text(repo, path, line, cache),
        }
        sup = suppression_for(finding, suppressions, skipped)
        if sup:
            finding["suppressed_reason"] = sup["reason"]
            suppressed_list.append(finding)
            suppressed_keys[(finding["rule"], path, line)] = sup["reason"] or "triaged"
        else:
            findings.append(finding)
    findings.sort(key=lambda f: (SEVERITIES.index(f["severity"]) if f["severity"] in SEVERITIES
                                 else 9, f["path"], f["line"]))
    counts = {s: sum(1 for f in findings if f["severity"] == s) for s in SEVERITIES}
    errors = raw.get("errors", [])
    return {
        "tool": "semgrep-ce",
        "semgrep_version": version,
        "engine": "Semgrep Community Edition (--oss-only, --metrics=off)",
        "rules": norm_path(RULES_DIR, repo) if RULES_DIR.startswith(repo) else RULES_DIR,
        "scope": scope,
        "base": base,
        "files_requested": None if targets is None else len(targets),
        "files_scanned": len(raw.get("paths", {}).get("scanned", [])),
        "counts": counts,
        "suppressed": len(suppressed_list),
        "scan_errors": len(errors),
        "scan_error_samples": [
            " ".join(str(e.get("message", "")).split())[:200] for e in errors[:5]],
        "findings": findings,
        "suppressed_findings": suppressed_list,
        "sarif": os.path.join(out_dir, "semgrep.sarif"),
        "summary": os.path.join(out_dir, "semgrep-summary.json"),
        "triage_file": os.path.join(repo, TRIAGE_FILE),
    }, suppressed_keys


def print_report(summary):
    """Short human-readable report."""
    c = summary["counts"]
    print("Semgrep CE %s - scope: %s%s" % (
        summary["semgrep_version"] or "?", summary["scope"],
        (" vs " + summary["base"]) if summary["base"] else ""))
    print("Findings: %d ERROR, %d WARNING, %d INFO (%d suppressed, %d scan errors)" % (
        c["ERROR"], c["WARNING"], c["INFO"], summary["suppressed"], summary["scan_errors"]))
    for f in summary["findings"]:
        print("  [%s] %s:%d %s" % (f["severity"], f["path"], f["line"], f["rule"]))
    print("SARIF:   %s" % summary["sarif"])
    print("Summary: %s" % summary["summary"])


def write_empty(out_dir, scope, base, version, repo, as_json):
    """Summary for a scope with nothing to scan."""
    summary = {
        "tool": "semgrep-ce", "semgrep_version": version, "scope": scope, "base": base,
        "files_requested": 0, "files_scanned": 0,
        "counts": {s: 0 for s in SEVERITIES}, "suppressed": 0, "scan_errors": 0,
        "findings": [], "suppressed_findings": [], "sarif": None,
        "summary": os.path.join(out_dir, "semgrep-summary.json"),
        "triage_file": os.path.join(repo, TRIAGE_FILE),
        "note": "no changed file with a scanned extension",
    }
    with open(summary["summary"], "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
    if as_json:
        print(json.dumps(summary, indent=2))
    else:
        print("Semgrep CE: no changed file to scan (%s). Summary: %s" % (scope, summary["summary"]))
    return 0


def main(argv=None):
    """Entry point."""
    parser = argparse.ArgumentParser(description="DSC Semgrep CE scan (local rules, offline).")
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--all", action="store_true", help="scan the whole repository")
    scope.add_argument("--paths", nargs="+", help="scan only these files or folders")
    scope.add_argument("--self-test", action="store_true", help="semgrep --test on the rules")
    parser.add_argument("--base", default="main", help="ref to diff against (default main)")
    parser.add_argument("--repo", default=os.getcwd(), help="repository folder (default cwd)")
    parser.add_argument("--out", help="output folder (default <temp>/dsc-semgrep/<repo>)")
    parser.add_argument("--extra-config", action="append", default=[],
                        help="additional local rule file or folder (repeatable)")
    parser.add_argument("--json", action="store_true", help="print the summary as JSON")
    args = parser.parse_args(argv)

    semgrep = find_semgrep()
    version = semgrep_version(semgrep) if semgrep else None
    if not version:
        sys.stderr.write(INSTALL_HINT + "\n")
        return 2
    if args.self_test:
        return self_test(semgrep)

    repo = git_root(args.repo)
    out_dir = os.path.normpath(args.out or os.path.join(
        tempfile.gettempdir(), "dsc-semgrep", os.path.basename(repo) or "repo"))
    os.makedirs(out_dir, exist_ok=True)

    base = None
    if args.all:
        scope_name, targets, scan_targets = "repository", None, [repo]
    elif args.paths:
        scope_name = "paths"
        targets = [norm_path(os.path.abspath(p), repo) for p in args.paths]
        scan_targets = [os.path.join(repo, t) for t in targets]
    else:
        base = resolve_base(repo, args.base)
        if not base:
            sys.stderr.write("No base ref found (%s, main, origin/main, master). "
                             "Use --base REF or --all.\n" % args.base)
            return 2
        scope_name = "changed"
        targets = changed_files(repo, base)
        if not targets:
            return write_empty(out_dir, scope_name, base, version, repo, args.json)
        scan_targets = [os.path.join(repo, t) for t in targets]
        if sum(len(t) + 3 for t in scan_targets) > MAX_CMDLINE_CHARS:
            scan_targets = [repo]

    for name in ("semgrep.sarif", "semgrep.json"):
        try:
            os.remove(os.path.join(out_dir, name))
        except OSError:
            pass
    cmd = build_command(semgrep, scan_targets, out_dir, args.extra_config)
    code, out, err = run(cmd, cwd=repo, env=semgrep_env())
    json_path = os.path.join(out_dir, "semgrep.json")
    if not os.path.isfile(json_path):
        sys.stderr.write("Semgrep failed (exit %d):\n%s\n%s\n" % (code, out[-2000:], err[-4000:]))
        return 2
    with open(json_path, encoding="utf-8") as fh:
        raw = json.load(fh)

    summary, suppressed_keys = summarize(
        repo, out_dir, scope_name, base, targets, raw, load_triage(repo), version)
    mark_sarif(summary["sarif"], suppressed_keys, repo)
    summary["exit_code"] = 1 if summary["counts"]["ERROR"] else 0
    with open(summary["summary"], "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print_report(summary)
    return summary["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
