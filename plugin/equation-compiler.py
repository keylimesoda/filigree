#!/usr/bin/env python3
"""Compile Filigree's small, deliberately non-executable equation language.

Every value is a complex number represented as a GLSL vec2. The shader template
provides cmul, cdiv, cpow (integer exponent), csin, ccos, cexp, cconj, cabs and
cabs2 (per-component magnitude); each returns vec2. Exactly one /* EQUATION */
marker is replaced. Successful compilations are immutable and addressed by the
complete shader's SHA-256.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


QSB = "/usr/lib/qt6/bin/qsb"
MARKER = "/* EQUATION */"
MAX_LENGTH = 512
MAX_NODES = 80
MAX_DEPTH = 16
MAX_FLOAT = 3.4028234e38
FUNCTIONS = {
    "sin": "csin",
    "cos": "ccos",
    "exp": "cexp",
    "conj": "cconj",
    "abs": "cabs",
    "abs2": "cabs2",
}


class EquationError(ValueError):
    """A concise, user-facing equation or shader error."""


def numeric_literal(value: object) -> str:
    if type(value) not in (int, float):
        raise EquationError("Use real numbers; write i for the imaginary unit.")
    try:
        number = float(value)
    except (OverflowError, ValueError):
        raise EquationError("That number is too large for the shader.") from None
    if not math.isfinite(number) or abs(number) > MAX_FLOAT:
        raise EquationError("Use finite numbers smaller than 3.4 × 10^38.")
    # repr always includes a decimal point or exponent, so GLSL receives floats.
    return repr(number)


def expression_to_glsl(expression: str) -> tuple[str, str]:
    """Validate the complete AST before generating any shader source."""
    if len(expression) > MAX_LENGTH:
        raise EquationError(f"Keep equations to {MAX_LENGTH} characters or fewer.")
    equation = expression.strip()
    if not equation:
        raise EquationError("Enter an equation, for example z^2 + c.")
    try:
        tree = ast.parse(equation.replace("^", "**"), mode="eval")
    except (SyntaxError, ValueError, RecursionError):
        raise EquationError("Check the equation's parentheses and operators.") from None
    if sum(1 for _ in ast.walk(tree)) > MAX_NODES:
        raise EquationError("That equation is too complex; use fewer operations.")

    def emit(node: ast.AST, depth: int = 0) -> str:
        if depth > MAX_DEPTH:
            raise EquationError("That equation nests operations too deeply.")
        if isinstance(node, ast.Constant):
            return f"vec2({numeric_literal(node.value)}, 0.0)"
        if isinstance(node, ast.Name):
            if node.id in ("z", "c"):
                return node.id
            if node.id == "i":
                return "vec2(0.0, 1.0)"
            if node.id == "pi":
                return "vec2(3.141592653589793, 0.0)"
            raise EquationError("Use only z, c, i, pi and the supported functions.")
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            operand = emit(node.operand, depth + 1)
            return f"({'-' if isinstance(node.op, ast.USub) else '+'}{operand})"
        if isinstance(node, ast.BinOp):
            left = emit(node.left, depth + 1)
            if isinstance(node.op, ast.Pow):
                exponent = node.right
                if not (
                    isinstance(exponent, ast.Constant)
                    and type(exponent.value) is int
                    and 0 <= exponent.value <= 8
                ):
                    raise EquationError("Powers must be whole numbers from 0 to 8, e.g. z^3.")
                return f"cpow({left}, {exponent.value})"
            right = emit(node.right, depth + 1)
            if isinstance(node.op, ast.Add):
                return f"({left} + {right})"
            if isinstance(node.op, ast.Sub):
                return f"({left} - {right})"
            if isinstance(node.op, ast.Mult):
                return f"cmul({left}, {right})"
            if isinstance(node.op, ast.Div):
                return f"cdiv({left}, {right})"
            raise EquationError("Supported operators are +, −, *, / and ^.")
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.keywords:
                raise EquationError("Use a supported function with plain positional arguments.")
            name = node.func.id
            if name == "complex":
                if len(node.args) != 2:
                    raise EquationError("complex(real, imaginary) needs two arguments.")
                real = emit(node.args[0], depth + 1)
                imaginary = emit(node.args[1], depth + 1)
                return f"({real} + cmul(vec2(0.0, 1.0), {imaginary}))"
            if name in ("re", "im"):
                if len(node.args) != 1:
                    raise EquationError(f"{name} needs exactly one argument.")
                argument = emit(node.args[0], depth + 1)
                return f"vec2(({argument}).{'x' if name == 're' else 'y'}, 0.0)"
            if name not in FUNCTIONS:
                raise EquationError("Supported functions: sin, cos, exp, conj, abs, abs2, re, im, complex.")
            if len(node.args) != 1:
                raise EquationError(f"{name} needs exactly one argument.")
            return f"{FUNCTIONS[name]}({emit(node.args[0], depth + 1)})"
        raise EquationError("Use a mathematical expression with numbers, z, c and supported functions.")

    return equation, emit(tree.body)


def shader_error(output: str, scratch: Path) -> str:
    """Retain useful diagnostics without leaking a screenful of compiler output."""
    output = output.replace(str(scratch), "shader")
    lines = [re.sub(r"\s+", " ", line).strip() for line in output.splitlines()]
    errors = [line for line in lines if "error" in line.lower()]
    useful = errors[:2] or [line for line in lines if line][:2]
    detail = " ".join(useful)[:280]
    return f"The shader could not compile: {detail}" if detail else "The shader could not compile."


def compile_equation(expression: str, template_path: Path, cache_dir: Path) -> dict:
    equation, glsl = expression_to_glsl(expression)
    try:
        template = template_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        raise EquationError("The fractal shader template could not be read.") from None
    if template.count(MARKER) != 1:
        raise EquationError("The fractal shader template needs one equation marker.")
    shader = template.replace(MARKER, glsl)
    digest = hashlib.sha256(shader.encode("utf-8")).hexdigest()
    cache_dir = cache_dir.expanduser().resolve()
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = cache_dir / f"equation-{digest}.frag.qsb"
    result = {"ok": True, "shaderPath": str(target), "equation": equation, "hash": digest}
    if target.is_file() and target.stat().st_size:
        return result

    # Compile inside the destination filesystem, then publish with atomic rename.
    # A failed edit leaves both the active shader and existing cache untouched.
    with tempfile.TemporaryDirectory(prefix=".equation-", dir=cache_dir) as temporary:
        scratch = Path(temporary)
        source = scratch / "fractal.frag"
        compiled = scratch / "fractal.frag.qsb"
        source.write_text(shader, encoding="utf-8")
        try:
            completed = subprocess.run(
                [QSB, "--glsl", "100 es,120,150", "--hlsl", "50", "--msl", "12",
                 "-o", str(compiled), str(source)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                errors="replace",
                timeout=30,
                check=False,
            )
        except subprocess.TimeoutExpired:
            raise EquationError("Compilation took too long. Try a simpler equation.") from None
        except FileNotFoundError:
            raise EquationError("The Qt shader compiler is missing. Install qt6-shadertools.") from None
        if completed.returncode or not compiled.is_file() or not compiled.stat().st_size:
            raise EquationError(shader_error(completed.stderr + "\n" + completed.stdout, scratch))
        os.replace(compiled, target)
    return result


class JsonArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise EquationError(message)


def main() -> int:
    parser = JsonArgumentParser(description=__doc__)
    parser.add_argument("--expression", required=True)
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--cache-dir", required=True, type=Path)
    try:
        # An equation may start with '-' and must remain data, even when supplied
        # as a separate argument rather than in the --expression=... form.
        arguments = sys.argv[1:]
        if "--expression" in arguments:
            index = arguments.index("--expression")
            if index + 1 < len(arguments):
                arguments[index:index + 2] = ["--expression=" + arguments[index + 1]]
        args = parser.parse_args(arguments)
        result = compile_equation(args.expression, args.template, args.cache_dir)
    except EquationError as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return 1
    except OSError:
        print(json.dumps({"ok": False, "error": "The shader cache could not be written. Check its permissions."}))
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
