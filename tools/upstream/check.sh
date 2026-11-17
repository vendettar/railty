#!/usr/bin/env bash
# Read-only upstream inspection & ledger verification tool for Railty.
# Safely fetches ghostty & sidegeist (with --no-tags), reports HEAD/merge-base
# relationships, validates docs/upstream/state.json and ledger.jsonl, lists
# unreviewed commits, and detects potential patch-id duplicates.
# It also cross-checks state.json against the real Git HEAD, the newest release
# tag, and the ledger's railtiy_commit ancestry, warning when they drift.
# Never modifies main, never merges, and never cherry-picks.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DO_FETCH=true
CHECK_PATCH_ID=false

for arg in "$@"; do
  case "$arg" in
    --no-fetch) DO_FETCH=false ;;
    --patch-id) CHECK_PATCH_ID=true ;;
    -h|--help)
      cat <<'EOF'
Usage: tools/upstream/check.sh [options]

Options:
  --no-fetch   Skip git fetch; inspect locally cached remote-tracking refs
  --patch-id   Also run git cherry / patch-id comparison against HEAD (slower)
  -h, --help   Show this help message
EOF
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

ensure_remote() {
  local name="$1" expected_url="$2"
  if git remote get-url "$name" >/dev/null 2>&1; then
    local actual_url
    actual_url="$(git remote get-url "$name")"
    if [[ "$actual_url" != "$expected_url" ]]; then
      printf 'WARN: remote %s points to %s (expected %s)\n' "$name" "$actual_url" "$expected_url" >&2
    fi
  else
    printf 'Adding missing remote %s -> %s\n' "$name" "$expected_url"
    git remote add "$name" "$expected_url"
  fi
}

ensure_remote ghostty "https://github.com/ghostty-org/ghostty.git"
ensure_remote sidegeist "https://github.com/tomreinert/ghostty-sidegeist.git"

if [[ "$DO_FETCH" == "true" ]]; then
  echo "== Fetching remotes (--no-tags to avoid tip/release tag collisions) =="
  git fetch --no-tags origin +refs/heads/main:refs/remotes/origin/main
  git fetch --no-tags ghostty +refs/heads/main:refs/remotes/ghostty/main
  git fetch --no-tags sidegeist +refs/heads/main:refs/remotes/sidegeist/main
  echo
fi

export RAILTY_CHECK_PATCH_ID="$CHECK_PATCH_ID"
export RAILTY_CHECK_FETCH="$DO_FETCH"

python3 - <<'PY'
import json
import os
import re
import subprocess
import sys
from collections import Counter

sys.path.insert(0, "tools/upstream")
import defer_queue

STATE_PATH = "docs/upstream/state.json"
LEDGER_PATH = "docs/upstream/ledger.jsonl"
DEFER_PATH = "docs/upstream/defer-queue.json"

VALID_DECISIONS = {"INCLUDE", "DEFER", "SKIP", "ALREADY_INCLUDED", "NEEDS_REVIEW"}
VALID_CATEGORIES = {
    "Security",
    "Critical Bug",
    "macOS Bug",
    "Performance",
    "New Feature",
    "Build / Toolchain",
    "Refactor",
    "Tests",
    "Docs / CI",
    "Platform-specific",
}
REQUIRED_FIELDS = {
    "source",
    "sha",
    "subject",
    "category",
    "decision",
    "reason",
    "impact",
    "dependencies",
    "integration",
    "railty_commit",
    "validation",
}

def git(*args, check=True):
    res = subprocess.run(["git", *args], text=True, capture_output=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {res.stderr.strip()}")
    return res.stdout.strip(), res.returncode

def is_ancestor(anc, desc):
    _, rc = git("merge-base", "--is-ancestor", anc, desc, check=False)
    return rc == 0

head_sha, _ = git("rev-parse", "HEAD")
head_subj, _ = git("show", "-s", "--format=%ci | %s", head_sha)
sg_sha, _ = git("rev-parse", "sidegeist/main")
sg_subj, _ = git("show", "-s", "--format=%ci | %s", sg_sha)
gh_sha, _ = git("rev-parse", "ghostty/main")
gh_subj, _ = git("show", "-s", "--format=%ci | %s", gh_sha)

mb_sg, _ = git("merge-base", "HEAD", "sidegeist/main")
mb_gh, _ = git("merge-base", "HEAD", "ghostty/main")
mb_sg_gh, _ = git("merge-base", "sidegeist/main", "ghostty/main")

sg_ahead, _ = git("rev-list", "--count", "HEAD..sidegeist/main")
railty_ahead_sg, _ = git("rev-list", "--count", "sidegeist/main..HEAD")
gh_ahead_mb, _ = git("rev-list", "--count", f"{mb_gh}..ghostty/main")

print("== Repository HEADs & Merge Bases ==")
print(f"Railty (HEAD):         {head_sha} ({head_subj})")
print(f"Sidegeist (main):      {sg_sha} ({sg_subj})")
print(f"Ghostty (main):        {gh_sha} ({gh_subj})")
print(f"merge-base(HEAD, sg):  {mb_sg} (sidegeist ahead: {sg_ahead}, railty ahead: {railty_ahead_sg})")
print(f"merge-base(HEAD, gh):  {mb_gh} (ghostty ahead of merge-base: {gh_ahead_mb})")
print(f"merge-base(sg, gh):    {mb_sg_gh}")
print()

if not os.path.exists(STATE_PATH):
    print(f"ERROR: missing {STATE_PATH}", file=sys.stderr)
    sys.exit(1)
if not os.path.exists(LEDGER_PATH):
    print(f"ERROR: missing {LEDGER_PATH}", file=sys.stderr)
    sys.exit(1)
if not os.path.exists(DEFER_PATH):
    print(f"ERROR: missing {DEFER_PATH}", file=sys.stderr)
    sys.exit(1)

with open(STATE_PATH, encoding="utf-8") as f:
    state = json.load(f)

rows = []
seen_keys = set()
dup_keys = []
errors = []

with open(LEDGER_PATH, encoding="utf-8") as f:
    for idx, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            errors.append(f"Line {idx}: invalid JSON ({e})")
            continue
        missing = REQUIRED_FIELDS - set(obj.keys())
        if missing:
            errors.append(f"Line {idx} ({obj.get('sha','?')[:10]}): missing fields {sorted(missing)}")
        key = (obj.get("source"), obj.get("sha"))
        if key in seen_keys:
            dup_keys.append(key)
        seen_keys.add(key)
        if obj.get("decision") not in VALID_DECISIONS:
            errors.append(f"Line {idx}: invalid decision {obj.get('decision')}")
        if obj.get("category") not in VALID_CATEGORIES:
            errors.append(f"Line {idx}: invalid category {obj.get('category')}")
        if not obj.get("reason"):
            errors.append(f"Line {idx}: empty reason")
        rows.append(obj)

print("== Ledger Integrity & Summary ==")
print(f"Entries: {len(rows)} | Duplicates: {len(dup_keys)} | Schema errors: {len(errors)}")
if dup_keys:
    print("Duplicate keys:", dup_keys[:10], file=sys.stderr)
if errors:
    for err in errors[:20]:
        print("ERROR:", err, file=sys.stderr)
    sys.exit(1)

by_source = Counter(r["source"] for r in rows)
by_decision = Counter(r["decision"] for r in rows)
by_integration = Counter(r["integration"] for r in rows)
print(f"By source:      {dict(by_source)}")
print(f"By decision:    {dict(by_decision)}")
print(f"By integration: {dict(by_integration)}")
print()

# --- DEFER review queue -------------------------------------------------------
with open(DEFER_PATH, encoding="utf-8") as f:
    defer_doc = json.load(f)

defer_errors, defer_warnings = defer_queue.validate_queue(defer_doc, rows)
summary = defer_queue.queue_summary(defer_doc)

print("== DEFER Review Queue ==")
print(f"Entries: {summary['total']} | Schema errors: {len(defer_errors)}")
print(f"By priority: {dict(sorted(summary['by_priority'].items()))}")
print("By group:")
for group, count in sorted(summary["by_group"].items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"  {count:3d}  {group}")
if defer_errors:
    for err in defer_errors[:20]:
        print("ERROR:", err, file=sys.stderr)
    sys.exit(1)
print()

# --- State consistency checks -------------------------------------------------
# state.json is only useful if it matches reality. These checks are warnings,
# not hard failures: the tool stays read-only and never edits the files.

warnings = list(defer_warnings)
state_railty = state.get("railty", {})
state_head = state_railty.get("head_sha")
state_tag = state_railty.get("latest_release_tag")

print("== State Consistency ==")
ancestor = bool(state_head) and is_ancestor(state_head, "HEAD")
changed_files = []
if state_head and state_head != head_sha and ancestor:
    out, _ = git("diff", "--name-only", f"{state_head}..HEAD")
    changed_files = out.splitlines()
level, message = defer_queue.state_head_status(
    state_head,
    head_sha,
    ancestor,
    changed_files,
)
if level == "warn":
    warnings.append(message)
else:
    print(message)

# Newest Railty release tag. Upstream Ghostty/Sidegeist tags (v1.4.0, tip, ...)
# are shared into this repository, so local tags are not reliable here: only
# origin's own tags identify Railty releases.
release_tags = None
out, rc = git("ls-remote", "--tags", "origin", check=False)
if rc == 0:
    release_tags = []
    for line in out.splitlines():
        ref = line.split("\t")[-1]
        if not ref.startswith("refs/tags/") or ref.endswith("^{}"):
            continue
        name = ref[len("refs/tags/"):]
        if defer_queue.semver(name):
            release_tags.append(name)

level, message = defer_queue.release_tag_status(state_tag, release_tags)
if level == "warn":
    warnings.append(message)
else:
    print(message)

if release_tags:
    newest_tag = max(
        (tag for tag in release_tags if defer_queue.semver(tag)),
        key=defer_queue.semver,
        default=None,
    )
    if newest_tag:
        tag_commit, rc = git("rev-parse", f"{newest_tag}^{{commit}}", check=False)
        if rc != 0:
            warnings.append(f"release tag {newest_tag} cannot be resolved to a commit")
        elif not is_ancestor(tag_commit, "HEAD"):
            warnings.append(f"release tag {newest_tag} ({tag_commit[:10]}) is not an ancestor of HEAD")

# Every integrated/adapted INCLUDE entry must point at a commit in HEAD history.
integrated_rows = [
    r for r in rows
    if r["decision"] == "INCLUDE" and r["integration"] in ("integrated", "adapted")
]
missing_refs = [r["sha"][:10] for r in integrated_rows if not r.get("railty_commit")]
dangling_refs = []
for r in integrated_rows:
    commit = r.get("railty_commit")
    if not commit:
        continue
    _, rc = git("cat-file", "-e", f"{commit}^{{commit}}", check=False)
    if rc != 0:
        dangling_refs.append((r["sha"][:10], commit[:10], "missing"))
    elif not is_ancestor(commit, "HEAD"):
        dangling_refs.append((r["sha"][:10], commit[:10], "not-an-ancestor"))
if missing_refs:
    warnings.append(f"{len(missing_refs)} integrated INCLUDE entr(ies) lack railty_commit: {missing_refs[:5]}")
if dangling_refs:
    warnings.append(f"{len(dangling_refs)} integrated INCLUDE railty_commit(s) are not in HEAD history: {dangling_refs[:5]}")
if not missing_refs and not dangling_refs:
    print(f"ledger railty_commit ancestry OK ({len(integrated_rows)} integrated/adapted entries)")

if warnings:
    print(f"WARNINGS: {len(warnings)}")
    for w in warnings:
        print(f"  WARN: {w}")
else:
    print("All state consistency checks passed.")
print()

# --- DEFER re-assessment gates ------------------------------------------------
ctx = {
    "zig_version": state_railty.get("pinned_zig_version", ""),
    "sidegeist_ahead": int(git("rev-list", "--count",
        f"{state['upstreams']['sidegeist']['last_integrated_sha']}..sidegeist/main")[0] or 0),
    "ghostty_ahead": int(git("rev-list", "--count",
        f"{state['upstreams']['ghostty']['last_reviewed_sha']}..ghostty/main")[0] or 0),
    "macos_uses_snapshot": git(
        "grep", "-q", "ghostty_snapshot", "--", "macos", "src/apprt", check=False
    )[1] == 0,
}

satisfied = defer_queue.satisfied_entries(defer_doc, ctx)
print("== DEFER Re-assessment Gates ==")
print(
    "Context: "
    f"zig={ctx['zig_version']} sidegeist_ahead={ctx['sidegeist_ahead']} "
    f"ghostty_ahead={ctx['ghostty_ahead']} macos_uses_snapshot={ctx['macos_uses_snapshot']}"
)
print(f"Triggers satisfied: {len(satisfied)}")
for entry in satisfied[:15]:
    print(f"  [{entry['priority']}] {entry['sha'][:10]} {entry['group']} ({entry['revisit_trigger']})")
if len(satisfied) > 15:
    print(f"  ... ({len(satisfied) - 15} more)")

contained = [
    entry for entry in defer_doc.get("entries", [])
    if is_ancestor(entry["sha"], "sidegeist/main")
]
if contained:
    print(f"WARNING: {len(contained)} DEFER commit(s) are already in sidegeist/main and may be integrated:")
    for entry in contained[:10]:
        print(f"  {entry['sha'][:10]} {entry['group']}")
else:
    print("No DEFER commit is already contained in sidegeist/main.")
print()

def check_upstream(name, remote_ref, remote_head, mb_sha):
    up_cfg = state["upstreams"][name]
    reviewed_sha = up_cfg["last_reviewed_sha"]
    integrated_sha = up_cfg["last_integrated_sha"]
    print(f"== Upstream: {name} ({remote_ref}) ==")
    print(f"last_integrated_sha: {integrated_sha}")
    print(f"last_reviewed_sha:   {reviewed_sha}")

    if not is_ancestor(reviewed_sha, remote_head):
        print(
            f"ALERT: last_reviewed_sha {reviewed_sha[:10]} is NOT an ancestor of {remote_ref} ({remote_head[:10]}). "
            "Possible non-fast-forward / history rewrite!",
            file=sys.stderr,
        )
        return 1

    # Check all commits from integrated_sha..remote_head
    out, _ = git("log", "--reverse", "--topo-order", "--format=%H\t%ad\t%s", "--date=short", f"{integrated_sha}..{remote_head}")
    commits = [line.split("\t", 2) for line in out.splitlines() if line.strip()]
    unreviewed = [c for c in commits if (name, c[0]) not in seen_keys]
    needs_review = [r for r in rows if r["source"] == name and r["decision"] == "NEEDS_REVIEW"]
    pending_inc = [r for r in rows if r["source"] == name and r["decision"] == "INCLUDE" and r["integration"] == "pending"]

    # Also verify git-history inclusion for pending INCLUDE commits
    git_included = []
    for r in pending_inc:
        if is_ancestor(r["sha"], "HEAD"):
            git_included.append(r["sha"])

    print(f"Total since integrated_sha: {len(commits)}")
    print(f"Unreviewed (not in ledger): {len(unreviewed)}")
    print(f"NEEDS_REVIEW in ledger:     {len(needs_review)}")
    print(f"INCLUDE (pending):          {len(pending_inc)}")
    if git_included:
        print(f"NOTE: {len(git_included)} pending INCLUDE SHA(s) are already ancestors of HEAD: {[s[:10] for s in git_included]}")

    if unreviewed:
        print(f"First {min(20, len(unreviewed))} unreviewed commits:")
        for sha, dt, subj in unreviewed[:20]:
            print(f"  {sha[:10]} {dt} {subj}")
        if len(unreviewed) > 20:
            print(f"  ... ({len(unreviewed) - 20} more)")
    print()
    return 0

rc = 0
rc |= check_upstream("ghostty", "ghostty/main", gh_sha, mb_gh)
rc |= check_upstream("sidegeist", "sidegeist/main", sg_sha, mb_sg)

if os.environ.get("RAILTY_CHECK_PATCH_ID") == "true":
    print("== Patch-ID / git-cherry Check (HEAD vs INCLUDE pending) ==")
    head_commits_out, _ = git("rev-list", "--no-merges", f"{mb_gh}..HEAD")
    head_pids = {}
    for sha in head_commits_out.splitlines():
        if not sha:
            continue
        diff = subprocess.check_output(["git", "diff-tree", "-p", sha])
        pid = subprocess.run(["git", "patch-id", "--stable"], input=diff, capture_output=True).stdout.decode().strip()
        if pid:
            head_pids[pid.split()[0]] = sha
    matches = []
    for r in rows:
        if r["decision"] == "INCLUDE" and r["integration"] == "pending":
            diff = subprocess.check_output(["git", "diff-tree", "-p", r["sha"]])
            pid = subprocess.run(["git", "patch-id", "--stable"], input=diff, capture_output=True).stdout.decode().strip()
            if pid and pid.split()[0] in head_pids:
                matches.append((r["sha"], head_pids[pid.split()[0]], r["subject"]))
    print(f"Matching patch-ids already in Railty HEAD: {len(matches)}")
    for up_sha, local_sha, subj in matches:
        print(f"  upstream {up_sha[:10]} == local {local_sha[:10]} | {subj}")
    print()

sys.exit(rc)
PY
