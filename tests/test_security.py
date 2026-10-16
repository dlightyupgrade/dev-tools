from servicing_triage_ui.security import Guard


def guard():
    return Guard(4177, token="secret-token")


def test_host_must_be_loopback_with_the_server_port():
    g = guard()
    assert g.host_ok("127.0.0.1:4177") and g.host_ok("localhost:4177") and g.host_ok("LOCALHOST:4177")
    assert not g.host_ok("evil.example:4177")
    assert not g.host_ok("127.0.0.1:9999")
    assert not g.host_ok("127.0.0.1.evil.example:4177")
    assert not g.host_ok(None)


def test_origin_is_optional_but_must_match_when_sent():
    g = guard()
    assert g.origin_ok(None)
    assert g.origin_ok("http://127.0.0.1:4177")
    assert not g.origin_ok("https://evil.example")
    assert not g.origin_ok("http://127.0.0.1:4177.evil.example")
    assert not g.origin_ok("null")


def test_post_requires_json_origin_and_token():
    g = guard()
    assert g.post_ok("application/json", None, "secret-token") is None
    assert g.post_ok("application/json; charset=utf-8", "http://localhost:4177", "secret-token") is None
    assert g.post_ok("text/plain", None, "secret-token") == "content type must be application/json"
    assert g.post_ok("application/json", "https://evil.example", "secret-token") == "origin not allowed"
    assert g.post_ok("application/json", None, "wrong") == "missing or wrong token"
    assert g.post_ok("application/json", None, None) == "missing or wrong token"


def test_each_guard_gets_its_own_random_token():
    assert Guard(1).token != Guard(1).token
