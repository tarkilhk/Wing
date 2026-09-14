"""Seed only an explicitly supplied disposable Hermes home for emulator tests."""
import argparse
import json
import re
import time
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--home', type=Path, required=True)
parser.add_argument('--port', type=int, required=True)
args = parser.parse_args()
assert args.home.name.startswith('admin-live-')
base = f'http://127.0.0.1:{args.port}'
for attempt in range(80):
    try:
        html = urllib.request.urlopen(base, timeout=2).read().decode()
        token = re.search(r'window\.__HERMES_SESSION_TOKEN__="([^"]+)";', html).group(1)
        break
    except Exception:
        time.sleep(0.25)
else:
    raise SystemExit('Disposable Hermes did not become ready')
for name in ('admin-live-a', 'admin-live-b'):
    request = urllib.request.Request(base + '/api/profiles',
        data=json.dumps({'name': name}).encode(), method='POST',
        headers={'X-Hermes-Session-Token': token, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(request) as response:
        assert json.load(response)['name'] == name
profile = args.home / 'profiles' / 'admin-live-a'
plugin = profile / 'plugins' / 'admin-live-plugin'
plugin.mkdir(parents=True)
(plugin / 'plugin.yaml').write_text('name: admin-live-plugin\nversion: 0.0.1\ndescription: Inert emulator QA plugin\n')
(plugin / '__init__.py').write_text('def register(ctx):\n    pass\n')
memories = profile / 'memories'
memories.mkdir(exist_ok=True)
(memories / 'MEMORY.md').write_text('Admin QA retained memory.\n')
print('Prepared two disposable profiles, one inert plugin and one QA memory.')
