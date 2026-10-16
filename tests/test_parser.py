import json
from pathlib import Path

import pytest

from servicing_triage_ui.parser import finding_id, parse_report, parse_sample, summarize_unchecked

FIXTURE = Path(__file__).parent / "fixtures" / "triage_sample.json"


@pytest.fixture(scope="module")
def report():
    return parse_report(json.loads(FIXTURE.read_text())["text"])


def by_key(report, fragment):
    return next(finding for finding in report["findings"] if fragment in finding["key"])


def test_header_counts(report):
    assert report["window_days"] == 1
    assert report["signatures"] == 6
    assert report["failures"] == 282
    assert len(report["findings"]) == 6


def test_findings_are_ordered_by_who_must_act_then_dollars(report):
    assert [finding["disposition"] for finding in report["findings"]] == ["bug", "ops", "review", "review", "review", "review"]
    review_dollars = [finding["dollars"] or 0 for finding in report["findings"][2:]]
    assert review_dollars == sorted(review_dollars, reverse=True)


def test_bug_finding_has_ticket_draft_and_duplicate_check(report):
    bug = by_key(report, "SP00531")
    assert bug["code"] == "SP00531"
    assert bug["route"] == "dev"
    assert bug["draft"]["kind"] == "ticket_draft"
    assert bug["draft"]["meta"]["duplicate_search_jql"].startswith('labels = "triage-sig-')
    assert bug["sample_kind"] == "ids"
    assert bug["samples"][0][1].startswith("$")


def test_ops_finding_has_handoff_and_payment_samples(report):
    ops = by_key(report, "SP00445")
    assert ops["route"] == "biz-ops"
    assert ops["draft"]["kind"] == "ops_handoff"
    assert ops["count"] == 3
    assert ops["dollars"] == 1426.04
    assert ops["sample_kind"] == "payment"
    assert ops["sample_columns"][0] == "Request"
    assert len(ops["samples"][0]) == len(ops["sample_columns"])


def test_review_payment_finding_takes_error_text_and_why(report):
    review = by_key(report, "SP00641")
    assert review["code"] == "SP00641"
    assert review["error_text"].startswith("SP00641 - Over-payment")
    assert review["summary"]
    assert review["draft"]["kind"] in ("biz_ops", "dev_ticket")


def test_billing_finding_uses_billing_samples(report):
    billing = by_key(report, "billing:unbilled-open-loans:delinquent")
    assert billing["count"] == 271
    assert billing["dollars"] is None
    assert billing["sample_kind"] == "billing"
    assert billing["title"].startswith("Unbilled open loans:")


def test_tqf_finding_has_task_samples_and_title(report):
    task = by_key(report, "LoanBoardingTaskV2")
    assert task["sample_kind"] == "task"
    assert task["title"].startswith("LoanBoardingTaskV2: ")
    assert "Exception" not in task["title"].split(": ", 1)[1][:20]
    assert task["samples"][0][3].isdigit()


def test_finding_without_a_draft_still_explains_itself(report):
    undrafted = by_key(report, "SP00395")
    assert undrafted["draft"] is None
    assert undrafted["summary"]
    assert undrafted["next_step"]


def test_unchecked_sensors_are_listed_with_short_reasons(report):
    assert report["unchecked"] == [
        {"name": "loanhardship tqf tasks", "reason": "permission denied for schema loanhardship"},
        {"name": "spectrumcustomer tqf tasks", "reason": "rail checker rejected the query"},
    ]


def test_finding_id_is_stable_and_short():
    assert finding_id("a:b") == finding_id("a:b")
    assert len(finding_id("a:b")) == 12


def test_report_without_findings_parses():
    empty = parse_report("Failure triage, last 2 days: 0 signatures, 0 failures\n\nNo failures.")
    assert empty["findings"] == [] and empty["unchecked"] == []


def test_parse_sample_kinds():
    assert parse_sample("- not a sample") is None
    kind, cells = parse_sample("- account 1 | 2 loan(s) in this group | last bill due none in 120 days | spectrum")
    assert kind == "billing" and cells[0] == "1"


def test_unchecked_reason_falls_back_to_a_trimmed_line():
    assert summarize_unchecked("boom\n  with detail " + "x" * 400).startswith("boom with detail")
    assert len(summarize_unchecked("y" * 400)) == 160
