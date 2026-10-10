# Wing workspace

Before planning or editing Wing, read [the internal working instructions](internal/AGENTS.md).
The private `wing-internal` repository must be cloned into `internal/` for
engineering work. If it is missing, obtain its clone URL and access from the
project owner before proceeding. Public CI runs from the app source alone.

For commit/push requests, stage only the completed task's app changes and run
`python3 scripts/wing_save.py "<message>"`. Use `--commit-only` for local commits
and `--push-only` to retry publication. The full save and recovery workflow is in
[internal contributor instructions](internal/CONTRIBUTING.md#workspace-saves).

Keep plans, specs, architecture, research, design decisions, audit evidence and
build/testing procedures under `internal/`. Public Git contains app source,
executable checks/build configuration, user guides, release notes and legal assets.

Wing targets the latest upstream, unmodified Hermes. Integrations belong entirely
in the Android client; backend patches, forks, plugins and custom endpoints are
out of scope. Compatibility behavior requires the user's explicit approval.
