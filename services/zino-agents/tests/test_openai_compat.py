import json

from zino_agents.openai_compat import ChatMessage, chunk, completion_response


def test_text_flattens_plain_string():
    assert ChatMessage(role="user", content="hello").text() == "hello"


def test_text_flattens_multimodal_parts_and_ignores_non_text():
    msg = ChatMessage(
        role="user",
        content=[
            {"type": "text", "text": "describe "},
            {"type": "image_url", "image_url": {"url": "http://x/y.png"}},
            {"type": "text", "text": "this"},
        ],
    )
    assert msg.text() == "describe this"


def test_text_handles_null_content():
    assert ChatMessage(role="assistant", content=None).text() == ""


def test_request_tolerates_unknown_fields():
    # Open WebUI sends fields we do not model; they must not 422 the request.
    msg = ChatMessage(role="user", content="hi", some_future_field=1)
    assert msg.role == "user"


def test_chunk_is_valid_sse_json():
    line = chunk("id-1", "zino-echo", {"content": "hi"})
    assert line.startswith("data: ")
    assert line.endswith("\n\n")
    body = json.loads(line[len("data: ") :])
    assert body["object"] == "chat.completion.chunk"
    assert body["choices"][0]["delta"]["content"] == "hi"
    assert body["choices"][0]["finish_reason"] is None


def test_completion_response_shape():
    body = completion_response("zino-echo", "answer")
    assert body["object"] == "chat.completion"
    assert body["choices"][0]["message"] == {"role": "assistant", "content": "answer"}
    assert body["choices"][0]["finish_reason"] == "stop"
