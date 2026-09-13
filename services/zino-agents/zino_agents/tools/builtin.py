"""Built-in tools.

Deliberately dependency-free and side-effect-free: they are the smoke test that
the tool-calling loop works end to end. Real tools (calendar, notes, search)
belong in their own modules and register themselves the same way.
"""

from __future__ import annotations

import ast
import datetime as dt
import operator
from typing import Any

from zino_agents.tools import registry


@registry.tool(
    name="current_time",
    description=(
        "Return the current date and time in UTC as an ISO-8601 string. "
        "Call this whenever the answer depends on what day or time it is now."
    ),
    parameters={"type": "object", "properties": {}, "required": []},
)
async def current_time() -> str:
    return dt.datetime.now(dt.UTC).isoformat(timespec="seconds")


# Only these node types are evaluated; anything else is rejected. This is an
# allowlist rather than a denylist so a new Python syntax feature cannot widen it.
_ALLOWED_BINOPS: dict[type[ast.operator], Any] = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
}
_ALLOWED_UNARYOPS: dict[type[ast.unaryop], Any] = {
    ast.UAdd: operator.pos,
    ast.USub: operator.neg,
}

# Bounds the cost of `2**999999999`, which would otherwise hang the worker.
_MAX_EXPONENT = 1000


def _eval_node(node: ast.AST) -> float:
    if isinstance(node, ast.Expression):
        return _eval_node(node.body)
    if isinstance(node, ast.Constant):
        if isinstance(node.value, bool) or not isinstance(node.value, (int, float)):
            raise ValueError("only numeric literals are allowed")
        return node.value
    if isinstance(node, ast.UnaryOp):
        op = _ALLOWED_UNARYOPS.get(type(node.op))
        if op is None:
            raise ValueError("unsupported unary operator")
        return op(_eval_node(node.operand))
    if isinstance(node, ast.BinOp):
        op = _ALLOWED_BINOPS.get(type(node.op))
        if op is None:
            raise ValueError("unsupported operator")
        left, right = _eval_node(node.left), _eval_node(node.right)
        if isinstance(node.op, ast.Pow) and abs(right) > _MAX_EXPONENT:
            raise ValueError(f"exponent above {_MAX_EXPONENT} is not allowed")
        return op(left, right)
    raise ValueError("expression is not a plain arithmetic calculation")


@registry.tool(
    name="calculator",
    description=(
        "Evaluate an arithmetic expression and return the result. "
        "Supports + - * / // % ** and parentheses. Use this instead of doing "
        "multi-digit arithmetic yourself."
    ),
    parameters={
        "type": "object",
        "properties": {
            "expression": {
                "type": "string",
                "description": "An arithmetic expression, e.g. '(1200 * 1.075) / 12'.",
            }
        },
        "required": ["expression"],
    },
)
async def calculator(expression: str) -> str:
    try:
        tree = ast.parse(expression, mode="eval")
    except SyntaxError as exc:
        return f"Error: could not parse expression ({exc.msg})."
    try:
        return str(_eval_node(tree))
    except ZeroDivisionError:
        return "Error: division by zero."
    except ValueError as exc:
        return f"Error: {exc}."
