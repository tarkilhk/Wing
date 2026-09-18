# Security audit results

The task is to understand the audit's reported exposure, then inspect findings
by severity. The primary interaction opens a severity group. Counts, scope and
checked time are passive context; running and read errors are temporary status.

Two arrangements were considered:

```text
A. Count tiles                       B. Severity cards (selected)
21 vulnerabilities ...              21 vulnerabilities found
[High 4] [Moderate 6]                across 177 components
[Low 2]  [Unknown 9]                 [High                 4  >]
Long findings list below            [Moderate             6  >]
                                    [Low                  2  >]
                                    [Unknown              9  >]
                                    [Diagnostic output       >]
```

Tiles followed by a second list repeat severity labels and push details down.
One expandable card per populated severity keeps the whole audit scannable and
reveals its findings in place with one tap. All start collapsed, highest severity
first. Rows inside each card show the package/version, description, advisory ID,
component group and fixed versions when reported. Preserve each reported finding;
do not guess equivalence between GHSA and PYSEC identifiers.

Reuse Doctor's compact icon/heading/check-time arrangement and Studio AdminGroup
cards, dividers, spacing and corners. Roboto titles/body/metadata carry the report;
monospace is reserved for raw output. The palette comes from the shared theme:
navy canvas #101B24 and panel #192934 in dark mode, light canvas #F7F7F4 and white
panels, accent #65C7BC/#126D70, semantic danger/warning and muted text. Severity is
always named, never communicated by color alone. Avoid count tiles, extra charts
or an additional completion label competing with the findings. At enlarged text,
use the title-medium heading token and omit redundant severity icons to preserve
word wrapping and space for the counts without clamping the user's text scale.

Health displays the short vulnerability count. The detail heading includes the
component total; only the complete current report can supply severity counts.
The raw output stays available in Diagnostic output, collapsed by default in all
audit states, and reported audit warnings stay accessible without
being counted as vulnerabilities. No server repair or package update is implied.

Inspect both themes at phone width and 200% text, including expanded long findings,
clean results, incomplete output and refresh failures before completion.
