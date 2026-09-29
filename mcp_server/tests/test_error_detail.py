import httpx

from dinatos_mcp.client import _error_detail


def test_falls_back_to_raw_text_for_a_non_json_body() -> None:
    response = httpx.Response(500, text="upstream is on fire")
    assert _error_detail(response) == "upstream is on fire"


def test_falls_back_to_raw_text_when_the_body_has_no_detail_field() -> None:
    response = httpx.Response(500, json={"message": "no detail key here"})
    assert _error_detail(response) == response.text


def test_reads_the_detail_field_from_a_fastapi_error_body() -> None:
    response = httpx.Response(404, json={"detail": "workout not found"})
    assert _error_detail(response) == "workout not found"
