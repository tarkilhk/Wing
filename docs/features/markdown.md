# Read and copy formatted content

Read partial and completed replies, code and tool output; select or copy exact content while asynchronous rendering keeps newer content authoritative.

Feature ID: `markdown`.

## Sub-features

- `markdown.render` — Read partial and completed formatted content.
- `markdown.copy` — Select or copy exact code and output.
- `markdown.reuse` — Retain current content through asynchronous rendering.

## How to get to it (user POV)

Read a streamed reply, saved answer, Activity result or supported file preview. Open code actions to copy exact text, wrap lines or inspect a full view.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/markdown_inline_parser_test.dart test/markdown_segment_correctness_test.dart test/markdown_parse_worker_test.dart
  ```

- **Android `recents-code`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py recents-code --output build/feature-verification/markdown
  ```

- **Android `html`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py html --output build/feature-verification/markdown
  ```

## Gotchas

Partial streams can be plain until completion. Unsupported syntax must remain readable. A parser test alone does not prove Android selection or a WebView render.
