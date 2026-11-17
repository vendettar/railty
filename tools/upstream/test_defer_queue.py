"""Unit tests for tools/upstream/defer_queue.py.

Run with: python3 -m unittest tools/upstream/test_defer_queue.py
"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import defer_queue as dq


def make_entry(sha="a" * 40, **overrides):
    entry = {
        "source": "ghostty",
        "sha": sha,
        "topic": "terminal-perf-pagelist-fastpath",
        "group": "terminal-cursor-pin-fastpath",
        "priority": "P2",
        "revisit_trigger": "manual_dedicated_port",
        "validation_plan": "Run tests and a macOS arm64 build.",
        "review_status": "candidate_next_batch",
        "last_reassessed_at": "2026-11-17",
        "notes": "Test fixture.",
    }
    entry.update(overrides)
    return entry


def make_document(entries):
    return {
        "schema_version": 1,
        "updated_at": "2026-11-17",
        "source_ledger": "docs/upstream/ledger.jsonl",
        "entries": entries,
    }


def ledger(rows):
    return [
        {"source": source, "sha": sha, "decision": decision}
        for source, sha, decision in rows
    ]


class ValidateQueueTests(unittest.TestCase):
    def test_valid_document_has_no_errors(self):
        doc = make_document([make_entry()])
        errors, warnings = dq.validate_queue(doc, ledger([("ghostty", "a" * 40, "DEFER")]))
        self.assertEqual(errors, [])
        self.assertEqual(warnings, [])

    def test_empty_queue_with_deferred_rows_is_an_error(self):
        errors, _ = dq.validate_queue(make_document([]), ledger([("ghostty", "a" * 40, "DEFER")]))
        self.assertEqual(len(errors), 1)
        self.assertIn("no queue entry", errors[0])

    def test_duplicate_sha_is_an_error(self):
        doc = make_document([make_entry(), make_entry()])
        errors, _ = dq.validate_queue(doc, ledger([("ghostty", "a" * 40, "DEFER")]))
        self.assertTrue(any("duplicate" in error for error in errors), errors)

    def test_invalid_priority_status_and_trigger_are_errors(self):
        doc = make_document(
            [
                make_entry(
                    priority="P9",
                    review_status="maybe",
                    revisit_trigger="whenever",
                )
            ]
        )
        errors, _ = dq.validate_queue(doc, ledger([("ghostty", "a" * 40, "DEFER")]))
        joined = "\n".join(errors)
        self.assertIn("invalid priority", joined)
        self.assertIn("invalid review_status", joined)
        self.assertIn("invalid revisit_trigger", joined)

    def test_missing_required_field_is_an_error(self):
        entry = make_entry()
        del entry["validation_plan"]
        errors, _ = dq.validate_queue(make_document([entry]), ledger([("ghostty", "a" * 40, "DEFER")]))
        self.assertTrue(any("missing fields" in error for error in errors), errors)

    def test_entry_for_non_deferred_row_is_an_error(self):
        errors, _ = dq.validate_queue(
            make_document([make_entry()]),
            ledger([("ghostty", "a" * 40, "INCLUDE")]),
        )
        self.assertTrue(any("not a DEFER" in error for error in errors), errors)

    def test_bad_reassessed_date_is_an_error(self):
        errors, _ = dq.validate_queue(
            make_document([make_entry(last_reassessed_at="17/11/2026")]),
            ledger([("ghostty", "a" * 40, "DEFER")]),
        )
        self.assertTrue(any("last_reassessed_at" in error for error in errors), errors)

    def test_missing_entries_is_a_list(self):
        errors, _ = dq.validate_queue({"entries": "nope"}, [])
        self.assertTrue(errors)


class SummaryTests(unittest.TestCase):
    def test_summary_counts_each_bucket(self):
        doc = make_document(
            [
                make_entry(priority="P1", group="g1"),
                make_entry(sha="b" * 40, priority="P2", group="g1"),
                make_entry(sha="c" * 40, priority="P2", group="g2", review_status="awaiting_upstream"),
            ]
        )
        summary = dq.queue_summary(doc)
        self.assertEqual(summary["total"], 3)
        self.assertEqual(summary["by_priority"], {"P1": 1, "P2": 2})
        self.assertEqual(summary["by_group"], {"g1": 2, "g2": 1})
        self.assertEqual(summary["by_status"]["awaiting_upstream"], 1)


class TriggerTests(unittest.TestCase):
    def test_toolchain_trigger_requires_0_17_1(self):
        entry = {"revisit_trigger": "on_toolchain_upgrade"}
        self.assertFalse(dq.trigger_satisfied(entry, {"zig_version": "0.17.0"}))
        self.assertTrue(dq.trigger_satisfied(entry, {"zig_version": "0.17.1"}))
        self.assertFalse(dq.trigger_satisfied(entry, {"zig_version": "invalid"}))

    def test_sidegeist_and_upstream_triggers(self):
        side = {"revisit_trigger": "on_sidegeist_upgrade"}
        upstream = {"revisit_trigger": "on_upstream_dependency_update"}
        self.assertFalse(dq.trigger_satisfied(side, {"sidegeist_ahead": 0}))
        self.assertTrue(dq.trigger_satisfied(side, {"sidegeist_ahead": 2}))
        self.assertFalse(dq.trigger_satisfied(upstream, {"ghostty_ahead": 0}))
        self.assertTrue(dq.trigger_satisfied(upstream, {"ghostty_ahead": 5}))

    def test_snapshot_trigger_needs_a_macos_consumer(self):
        entry = {"revisit_trigger": "on_macos_snapshot_consumer"}
        self.assertFalse(dq.trigger_satisfied(entry, {"macos_uses_snapshot": False}))
        self.assertTrue(dq.trigger_satisfied(entry, {"macos_uses_snapshot": True}))

    def test_next_sync_trigger_reacts_to_either_upstream(self):
        entry = {"revisit_trigger": "on_next_sync_review"}
        self.assertFalse(dq.trigger_satisfied(entry, {"ghostty_ahead": 0, "sidegeist_ahead": 0}))
        self.assertTrue(dq.trigger_satisfied(entry, {"ghostty_ahead": 1, "sidegeist_ahead": 0}))
        self.assertTrue(dq.trigger_satisfied(entry, {"ghostty_ahead": 0, "sidegeist_ahead": 1}))

    def test_manual_triggers_never_satisfy_automatically(self):
        context = {"zig_version": "0.17.1", "ghostty_ahead": 10, "sidegeist_ahead": 10}
        for trigger in ("manual_dedicated_port", "on_user_request"):
            self.assertFalse(dq.trigger_satisfied({"revisit_trigger": trigger}, context))

    def test_satisfied_entries_filters_document(self):
        doc = make_document(
            [
                make_entry(sha="a" * 40, revisit_trigger="on_sidegeist_upgrade"),
                make_entry(sha="b" * 40, revisit_trigger="manual_dedicated_port"),
            ]
        )
        satisfied = dq.satisfied_entries(doc, {"sidegeist_ahead": 1})
        self.assertEqual([entry["sha"] for entry in satisfied], ["a" * 40])


class StateHeadTests(unittest.TestCase):
    def test_equal_heads(self):
        level, _ = dq.state_head_status("abc", "abc", is_ancestor=True, changed_files=[])
        self.assertEqual(level, "ok")

    def test_missing_state_head(self):
        level, _ = dq.state_head_status("", "abc", is_ancestor=True, changed_files=[])
        self.assertEqual(level, "warn")

    def test_code_changes_behind_head_warn(self):
        level, message = dq.state_head_status(
            "aaa",
            "bbb",
            is_ancestor=True,
            changed_files=["src/terminal/Terminal.zig"],
        )
        self.assertEqual(level, "warn")
        self.assertIn("code changes", message)

    def test_protocol_only_changes_are_informational(self):
        level, message = dq.state_head_status(
            "aaa",
            "bbb",
            is_ancestor=True,
            changed_files=[
                "docs/upstream/state.json",
                "tools/upstream/check.sh",
                ".github/workflows/ci-railty.yml",
                "AGENTS.md",
            ],
        )
        self.assertEqual(level, "info")
        self.assertIn("protocol/docs-only", message)

    def test_history_rewrite_warns(self):
        level, message = dq.state_head_status("aaa", "bbb", is_ancestor=False, changed_files=[])
        self.assertEqual(level, "warn")
        self.assertIn("NOT an ancestor", message)


class ReleaseTagTests(unittest.TestCase):
    def test_unreachable_origin_is_informational(self):
        level, _ = dq.release_tag_status("v0.1.4", None)
        self.assertEqual(level, "info")

    def test_no_tags_is_a_warning(self):
        level, _ = dq.release_tag_status("v0.1.4", [])
        self.assertEqual(level, "warn")

    def test_equal_tag(self):
        level, _ = dq.release_tag_status("v0.1.4", ["v0.1.3", "v0.1.4"])
        self.assertEqual(level, "ok")

    def test_state_behind_tag_warns(self):
        level, message = dq.release_tag_status("v0.1.3", ["v0.1.4"])
        self.assertEqual(level, "warn")
        self.assertIn("behind", message)

    def test_state_newer_than_tags_warns(self):
        level, message = dq.release_tag_status("v0.2.0", ["v0.1.4"])
        self.assertEqual(level, "warn")
        self.assertIn("newer", message)

    def test_missing_state_tag_warns(self):
        level, message = dq.release_tag_status(None, ["v0.1.4"])
        self.assertEqual(level, "warn")
        self.assertIn("missing", message)


class SemverTests(unittest.TestCase):
    def test_semver_parsing(self):
        self.assertEqual(dq.semver("v1.4.0"), (1, 4, 0))
        self.assertIsNone(dq.semver("tip"))
        self.assertIsNone(dq.semver("v1.4"))


class RepositoryFilesTests(unittest.TestCase):
    """Validate the checked-in ledger and queue without network or git.

    This is the CI-safe replacement for running check.sh, which needs remote
    tracking refs and therefore cannot run on a fresh checkout.
    """

    @classmethod
    def setUpClass(cls):
        cls.root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    def test_repository_ledger_and_queue_are_consistent(self):
        ledger_path = os.path.join(self.root, "docs/upstream/ledger.jsonl")
        queue_path = os.path.join(self.root, "docs/upstream/defer-queue.json")

        rows = []
        with open(ledger_path, encoding="utf-8") as handle:
            for line in handle:
                if line.strip():
                    rows.append(json.loads(line))
        self.assertTrue(rows, "ledger.jsonl must not be empty")

        keys = [(row["source"], row["sha"]) for row in rows]
        self.assertEqual(len(keys), len(set(keys)), "ledger.jsonl contains duplicate (source, sha)")

        with open(queue_path, encoding="utf-8") as handle:
            document = json.load(handle)
        errors, _ = dq.validate_queue(document, rows)
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
