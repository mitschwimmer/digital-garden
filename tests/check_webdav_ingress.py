"""Exercise Nix-generated WebDAV routes with the pinned native Caddy.

Usage: check_webdav_ingress.py CADDY DENY_ALL_ROUTE LAN_ROUTE
LAN_ROUTE must allow 127.0.0.2/32. No credentials or public ACME calls are used.
"""

import http.client
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Backend(BaseHTTPRequestHandler):
    calls = []

    def handle_request(self):
        self.calls.append((self.command, self.path))
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *_):
        pass


METHODS = "GET HEAD OPTIONS PROPFIND PUT DELETE MKCOL MOVE COPY LOCK UNLOCK PATCH".split()
for method in METHODS:
    setattr(Backend, "do_" + method, Backend.handle_request)


def request(port, source, method="GET", path="/", headers=None, address="127.0.0.1"):
    connection = http.client.HTTPConnection(address, port, timeout=3, source_address=(source, 0))
    try:
        connection.request(method, path, headers={"Host": "webdav.archaic.work", **(headers or {})})
        response = connection.getresponse()
        response.read()
        return response.status
    finally:
        connection.close()


def check(caddy, route, allowed, backend, directory):
    # Adapt the actual Nix-generated site, then disable only transport-level TLS
    # and replace its backend dial address for an offline HTTP routing test.
    # Matchers, handler order, paths and methods are left unchanged.
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    caddyfile = directory / "Caddyfile"
    caddyfile.write_text("{\n admin off\n persist_config off\n}\n" +
                         f"webdav.archaic.work:{port} {{\n" + route.read_text() + "\n}\n")
    adapted = subprocess.run([caddy, "adapt", "--config", str(caddyfile), "--adapter", "caddyfile"],
                             check=True, capture_output=True, text=True)
    config = json.loads(adapted.stdout)
    config["apps"].pop("tls", None)
    ipv6 = False
    try:
        with socket.socket(socket.AF_INET6) as probe:
            probe.bind(("::1", 0))
            ipv6 = True
    except OSError:
        pass
    for server in config["apps"]["http"]["servers"].values():
        server["listen"] = [f"127.0.0.1:{port}"] + ([f"[::1]:{port}"] if ipv6 else [])
        server.pop("tls_connection_policies", None)
        server["automatic_https"] = {"disable": True}
    serialized = json.dumps(config).replace("webdav.garden.internal:6065", f"127.0.0.1:{backend.server_port}")
    config_path = directory / "caddy.json"
    config_path.write_text(serialized)
    with (directory / "caddy.log").open("w+") as log:
        process = subprocess.Popen([caddy, "run", "--config", str(config_path)], stdout=log, stderr=log,
                                   env={**os.environ, "XDG_DATA_HOME": str(directory / "data"),
                                        "XDG_CONFIG_HOME": str(directory / "config")})
        try:
            deadline = time.monotonic() + 10
            while True:
                try:
                    assert request(port, "127.0.0.1") == 403
                    break
                except (OSError, http.client.HTTPException):
                    if process.poll() is not None or time.monotonic() >= deadline:
                        log.seek(0)
                        raise RuntimeError(log.read())
                    time.sleep(0.05)
            before = len(Backend.calls)
            spoofed = {"X-Forwarded-For": "127.0.0.2", "X-Real-IP": "127.0.0.2",
                       "Forwarded": "for=127.0.0.2"}
            for method in METHODS:
                assert request(port, "127.0.0.1", method, "/vault", spoofed) == 403, method
            for path in ["/", "/enpass/", "/%2e%2e/vault", "/vault?x=1",
                         "/.well-known/acme-challenge/not-an-active-token"]:
                assert request(port, "127.0.0.1", path=path, headers=spoofed) == 403, path
            if ipv6:
                assert request(port, "::1", headers=spoofed, address="::1") == 403
            assert len(Backend.calls) == before, "Denied request reached backend"
            for method in METHODS:
                expected = 204 if allowed else 403
                assert request(port, "127.0.0.2", method, "/vault") == expected, method
            assert len(Backend.calls) - before == (len(METHODS) if allowed else 0)
            print(f"{'LAN allowlist' if allowed else 'Empty allowlist'}: passed; IPv6 {'checked' if ipv6 else 'unavailable'}")
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def main():
    caddy, deny_route, lan_route = sys.argv[1:]
    backend = ThreadingHTTPServer(("127.0.0.1", 0), Backend)
    worker = threading.Thread(target=backend.serve_forever, daemon=True)
    worker.start()
    try:
        for route, allowed in [(deny_route, False), (lan_route, True)]:
            with tempfile.TemporaryDirectory() as directory:
                check(caddy, Path(route), allowed, backend, Path(directory))
    finally:
        backend.shutdown()
        backend.server_close()
        worker.join()


if __name__ == "__main__":
    main()
