# Authored file census

`ARCH_AUTHORED_CENSUS` prevents a stale scope inventory from silently omitting
files added during feature migration or retaining physically removed files.
It compares `tools/architecture/roots.json:files` with the actual application
Git checkout: present tracked files and intentional untracked files visible to
Git. A tracked deletion is absent; a symlink itself remains an authored input.
Duplicate entries are violations. Paths must be canonical and checkout-relative.

The fixed exclusions are root `.git`, `build`, `.dart_tool`, and nested installed
`node_modules`/Python cache directories. A manifest cannot broaden them. A nested
authored directory named `build` is legitimate. Git's existing ignore rules
identify local installed/generated output; this guard cannot prove that an
incorrect ignore rule has not hidden an intended source file.

Run independently from the actual checkout, using the existing Python and Git:

```sh
python3 tools/architecture/rules/authored_census.py
python3 -m unittest tools.qa.test_authored_census -v
```

Exit 0 means file-set coverage; exit 1 means a missing, stale or duplicate census
entry; exit 2 means malformed input or an unavailable/non-root Git checkout.
Diagnostics are deterministically ordered and name the manifest location and
affected path. Updating the census is a reviewed action; the check never edits it.
Its independent fixtures exercise the actual CLI for all three outcomes, tracked
deletion, untracked additions, ignored outputs, symlinks, traversal and a nested
checkout path. Offline QA discovers the fixtures. Both workflows explicitly run
the production check, and `REQUIRED_QUALITY_GATE` rejects omission, conditional
execution or swallowed failures.

This property does **not** prove executable-root completeness, declaration
liveness, direct-dependency use or safe removal. Those remain separate resolved
caller and dynamic-root obligations in the deletion inventory. No source search
or matching file count closes them.

Local feedback budget: 250 milliseconds for the complete production CLI on the
recorded host/Python/Git/input census. Measure cold startup and three warm runs
after fixture correctness, and retain exact input hashes and measurements under
ignored `build/architecture-program/` according to `docs/PERFORMANCE.md`. CI uses
the deterministic correctness result, never timing as a condition.
