# Security audit: stock report contract

Verified upstream main on 18 September 2026 through GitHub's commit API:
[`debfc7420b61a96ad97fc03b18cca74d7e72697d`](https://github.com/NousResearch/hermes-agent/commit/debfc7420b61a96ad97fc03b18cca74d7e72697d).
Pinned source files were downloaded into `/tmp/wing-security-upstream` for
read-only inspection. This design needs only Android client changes.

## Action and status

`POST /api/ops/security-audit` launches `hermes security audit` with no JSON,
severity-threshold or report options. The successful launch response contains
`ok`, `pid`, and `name`. The CLI supports JSON, but this stock HTTP operation
does not expose that option. [Operation](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/web_routers/ops.py#L500-L513),
[launch response](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/web_routers/_common.py#L65-L73).

`GET /api/actions/security-audit/status?lines=2000` returns `name`, `running`,
`exit_code`, `pid`, and `lines` (strings). Default tail length is 200; requests
are clamped to 1–2000 lines. Reading also stops at 256 KiB and drops a partial
first line. A tail therefore does not guarantee a complete report. Process
results live in memory: after a dashboard restart, `running: false` with a null
exit code can coexist with retained historical logs. Audit has no durable
receipt or structured report endpoint here.
[Status](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/web_routers/actions.py#L328-L379),
[tail limits](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/web_routers/actions.py#L49-L119).

The log is appended to, with a blank line followed by
`=== security-audit started YYYY-MM-DD HH:MM:SS ===` before each child starts.
Standard error and standard output share that file. There is no audit-specific
completion marker. Parse only the newest run when a start marker is present;
an empty new run must not inherit a previous run's results.
[Spawn/log implementation](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/web_server_gateway.py#L443-L491).

## Human report

The report renderer emits these exact header shapes:

```text
Found 21 known vulnerability finding(s) across 177 component(s):
No known vulnerabilities found across 177 component(s).
```

A findings report has a blank line, source markers such as `[venv]`,
`[plugin:NAME]`, or `[mcp:NAME]`, and finding rows:

```text
  HIGH      package==1.2.3  GHSA-example
           Optional summary
           fixed in: 2.0.0, 2.1.0
```

Severity is uppercase, padded to eight characters, with two spaces before the
package and advisory ID. Known severities are `CRITICAL`, `HIGH`, `MODERATE`,
`MEDIUM`, `LOW`, and `UNKNOWN`; `WARNING` is not an audit severity. Both summary
and fixed-version lines are optional. The summary is at most 100 characters,
using a trailing `...` when clipped; only the first three fixed versions are
printed. No URL, numeric severity, or ecosystem field is printed. There is no
finding-count truncation and no footer: every finding is rendered.
[Renderer](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/security_audit.py#L253-L283),
[severity set](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/security_audit.py#L28-L29).

Findings sort by descending severity, then source, package name, and advisory
ID. Source markers can therefore repeat as severity changes. Count each
component/advisory finding, preserving separate GHSA and PYSEC records; the
header is not a count of deduplicated underlying vulnerabilities. The component
total is the number scanned, not the number of affected packages. Discovery
covers installed Python distributions and exact pinned plugin/MCP packages;
unpinned or unsupported declarations are silently skipped.
[Discovery and ordering](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/security_audit.py#L52-L250).

## Empty results, failures, and notices

With no discovered components, the output is exactly
`No components discovered (everything skipped, or empty environment).`
and the exit code is zero. Treat this as an empty scan, not evidence that a
populated environment is healthy. A batch-query failure prints
`audit failed: OSV batch query failed: ...` and exits 2. Detail lookup failures
instead retain the finding with `UNKNOWN` severity and no title/fix data.
The report contains no warning footer.
[CLI result handling](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/security_audit.py#L286-L312),
[OSV failures](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/security_audit.py#L173-L224).

The default failure threshold is critical. Exit 0 can therefore accompany
high, moderate, low, or unknown findings; exit 1 means findings met the severity
threshold, not that the scan failed. Exit 2 denotes handled audit failure or
invalid options. The main CLI preserves that exit code.
[Threshold](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/security_audit.py#L286-L312),
[dispatch](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/main.py#L2183-L2193).

The three-line pending gateway restart warning supplied in the user's sample
is printed by CLI startup, independently of the audit report. It is operational
context, not a vulnerability or severity group. Preserve such context in
output/notice access without counting it as a finding.
[Warning formatter](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/update_cmd_fleet.py#L332-L338),
[startup call](https://github.com/NousResearch/hermes-agent/blob/debfc7420b61a96ad97fc03b18cca74d7e72697d/hermes_cli/main.py#L3465-L3473).

## Client parsing implications

- Request 2000 lines for security audit, isolate the newest run, and require a
  recognized header before deriving totals. A tail without a header must not
  imply zero findings or a complete scan.
- Compare the parsed finding count with the declared total before presenting a
  complete severity breakdown. A missing header, clipped body, or malformed
  row should yield an explicitly incomplete/unrecognized result, retaining
  access to the actual output rather than inventing counts.
- While running, keep the running state. At completion, a valid findings report
  and exit 0 or 1 means findings; exit 2 must remain an execution error.
- A new run with no report must not reuse an older completed report. A healthy
  header is positive evidence of zero known findings; an empty log is not.
- The user's sample is 21 findings across 177 scanned components: 4 high,
  6 moderate, 2 low, and 9 unknown. Show those nonempty severity cards and retain
  each package/version, advisory ID, optional title, and optional fix list.

These parsing decisions follow the pinned stock contract; they do not add
support for legacy formats or require backend changes.
