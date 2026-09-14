"""Read-only administration contract probe; outputs shapes, never private values.

Uses the same loopback dashboard token flow as DashboardClient. Does not invoke
mutations, model inference, OAuth, tool setup, MCP probes or maintenance actions.
"""
import argparse
import datetime
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--port', type=int, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
base = f'http://127.0.0.1:{args.port}'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
with opener.open(base + '/', timeout=15) as response:
    html = response.read().decode('utf-8')
match = re.search(r'window\.__HERMES_SESSION_TOKEN__="([^"]+)";', html)
if not match:
    raise SystemExit('Local dashboard token flow unavailable; no credentials printed.')
headers = {'X-Hermes-Session-Token': match.group(1)}
del html, match

def read(path, query=None):
    started = time.monotonic()
    url = base + '/api/' + path
    if query:
        url += '?' + urllib.parse.urlencode(query)
    request = urllib.request.Request(url, headers=headers, method='GET')
    try:
        with opener.open(request, timeout=40) as response:
            payload = json.load(response)
            return response.status, payload, round(time.monotonic() - started, 3)
    except urllib.error.HTTPError as error:
        return error.code, None, round(time.monotonic() - started, 3)
    except Exception as error:
        return type(error).__name__, None, round(time.monotonic() - started, 3)

def shape(value):
    if isinstance(value, dict):
        result = {'kind': 'object', 'keys': sorted(value)}
        result['arrays'] = {key: {'count': len(val), 'item_keys': sorted(val[0]) if val and isinstance(val[0], dict) else []}
                            for key, val in value.items() if isinstance(val, list)}
        return result
    if isinstance(value, list):
        return {'kind': 'array', 'count': len(value), 'item_keys': sorted(value[0]) if value and isinstance(value[0], dict) else []}
    return {'kind': type(value).__name__}

records = []
def probe(path, query=None):
    status, payload, elapsed = read(path, query)
    record = {'method': 'GET', 'path': '/api/' + path, 'query': query or {}, 'status': status, 'seconds': elapsed}
    if payload is not None:
        record['shape'] = shape(payload)
    records.append(record)
    print(json.dumps(record), flush=True)
    return payload

discovery = probe('profiles')
rows = discovery if isinstance(discovery, list) else (discovery or {}).get('profiles', [])
names = {row.get('name') for row in rows if isinstance(row, dict)}
targets = [name for name in ('default', 'android-qa-a', 'android-qa-b') if name in names]
probe('profiles/active')
for profile in targets:
    for endpoint in ('model/info', 'model/auxiliary', 'config/schema', 'skills', 'tools/toolsets', 'mcp/servers', 'learning/graph'):
        payload = probe(endpoint, {'profile': profile})
        if endpoint == 'config/schema' and isinstance(payload, dict):
            fields = payload.get('fields', {})
            records[-1]['schema_fields'] = [
                {'key': key, **{k: field[k] for k in ('type', 'category', 'options', 'min', 'max') if k in field}}
                for key, field in fields.items() if isinstance(field, dict)
            ] if isinstance(fields, dict) else []
    probe('config', {'profile': profile, 'include_defaults': 'false'})
    probe('analytics/usage', {'profile': profile, 'days': 7})
    probe('analytics/models', {'profile': profile, 'days': 7})
for endpoint in ('model/info', 'config', 'skills', 'tools/toolsets', 'mcp/servers', 'analytics/usage', 'learning/graph'):
    probe(endpoint, {'profile': 'android-admin-audit-missing-20260914'})
report = {'timestamp_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'base_url': base, 'profiles_checked': targets, 'records': records,
          'limits': 'Read responses only. No write isolation or runtime adoption is claimed. Only shapes, counts and public schema definitions retained; no configuration values, tokens, secrets, skill instructions, memories, SOUL, logs or transcripts retained.'}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
print(f'Saved {len(records)} sanitized observations.')
