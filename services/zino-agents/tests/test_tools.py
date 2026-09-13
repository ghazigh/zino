import pytest

from zino_agents.tools import registry
from zino_agents.tools.builtin import calculator, current_time


async def test_calculator_basic():
    assert await calculator("2 + 3 * 4") == "14"


async def test_calculator_parentheses_and_float():
    assert await calculator("(1 + 1) / 4") == "0.5"


async def test_calculator_rejects_names_and_calls():
    assert (await calculator("__import__('os').system('ls')")).startswith("Error:")
    assert (await calculator("open('/etc/passwd')")).startswith("Error:")
    assert (await calculator("x + 1")).startswith("Error:")


async def test_calculator_rejects_huge_exponent():
    # Guards against wedging the worker on 2**10**9.
    assert (await calculator("2 ** 999999999")).startswith("Error:")


async def test_calculator_handles_division_by_zero():
    assert await calculator("1/0") == "Error: division by zero."


async def test_calculator_handles_syntax_error():
    assert (await calculator("1 +")).startswith("Error: could not parse")


async def test_current_time_is_iso_utc():
    value = await current_time()
    assert value.endswith("+00:00")


def test_builtin_tools_are_registered():
    assert "calculator" in registry
    assert "current_time" in registry
    names = {s["function"]["name"] for s in registry.specs()}
    assert names == {"calculator", "current_time"}


def test_duplicate_registration_is_rejected():
    from zino_agents.tools import Tool

    with pytest.raises(ValueError):
        registry.register(Tool(name="calculator", description="dupe", parameters={}, fn=calculator))
