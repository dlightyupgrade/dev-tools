from servicing_triage_ui.sumo_index import SumoIndex, needles_for

MONITOR = '''
module "x" {
  name   = "%s"
  query = <<-EOT
    %s
  EOT
  thresholds = {
    time_range = "15m"
  }
  priority = "P3"
  notification = {
    slack_channels = ["feeds_prod_servicing_app_alerts", "other"]
    incidentio     = {}
  }
}
'''


def write(root, relative, name, query):
    path = root / "monitors" / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(MONITOR % (name, query))


def finding(**overrides):
    base = {"key": "loan-servicing-srvc:Svc:payment-post:SP00445:account_closed", "error_text": "", "title": "t", "area": "loan-servicing-srvc"}
    return {**base, **overrides}


def test_index_reads_prod_monitors_only(tmp_path):
    write(tmp_path, "servicing/20-a_prod.tf", "Prod monitor", "SP00445 something")
    write(tmp_path, "servicing/preprod/20-a.tf", "Preprod monitor", "SP00445 something")
    write(tmp_path, "servicing/20-stage_b.tf", "Stage monitor", "SP00445 something")
    index = SumoIndex(tmp_path)
    assert [m["name"] for m in index.monitors] == ["Prod monitor"]
    monitor = index.monitors[0]
    assert monitor["priority"] == "P3" and monitor["window"] == "15m" and monitor["incidentio"] is True
    assert monitor["channels"] == ["feeds_prod_servicing_app_alerts", "other"]
    assert monitor["team"] == "servicing"


def test_find_by_code_text_and_task(tmp_path):
    write(tmp_path, "servicing/20-a.tf", "Code monitor", "\"SP00445 - Account is not open\"")
    write(tmp_path, "servicing/20-b.tf", "Text monitor", "\"Loan Boarded in PIPELINE state\"")
    write(tmp_path, "servicing/20-c.tf", "Task monitor", "LoanBoardingTaskV2 aborted")
    index = SumoIndex(tmp_path)
    assert [m["name"] for m in index.find([("code", "SP00445")])["monitors"]] == ["Code monitor"]
    text = index.find([("text", "loan boarded in pipeline state")])
    assert text["total"] == 1 and text["monitors"][0]["matched_on"] == ["text"]
    assert index.find([("task", "LoanBoardingTaskV2")])["monitors"][0]["name"] == "Task monitor"
    assert index.find([("code", "SP99999")]) == {"total": 0, "monitors": []}


def test_find_ranks_code_matches_first_and_limits(tmp_path):
    for number in range(8):
        write(tmp_path, f"servicing/20-m{number}.tf", f"Monitor {number}", "SP00445")
    write(tmp_path, "servicing/20-task.tf", "Aaa task", "LoanBoardingTaskV2")
    result = SumoIndex(tmp_path).find([("task", "LoanBoardingTaskV2"), ("code", "SP00445")], limit=3)
    assert result["total"] == 9 and len(result["monitors"]) == 3
    assert all(m["matched_on"] == ["code"] for m in result["monitors"])


def test_missing_checkout_is_not_available(tmp_path):
    assert SumoIndex(tmp_path / "nope").available is False
    assert SumoIndex(None).available is False


def test_needles_for_code_text_and_task():
    needles = needles_for(finding(
        key="loanservicing-tqf:LoanBoardingTaskV2:CfInternalServerException: Loan Boarded in PIPELINE state. Will retry loanAccountNumber:no_playbook",
        error_text="com.credify.core.exception.CfInternalServerException: Loan Boarded in PIPELINE state. Will retry loanAccountNumber=# productType=X",
        area="loanservicing-tqf",
    ))
    assert ("task", "LoanBoardingTaskV2") in needles
    assert any(kind == "text" and needle.startswith("Loan Boarded in PIPELINE state") for kind, needle in needles)
    assert ("code", "SP00445") in needles_for(finding())


def test_needles_skip_text_that_is_cut_short_by_a_number():
    error = "SP00229 - Amount $0.04 cannot exceed Interest Receivable Amount $0.00."
    assert needles_for(finding(key="refund-sensor:x", error_text=error, area="refund-sensor")) == [("code", "SP00229")]
