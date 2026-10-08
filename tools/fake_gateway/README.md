# Synthetic Desktop Gateway

This local-only fixture exercises the Dashboard and Desktop Gateway contracts
used by the Android application. All sessions, credentials, prompts, files, and
responses are synthetic.

The fixture implements the retained client subset of stock Hermes; it cannot
establish real-server durability, concurrency or capability support. The removed
experimental recovery ledger, its capability advertisement and exclusive probes
are retired. Supported prompt acknowledgements use stock `status: streaming`;
unknown submit parameters fail with code 4000. The explicit disconnect selector
below is a local test control.

Contract pin for this cleanup: `44533f11e397b78f2569c41dc0eba9502304dd74`.
Inspected `tui_gateway/methods_session.py`, `methods_prompt.py`, `ws.py` and
`contracts/prompt_voice.py`, `contracts/common.py`, `contracts/base.py`.
Model-options producer was inspected at
`23a20a218dc82b005b0ea3af776604e76d6d8c4a`; model rows use string IDs with
provider `slug`/`name`. Reinspect latest stock before changing any contract.
The minimal ready payload describes only fixture skin; it advertises no
unimplemented recovery, change-event or heartbeat capability.

Small offline guards and their positive/negative CLI proofs run through the
mandatory offline QA gate:

```sh
python3 tools/architecture/rules/fixture_model_catalog.py
python3 tools/architecture/rules/retired_fixture_recovery.py
python3 -m unittest discover -s tools/qa -p 'test_architecture_fixture_guards.py' -v
```

## Run

From the repository root, using a Python environment for development dependencies:

```bash
python -m pip install -r tools/fake_gateway/requirements.txt
python tools/fake_gateway/fake_gateway.py --host 127.0.0.1 --port 18642 --api-key test-key
```

In another terminal:

```bash
python tools/fake_gateway/test_fake_gateway.py
```

## Deterministic disconnect scenarios

The fixture accepts the test-only `prompt.submit` parameter
`fixture_disconnect_scenario` with one of these exact values:

- `before_ack` closes the socket before the JSON-RPC result;
- `after_ack_before_first_delta` sends the accepted result, then closes before
  the first `message.delta`;
- `mid_stream_after_2_deltas` sends the accepted result and exactly two
  `message.delta` events, then closes.

These paths do not use timers. They never emit `turn.end` and never append a
user or assistant completion to session history. They model transport loss
only: they do not claim background continuation, recovery, replay,
idempotency, or server durability.

Loopback clients can inspect a resettable, prompt-free diagnostic ledger:

```text
GET  /test/disconnect-ledger
POST /test/disconnect-ledger/reset
```

The `hermes.fake_gateway.disconnect_ledger.v1` response contains one record per
scenario with `prompt_submit_count`, `disconnect_point`, `ack_seen`,
`delta_count`, `turn_end_count`, and `resubmit_count`. It never contains prompt
text, credentials, attachment bytes, or response content. Both diagnostic
routes reject non-loopback callers.

The fixture binds to loopback by default. Do not expose it as a real gateway or
reuse its synthetic credentials for any other service.
