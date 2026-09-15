# Flutter setup action

Vendored from `subosito/flutter-action` at commit
`1a449444c387b1966244ae4d4f8c696479add0b2`, the revision previously used by
both Wing workflows. The upstream MIT license is preserved in `LICENSE`.

The only implementation change is pinning both nested `actions/cache@v5`
references to `caa296126883cff596d87d8935842f9db880ef25`. GitHub's policy
requiring full commit SHAs also applies to actions called by composite
actions, so the upstream tagged references prevented both workflows from
starting.

When updating this copy, review the upstream changes, preserve its license,
and pin every nested remote action before committing. Keep `setup.sh` in
sync with `action.yaml`.
