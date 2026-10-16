from pathlib import Path

from servicing_triage_ui.stats import parse_stats

TEXT = (Path(__file__).parent / "fixtures" / "stats_sample.txt").read_text()


def rows(stats):
    return {row["label"]: row for section in stats["sections"] for row in section["rows"]}


def test_sections_and_day_are_parsed():
    stats = parse_stats(TEXT)
    assert stats["day"] == "Thu 2026-10-15"
    assert [section["name"] for section in stats["sections"]] == ["Payments", "Due dates", "Charge-offs"]


def test_counts_dollars_and_changes():
    row = rows(parse_stats(TEXT))["Refunds processed"]
    assert row["count"] == 1132 and row["dollars"] == 640066.45
    assert row["change_percent"] == 31 and row["failure"] is False


def test_negative_and_same_changes():
    parsed = rows(parse_stats(TEXT))
    assert parsed["Reversals processed"]["change_percent"] == -20
    assert parsed["Loan charge-offs failed"]["change_percent"] == 0


def test_breakdown_and_follow_up_on_failures():
    row = rows(parse_stats(TEXT))["Failed requests"]
    assert row["failure"] is True and row["follow_up"] == "follow up with failure triage"
    assert row["breakdown"] == [{"name": "TRANSACTION", "count": 6}, {"name": "REVERSAL", "count": 4}, {"name": "REFUND", "count": 1}]


def test_row_without_dollars_has_none():
    assert rows(parse_stats(TEXT))["Due date changes, all payments"]["dollars"] is None


def test_unchecked_and_notes_are_separated_from_sections():
    stats = parse_stats(TEXT)
    assert [item["name"] for item in stats["unchecked"]] == ["loan hardship", "loan restructures"]
    assert all("permission denied for schema loanhardship" == item["reason"] for item in stats["unchecked"])
    assert any(note.startswith("Counted by when") for note in stats["notes"])
