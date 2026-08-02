#!/usr/bin/env python3
"""Check the Events bus: every emit and every connect against the declaration.

Everything in this game talks over scripts/autoload/events.gd. Godot resolves
signal arity at runtime, so an emit with the wrong number of arguments, or a
handler whose parameter list does not match the signal, is a red console error
during play and nothing at all before it. With no Godot binary here, "during
play" means "after it is deployed".

Checks:

  * every `Events.x.emit(...)` names a declared signal and passes exactly as
    many arguments as it declares
  * every `Events.x.connect(handler)` names a declared signal, and the handler
    -- a named method in the same file, or an inline lambda -- accepts exactly
    the arguments the signal carries
  * signals that are declared and emitted but never listened to are reported.
    Not a failure: a signal can legitimately land before its consumer exists.
    But it is worth saying out loud, because "emitted into a void" is a bug
    that looks exactly like working code.

Run from the repository root:  python3 tools/check_signals.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVENTS = ROOT / "scripts" / "autoload" / "events.gd"

SIGNAL_DECL = re.compile(r"^signal\s+(\w+)\s*(?:\((.*)\))?\s*$", re.MULTILINE)
LAMBDA = re.compile(r"^func\s*\((.*?)\)")


def strip_strings(text: str) -> str:
    """Blank out string bodies and comments, preserving line structure.

    A regex cannot do this. The obvious `"..."|'...'` pattern treats the
    apostrophe in a comment like `## Adjuster's Streak` as an opening quote
    and swallows everything up to the next apostrophe anywhere in the file --
    which, the first time this was written, ate whole function definitions and
    made their arity un-checkable. So: one pass, character by character,
    with the quote state reset at each newline (GDScript strings do not span
    lines here).
    """
    lines = []
    for line in text.split("\n"):
        out: list[str] = []
        quote = ""
        index = 0
        while index < len(line):
            char = line[index]
            if quote:
                if char == "\\":
                    index += 2
                    continue
                if char == quote:
                    quote = ""
                index += 1
                continue
            if char == "#":
                break                      # comment: drop the rest of the line
            if char in "\"'":
                quote = char
                out.append('""')           # placeholder keeps call arity intact
                index += 1
                continue
            out.append(char)
            index += 1
        lines.append("".join(out))
    return "\n".join(lines)


def split_args(text: str) -> list[str]:
    """Split a call's argument text on top-level commas only."""
    args, depth, current = [], 0, ""
    for char in text:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            args.append(current.strip())
            current = ""
            continue
        current += char
    if current.strip():
        args.append(current.strip())
    return args


def balanced_call(text: str, open_index: int) -> tuple[str, int] | None:
    """Given the index of a '(', return its contents and the index after ')'."""
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return text[open_index + 1:index], index + 1
    return None


def declared_signals() -> dict[str, int]:
    text = EVENTS.read_text(encoding="utf-8")
    signals: dict[str, int] = {}
    for name, params in SIGNAL_DECL.findall(text):
        signals[name] = len(split_args(params)) if params and params.strip() else 0
    return signals


def param_arity(params: str) -> tuple[int, int]:
    """(required, total) for a parameter list."""
    parts = split_args(params)
    parts = [p for p in parts if p]
    required = sum(1 for p in parts if "=" not in p)
    return required, len(parts)


# Built-in methods it is legitimate to connect a signal straight to.
BUILTIN_HANDLERS = {"queue_free", "hide", "show", "stop", "play", "free", "grab_focus"}


class ScriptIndex:
    """Every project script, its extends target, and the funcs it defines --
    enough to resolve a bare handler name up an inheritance chain."""

    def __init__(self, sources: dict[str, str]):
        self.sources = sources
        self.by_class: dict[str, str] = {}
        self.extends: dict[str, str] = {}
        for path, source in sources.items():
            name = re.search(r"^class_name\s+(\w+)", source, re.MULTILINE)
            if name:
                self.by_class[name.group(1)] = path
            base = re.search(r'^extends\s+"?(res://[^"]+|\w+)"?', source, re.MULTILINE)
            if base:
                self.extends[path] = base.group(1)

    def find_func(self, path: str, name: str) -> tuple[str, str] | None:
        """Return (params, defining path), following extends. None if the
        chain runs into a Godot built-in, where we cannot know."""
        seen: set[str] = set()
        current = path
        while current and current in self.sources and current not in seen:
            seen.add(current)
            found = re.search(rf"^func {re.escape(name)}\((.*?)\)\s*(?:->|:)",
                              self.sources[current], re.MULTILINE | re.DOTALL)
            if found:
                return found.group(1), current
            base = self.extends.get(current, "")
            current = base if base.startswith("res://") else self.by_class.get(base, "")
        return None

    def chain_is_local(self, path: str) -> bool:
        """True when every script from here up is one of ours, so a name we
        did not find really is missing rather than inherited from Godot."""
        seen: set[str] = set()
        current = path
        while current in self.sources and current not in seen:
            seen.add(current)
            base = self.extends.get(current, "")
            if not base:
                return False
            if base.startswith("res://"):
                current = base
                continue
            # A bare identifier: another of our scripts, or a Godot class.
            if base in self.by_class:
                current = self.by_class[base]
                continue
            return base in ("Node", "RefCounted", "Object")
        return False


def handler_arity(index: ScriptIndex, path: str, handler: str) -> tuple[int, int] | str | None:
    """Parameter arity for a connect() argument, the string "missing" if the
    handler cannot be found at all, or None if we cannot tell (bound
    callables, callables held in variables, and so on)."""
    handler = handler.strip()
    lambda_match = LAMBDA.match(handler)
    if lambda_match:
        return param_arity(lambda_match.group(1))
    if not re.fullmatch(r"\w+", handler):
        return None            # .bind(...), Callable(...), a variable: skip
    found = index.find_func(path, handler)
    if found is not None:
        return param_arity(found[0])
    if handler in BUILTIN_HANDLERS:
        return None
    # Nothing in Godot's API is named _on_something, so a handler by that
    # convention that is not defined anywhere up the chain is a typo. This
    # matters because almost every script here extends a Godot node type,
    # which otherwise makes the chain unresolvable and the check toothless.
    if handler.startswith("_on_"):
        return "missing"
    # Otherwise only flag when the whole chain is our own code, so an
    # inherited built-in method is never reported as missing.
    if index.chain_is_local(path):
        return "missing"
    return None


def main() -> int:
    signals = declared_signals()
    if not signals:
        print("FAIL\n - no signals declared in scripts/autoload/events.gd")
        return 1

    problems: list[str] = []
    emitted: set[str] = set()
    connected: set[str] = set()
    emit_count = connect_count = 0

    sources = {
        "res://" + str(p.relative_to(ROOT)): strip_strings(p.read_text(encoding="utf-8"))
        for p in ROOT.rglob("*.gd")
    }
    index = ScriptIndex(sources)

    for path in sorted(ROOT.rglob("*.gd")):
        if path == EVENTS:
            continue
        rel = str(path.relative_to(ROOT))
        source = sources["res://" + rel]

        for match in re.finditer(r"\bEvents\.(\w+)\.(emit|connect)\(", source):
            name, kind = match.group(1), match.group(2)
            line = source.count("\n", 0, match.start()) + 1
            if name not in signals:
                problems.append(f"{rel}:{line}: Events.{name} is not a declared signal")
                continue
            call = balanced_call(source, match.end() - 1)
            if call is None:
                problems.append(f"{rel}:{line}: unbalanced parentheses in Events.{name}.{kind}(")
                continue
            args = split_args(call[0])
            if kind == "emit":
                emit_count += 1
                emitted.add(name)
                if len(args) != signals[name]:
                    problems.append(
                        f"{rel}:{line}: Events.{name}.emit() passes {len(args)} "
                        f"argument(s); the signal declares {signals[name]}")
            else:
                connect_count += 1
                connected.add(name)
                if not args:
                    problems.append(f"{rel}:{line}: Events.{name}.connect() has no handler")
                    continue
                arity = handler_arity(index, "res://" + rel, args[0])
                if arity is None:
                    continue
                if arity == "missing":
                    problems.append(
                        f"{rel}:{line}: Events.{name}.connect({args[0]}) — no such "
                        f"method on this script or anything it extends")
                    continue
                required, total = arity
                if not required <= signals[name] <= total:
                    problems.append(
                        f"{rel}:{line}: Events.{name} carries {signals[name]} "
                        f"argument(s) but the handler accepts {required}"
                        f"{'' if required == total else f'-{total}'}")

    print(f"checked {len(signals)} signals, {emit_count} emits, {connect_count} connects")

    if problems:
        print("\nFAIL")
        for problem in problems:
            print(f" - {problem}")
        return 1

    orphans = sorted(emitted - connected)
    if orphans:
        print("note: emitted with no listener anywhere: " + ", ".join(orphans))
    silent = sorted(set(signals) - emitted - connected)
    if silent:
        print("note: declared but neither emitted nor connected: " + ", ".join(silent))

    print("All signal emits and handlers match their declarations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
