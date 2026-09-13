"""Reproduce official @file expansion when persisted prompt text is replayed.

This imports the installed official context-reference preprocessor and uses only
a disposable local workspace. It starts no backend and reads no session data.
"""

from __future__ import annotations

import os
from pathlib import Path
import sys
import tempfile
import types


official_root = Path(os.environ["LOCALAPPDATA"]) / "hermes" / "hermes-agent"
context_source = official_root / "agent" / "context_references.py"
prompt_source = official_root / "tui_gateway" / "methods_prompt.py"
turn_source = official_root / "tui_gateway" / "prompt_turn.py"

assert context_source.is_file(), f"Official source not found: {context_source}"
assert prompt_source.is_file(), f"Official source not found: {prompt_source}"
assert turn_source.is_file(), f"Official source not found: {turn_source}"

# context_references imports the model token estimator through a module that has
# optional CLI dependencies. Token accounting is outside this repro, so provide
# the same conservative length shape and use a context limit far above the fixture.
model_metadata = types.ModuleType("agent.model_metadata")
model_metadata.estimate_tokens_rough = lambda value: max(1, len(str(value)) // 4)
sys.modules["agent.model_metadata"] = model_metadata
sys.path.insert(0, str(official_root))

from agent.context_references import preprocess_context_references  # noqa: E402


source = context_source.read_text(encoding="utf-8-sig")
prompt_handler = prompt_source.read_text(encoding="utf-8-sig")
turn_handler = turn_source.read_text(encoding="utf-8-sig")
assert "original_message=message" in source
assert 'final = f"{final}\\n\\n--- Attached Context ---\\n\\n"' in source
assert 'raw_text = params.get("text", "")' in prompt_handler
assert "prompt = ctx.message" in turn_handler

marker = "fixture-value-amber-729"
header = "--- Attached Context ---"

with tempfile.TemporaryDirectory(prefix="regeneration-context-") as fixture_dir:
    workspace = Path(fixture_dir)
    (workspace / "fixture.txt").write_text(marker, encoding="utf-8")

    original = "@file:fixture.txt\n\nSummarize this file."
    first = preprocess_context_references(
        original, cwd=workspace, allowed_root=workspace, context_length=100_000
    ).message
    replay = preprocess_context_references(
        first, cwd=workspace, allowed_root=workspace, context_length=100_000
    ).message

    assert first.count(header) == 1
    assert first.count(marker) == 1
    assert replay.count(header) == 2
    assert replay.count(marker) == 3
    print(
        "REPRODUCED: replaying official persisted expanded text grows "
        "Attached Context headers 1 -> 2 and file-content copies 1 -> 3."
    )

    plain = "Summarize this plain prompt."
    plain_first = preprocess_context_references(
        plain, cwd=workspace, allowed_root=workspace, context_length=100_000
    ).message
    plain_replay = preprocess_context_references(
        plain_first, cwd=workspace, allowed_root=workspace, context_length=100_000
    ).message
    assert plain_first == plain_replay == plain
    assert header not in plain_replay
    print("CONTROL PASSED: replaying a prompt without an @ reference is unchanged.")
