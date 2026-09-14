"""Generate synthetic test input with the installed Hermes batch producer.

Usage: python -B tools/qa/generate_process_batch_fixture.py <hermes-agent checkout>
No processes, sessions, model calls, or backend changes are made.
"""

import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(root))
from tools.process_registry_notifications import (  # noqa: E402
    ProcessNotificationBatch,
    format_process_notification,
)


class UnconsumedRegistry:
    def is_completion_consumed(self, _session_id):
        return False


events = [
    {
        "type": "completion",
        "session_id": f"proc_fixture_{index + 1}",
        "command": f"check-step {index + 1}",
        "exit_code": 1 if index == 15 else 0,
        "output": "Action needed: check failed" if index == 15 else f"Step {index + 1} passed [OK]\n\nMore output",
    }
    for index in range(16)
]
notices = [format_process_notification(event) for event in events]
fixture = {
    "source_commit": subprocess.check_output(["git", "-c", f"safe.directory={root.as_posix()}", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
    "producer": "tools/process_registry_notifications.py:ProcessNotificationBatch.render",
    "batch": ProcessNotificationBatch(tuple(zip(events, notices))).render(UnconsumedRegistry()),
    "notices": notices,
    "outputs": [event["output"] for event in events],
}
destination = Path(__file__).resolve().parents[2] / "test/fixtures/process_batch.json"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(json.dumps(fixture, indent=2) + "\n", encoding="utf-8")
print(f"Generated {len(notices)} process notices at {destination}")
