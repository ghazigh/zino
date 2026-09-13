"""The streamed tool-call accumulator is the subtlest part of the agent loop:
providers split one call across many chunks, and getting the merge wrong shows up
as silently malformed tool arguments."""

from zino_agents.agents.assistant import _accumulate_tool_call, _execute_tool


def test_fragments_merge_into_one_call():
    pending: dict[int, dict] = {}
    _accumulate_tool_call(
        pending,
        {"index": 0, "id": "call_1", "function": {"name": "calculator", "arguments": ""}},
    )
    _accumulate_tool_call(pending, {"index": 0, "function": {"arguments": '{"expre'}})
    _accumulate_tool_call(pending, {"index": 0, "function": {"arguments": 'ssion": "1+1"}'}})

    assert pending[0]["id"] == "call_1"
    assert pending[0]["function"]["name"] == "calculator"
    assert pending[0]["function"]["arguments"] == '{"expression": "1+1"}'


def test_parallel_calls_stay_separate():
    pending: dict[int, dict] = {}
    _accumulate_tool_call(pending, {"index": 0, "id": "a", "function": {"name": "current_time"}})
    _accumulate_tool_call(pending, {"index": 1, "id": "b", "function": {"name": "calculator"}})
    _accumulate_tool_call(pending, {"index": 1, "function": {"arguments": "{}"}})

    assert len(pending) == 2
    assert pending[0]["function"]["name"] == "current_time"
    assert pending[1]["function"]["arguments"] == "{}"


def test_missing_index_defaults_to_zero():
    pending: dict[int, dict] = {}
    _accumulate_tool_call(pending, {"id": "a", "function": {"name": "current_time"}})
    assert pending[0]["id"] == "a"


async def test_execute_unknown_tool_returns_error_text():
    call = {"id": "1", "function": {"name": "nope", "arguments": "{}"}}
    assert "no tool named" in await _execute_tool(call)


async def test_execute_with_malformed_json_returns_error_text():
    call = {"id": "1", "function": {"name": "calculator", "arguments": "{not json"}}
    assert "not valid JSON" in await _execute_tool(call)


async def test_execute_with_wrong_kwargs_returns_error_text():
    call = {"id": "1", "function": {"name": "calculator", "arguments": '{"bogus": 1}'}}
    assert "invalid arguments" in await _execute_tool(call)


async def test_execute_happy_path():
    call = {"id": "1", "function": {"name": "calculator", "arguments": '{"expression": "6*7"}'}}
    assert await _execute_tool(call) == "42"
