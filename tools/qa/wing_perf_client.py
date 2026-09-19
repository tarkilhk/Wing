"""Private local ADB tunnel to the benchmark entry point; exports no credentials."""
import json
import re
import subprocess
import urllib.parse
import urllib.request


class WingPerfClient:
    def __init__(self, serial, package="com.tarkilhk.wing.dev"):
        self.adb = ["adb", "-s", serial]
        self.port = None
        self.http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        pid = self.call("shell", "pidof", package).strip().split()[0]
        logs = self.call("logcat", "-d", "--pid=" + pid, "-s", "flutter:I")
        matches = re.findall(r"Dart VM service is listening on (http://[^\s]+)", logs)
        if not matches:
            raise RuntimeError("Benchmark VM service is not ready")
        url = urllib.parse.urlparse(matches[-1].rstrip("."))
        self.port = self.call("forward", "tcp:0", "tcp:" + str(url.port)).strip()
        self.base = "http://127.0.0.1:" + self.port + url.path
        try:
            vm = self.rpc("getVM")
            self.isolate = next(i["id"] for i in vm["isolates"] if i["name"] == "main")
        except Exception:
            self.close()
            raise

    def call(self, *words):
        return subprocess.check_output(self.adb + list(words), text=True, timeout=15)

    def rpc(self, method, **params):
        url = self.base + method + "?" + urllib.parse.urlencode(params)
        try:
            with self.http.open(url, timeout=45 if method.endswith('.refresh') else 8) as response:
                value = json.load(response)
        except Exception:
            # The VM-service URL contains an access token: never print it.
            raise RuntimeError("Benchmark RPC unavailable or timed out") from None
        if "error" in value:
            raise RuntimeError("Benchmark RPC rejected; verify Chats is open")
        return value["result"]

    def action(self, name):
        return self.rpc("ext.wingPerf." + name, isolateId=self.isolate)

    def close(self):
        if self.port:
            subprocess.run(self.adb + ["forward", "--remove", "tcp:" + self.port],
                           capture_output=True, timeout=15)
            self.port = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
