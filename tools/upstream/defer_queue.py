"""Validation helpers for the Railty deferred-review queue and state checks.

The module is intentionally dependency-free so that both
``tools/upstream/check.sh`` and the unit tests can import it.

It never mutates the repository and never runs git commands itself; callers
inject the facts (HEAD, ancestry results, changed files) so the logic is
testable without a real repository.
"""

from __future__ import annotations

import re

PRIORITIES = {"P1", "P2", "P3"}
REVIEW_STATUSES = {
    "awaiting_validation",
    "awaiting_dependencies",
    "awaiting_toolchain",
    "awaiting_upstream",
    "no_runtime_path",
    "candidate_next_batch",
}
REVISIT_TRIGGERS = {
    "on_zig_upgrade",
    "on_sidegeist_upgrade",
    "on_upstream_dependency_update",
    "on_macos_snapshot_consumer",
    "on_toolchain_upgrade",
    "on_next_sync_review",
    "manual_dedicated_port",
    "on_user_request",
}

REQUIRED_ENTRY_FIELDS = {
    "source",
    "sha",
    "topic",
    "group",
    "priority",
    "revisit_trigger",
    "validation_plan",
    "review_status",
    "last_reassessed_at",
    "notes",
}

PROTOCOL_PREFIXES = ("docs/", "tools/upstream/", ".github/")
PROTOCOL_FILES = {"AGENTS.md"}


def semver(tag):
    """Parse ``vX.Y.Z`` into a comparable tuple, or return None."""
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag or "")
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def validate_queue(document, ledger_rows):
    """Return ``(errors, warnings)`` for a defer-queue document.

    The queue must cover every ``DEFER`` ledger row exactly once and must not
    contain entries for any other decision.
    """
    errors = []
    warnings = []

    entries = document.get("entries") if isinstance(document, dict) else None
    if not isinstance(entries, list):
        return ["defer-queue: 'entries' must be a list"], warnings
    if document.get("source_ledger") != "docs/upstream/ledger.jsonl":
        warnings.append("defer-queue: source_ledger should be docs/upstream/ledger.jsonl")

    ledger_defer = {
        (row.get("source"), row.get("sha"))
        for row in ledger_rows
        if row.get("decision") == "DEFER"
    }

    seen = set()
    for index, entry in enumerate(entries):
        label = f"defer-queue entry {index + 1}"
        if not isinstance(entry, dict):
            errors.append(f"{label}: must be an object")
            continue

        missing = REQUIRED_ENTRY_FIELDS - set(entry)
        if missing:
            errors.append(f"{label}: missing fields {sorted(missing)}")
            continue

        key = (entry.get("source"), entry.get("sha"))
        label = f"defer-queue entry {entry['sha'][:10]}"
        if key in seen:
            errors.append(f"{label}: duplicate (source, sha)")
        seen.add(key)

        if key not in ledger_defer:
            errors.append(f"{label}: is not a DEFER row in ledger.jsonl")
        if entry.get("priority") not in PRIORITIES:
            errors.append(f"{label}: invalid priority {entry.get('priority')!r}")
        if entry.get("review_status") not in REVIEW_STATUSES:
            errors.append(f"{label}: invalid review_status {entry.get('review_status')!r}")
        if entry.get("revisit_trigger") not in REVISIT_TRIGGERS:
            errors.append(f"{label}: invalid revisit_trigger {entry.get('revisit_trigger')!r}")
        if not entry.get("group"):
            errors.append(f"{label}: empty group")
        if not entry.get("validation_plan"):
            errors.append(f"{label}: empty validation_plan")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", entry.get("last_reassessed_at") or ""):
            errors.append(f"{label}: last_reassessed_at must be YYYY-MM-DD")

    missing_entries = ledger_defer - seen
    if missing_entries:
        preview = sorted(sha[:10] for _, sha in missing_entries)[:5]
        errors.append(f"defer-queue: {len(missing_entries)} DEFER rows have no queue entry: {preview}")

    return errors, warnings


def queue_summary(document):
    """Aggregate the queue by priority, group, status and trigger."""
    entries = document.get("entries", []) if isinstance(document, dict) else []
    summary = {
        "total": len(entries),
        "by_priority": {},
        "by_group": {},
        "by_status": {},
        "by_trigger": {},
    }
    for entry in entries:
        for bucket, field in (
            ("by_priority", "priority"),
            ("by_group", "group"),
            ("by_status", "review_status"),
            ("by_trigger", "revisit_trigger"),
        ):
            value = entry.get(field, "?")
            summary[bucket][value] = summary[bucket].get(value, 0) + 1
    return summary


def trigger_satisfied(entry, context):
    """Return True when an entry's re-assessment trigger is already met.

    ``context`` keys:
      - ``zig_version``: pinned Zig version string (e.g. ``"0.17.0"``)
      - ``sidegeist_ahead``: commits on sidegeist/main since the integrated base
      - ``ghostty_ahead``: unreviewed Ghostty commits since last_reviewed_sha
      - ``macos_uses_snapshot``: True when the macOS app calls ghostty_snapshot_*
    """
    trigger = entry.get("revisit_trigger")
    if trigger == "on_toolchain_upgrade":
        version = context.get("zig_version") or ""
        return bool(re.fullmatch(r"0\.\d+\.\d+", version)) and tuple(
            int(part) for part in version.split(".")
        ) >= (0, 17, 1)
    if trigger == "on_zig_upgrade":
        return trigger_satisfied({**entry, "revisit_trigger": "on_toolchain_upgrade"}, context)
    if trigger in ("on_sidegeist_upgrade",):
        return context.get("sidegeist_ahead", 0) > 0
    if trigger == "on_upstream_dependency_update":
        return context.get("ghostty_ahead", 0) > 0
    if trigger == "on_macos_snapshot_consumer":
        return bool(context.get("macos_uses_snapshot"))
    if trigger == "on_next_sync_review":
        return context.get("ghostty_ahead", 0) > 0 or context.get("sidegeist_ahead", 0) > 0
    # manual_dedicated_port / on_user_request: a human decision, never automatic.
    return False


def satisfied_entries(document, context):
    """Return the entries whose trigger is currently satisfied."""
    return [
        entry
        for entry in (document.get("entries", []) if isinstance(document, dict) else [])
        if trigger_satisfied(entry, context)
    ]


def state_head_status(state_head, head_sha, is_ancestor, changed_files):
    """Classify how far ``state.json``'s head_sha is from the real HEAD.

    Returns ``(level, message)`` where level is ``ok``, ``info`` or ``warn``.
    """
    if not state_head:
        return "warn", "state.json railty.head_sha is missing"
    if state_head == head_sha:
        return "ok", f"railty.head_sha matches HEAD ({head_sha[:10]})"
    if not is_ancestor:
        return (
            "warn",
            f"state.json head_sha {state_head[:10]} is NOT an ancestor of HEAD "
            f"{head_sha[:10]} (history rewrite or stale checkout?)",
        )

    changed = [path for path in changed_files if path]
    code_changes = [
        path
        for path in changed
        if not path.startswith(PROTOCOL_PREFIXES) and path not in PROTOCOL_FILES
    ]
    if code_changes:
        return (
            "warn",
            f"state.json head_sha {state_head[:10]} is behind HEAD {head_sha[:10]} "
            f"with code changes ({len(code_changes)}): {code_changes[:5]}",
        )
    return (
        "info",
        f"railty.head_sha {state_head[:10]} is behind HEAD {head_sha[:10]} "
        f"(protocol/docs-only drift, {len(changed)} file(s))",
    )


def release_tag_status(state_tag, release_tags):
    """Classify ``latest_release_tag`` against origin's release tags.

    ``release_tags`` is None when origin could not be reached.
    """
    if release_tags is None:
        return "info", "release tag check skipped: cannot reach origin"
    tags = [tag for tag in release_tags if semver(tag)]
    if not tags:
        return "warn", "no Railty vX.Y.Z release tag found on origin"

    newest = max(tags, key=semver)
    if not state_tag:
        return "warn", "state.json railty.latest_release_tag is missing"
    if semver(newest) > semver(state_tag):
        return (
            "warn",
            f"state.json latest_release_tag {state_tag} is behind newest release tag {newest}",
        )
    if semver(newest) < semver(state_tag):
        return (
            "warn",
            f"state.json latest_release_tag {state_tag} is newer than any tag found ({newest})",
        )
    return "ok", f"railty.latest_release_tag matches newest release tag ({newest})"
