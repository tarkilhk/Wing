# Pinned stock task blueprint contract

`hermes_task_blueprints.json` contains the 16 form schemas (58 fields) inspected
on upstream main at `3a056db7b1bb66e6601e4549b4074c4f2c35f838`. Its provenance
records the source URL, source SHA-256 and canonical projection SHA-256. The
projection was extracted from `cron/blueprint_catalog.py` with bounded AST
interpretation of catalog literals and the inspected `BlueprintSlot` / `_TIME`
defaults; upstream code was not executed. The source is MIT licensed; retain
`HERMES_LICENSE.txt` with these source-derived schemas.

Refresh the pin against official upstream main before changing the protocol.
Review `blueprint_form_schema`, `fill_blueprint`, and the blueprint HTTP routes;
regenerate the form projection and its two hashes. Update the device-safe Dart
constant in `test/support/stock_task_blueprints.dart` at the same time. Host tests
verify the actual fixture response, rather than asserting source text. The Dart
constant lets native integration tests use this fixture without host files.

V03 was an invented `topic` field and 09:00 default on `morning-brief`. Stock
defines only `time` (08:00) and `deliver`. `news-digest` legitimately defines a
`topic` field. Current catalog fields all have `optional: false`; omitted values
can still use stock defaults. An explicitly empty required value is rejected.

Two independent offline checks enforce distinct properties:

- `STOCK_TASK_BLUEPRINT_SCHEMA`: a complete fixture catalog must equal the pinned
  form schemas. Its input is `{blueprints: [...]}`. Extra stock catalog rendering
  properties (schedule, command and links) are outside this property. An optional
  `delivery_targets: [id, ...]` describes the HTTP delivery-target response IDs:
  the implicit `local` is removed before constructing the form's
  `[origin, local, ...configured-platforms]` options. Platforms without a home
  channel remain valid advertised options, matching the stock route.
- `STOCK_TASK_BLUEPRINT_SLOT`: submitted slot names must belong to that stock
  blueprint. Its input is `{submissions: [{blueprint: key, values: {...}}]}`.
  Omitted slots and the legitimate `news-digest.topic` are valid. This guard
  checks names only; it does not claim to prove slot-value validation, schedule
  generation, prompt filling, delivery routing or mutation atomicity.

Each has its own command and diagnostic. Inputs may be files or stdin:

```sh
python3 tools/architecture/rules/stock_task_blueprint_schema.py --input response.json
python3 tools/architecture/rules/stock_task_blueprint_slots.py --input submissions.json
python3 tools/architecture/tests/test_task_blueprint_guards.py -v
python3 -m unittest discover -s tools/qa -p 'test_task_blueprint_guards.py' -v
flutter test --no-pub test/scheduled_tasks_blueprint_contract_test.dart
```

The synthetic cases invoke both real CLIs and require exit 1 plus the stable
diagnostic for invented fields, defaults, optional flags, slots and keys. Valid
catalogs, dynamic delivery options, defaults and real text slots must pass. Exit
2 denotes malformed input or artifact hash mismatch. The host contract test runs
these cases, then checks the fixture's actual response and captured repository
submissions; it runs in the existing complete host-test CI gate. There is no
network dependency or migration baseline.
`tools/qa/test_task_blueprint_guards.py` also runs the independent CLI fixtures
through mandatory offline-QA discovery and requires malformed inputs/artifacts
to exit 2 without a traceback. This Python gate verifies JSON rule inputs; the
host contract test separately verifies actual Dart-produced wire rows.

Local feedback contract: on Linux x86_64 / Python 3.12 with this 16-row catalog,
target at most 100 ms per independently started valid CLI. Measure cold-process
wall time and repeat five times when changing either rule; archive observations
under ignored `build/architecture-program/` following `docs/PERFORMANCE.md`.
Timing is informational and never changes a correctness result. Catalog updates
require a full check; slot-name inputs can be checked individually against the
same immutable catalog. No shared parsing or cache invalidation is required.

The fixture models schema advertisement, slot names, required defaults and
strict enums. It is a small client test fixture, not a full implementation of
stock prompt/schedule filling. Live stock acceptance remains required for those
server behaviors. Runtime/static proof of request races also remains with the
scheduled-task behavior tests.


`hermes_task_schedule_projection.json` separately pins seven schedule-response
cases from upstream `3251a180f01ad21ae059862997307bf75f3e3f0a`. It records full
source/parser/projection hashes and a fixed injected clock. The narrow independent
`STOCK_TASK_SCHEDULE_PROJECTION` rule compares actual Dart fixture POST/PUT
exports with those outputs; see the scheduled-task pilot regression contract for
its command, supported forms and behavioral limits. This property remains
separate from blueprint advertisement and slot names.
