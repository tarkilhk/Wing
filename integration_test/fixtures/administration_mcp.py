"""Disposable stdio MCP service used by the real Hermes admin acceptance run."""
import json
import sys

# Real stdio JSON-RPC service with no packages, files, network or credentials.
for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    method = request["method"]
    if method == "initialize":
        result = {"protocolVersion": request["params"]["protocolVersion"],
                  "capabilities": {"tools": {}, "prompts": {}, "resources": {}},
                  "serverInfo": {"name": "Administration QA", "version": "1.0"}}
    elif method == "tools/list":
        result = {"tools": [{"name": "admin_echo", "description": "Return a QA message",
                             "inputSchema": {"type": "object", "properties": {
                                 "message": {"type": "string"}}}}]}
    elif method == "tools/call":
        result = {"content": [{"type": "text", "text": request["params"]["arguments"]["message"]}]}
    elif method == "prompts/list":
        result = {"prompts": [{"name": "admin_prompt", "description": "QA prompt"}]}
    elif method == "resources/list":
        result = {"resources": [{"uri": "qa://administration", "name": "QA resource"}]}
    else:
        result = {}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
