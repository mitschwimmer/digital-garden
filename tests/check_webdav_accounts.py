"""Check authentication and per-user file roots with native WebDAV.

Usage: check_webdav_accounts.py WEBDAV NIX_SETTINGS_JSON
Only bind address, port and filesystem paths are replaced for the test.
Uses ephemeral synthetic passwords, never real SOPS inputs.
"""

import base64
import http.client
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time


ACCOUNTS = ("henner", "claudi", "elmo")


def request(port, method, path, username=None, password=None, body=None):
    headers = {}
    if username is not None:
        token = base64.b64encode(f"{username}:{password}".encode()).decode()
        headers["Authorization"] = "Basic " + token
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    try:
        connection.request(method, path, body=body, headers=headers)
        response = connection.getresponse()
        return response.status, response.read()
    finally:
        connection.close()


def main():
    binary, settings_path = sys.argv[1:]
    settings = json.loads(Path(settings_path).read_text())
    assert settings["permissions"] == "none"
    assert [user["username"] for user in settings["users"]] == list(ACCOUNTS)
    passwords = {name: secrets.token_hex(32) for name in ACCOUNTS}
    environment = os.environ.copy()
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        settings.update(address="127.0.0.1", port=port, directory=str(directory / "data"))
        (directory / "data").mkdir()
        for user in settings["users"]:
            name = user["username"]
            assert user["directory"] == f"/var/lib/webdav/{name}"
            assert user["password"] == f"{{env}}WEBDAV_{name.upper()}_PASSWORD"
            environment[f"WEBDAV_{name.upper()}_PASSWORD"] = passwords[name]
            root = directory / "data" / name
            root.mkdir()
            user["directory"] = str(root)
        configuration = directory / "settings.json"
        configuration.write_text(json.dumps(settings))
        with (directory / "webdav.log").open("w+") as log:
            process = subprocess.Popen([binary, "-c", str(configuration)], env=environment,
                                       stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while True:
                    try:
                        assert request(port, "GET", "/")[0] == 401
                        break
                    except (OSError, http.client.HTTPException):
                        if process.poll() is not None or time.monotonic() >= deadline:
                            log.seek(0)
                            raise RuntimeError(log.read())
                        time.sleep(0.05)
                for name in ACCOUNTS:
                    assert request(port, "PUT", "/marker", name, passwords[name], name.encode())[0] == 201
                assert request(port, "PUT", "/anonymous", body=b"fixture")[0] == 401
                for name in ACCOUNTS:
                    assert request(port, "GET", "/marker", name, passwords[name]) == (200, name.encode())
                    for other in ACCOUNTS:
                        if other == name:
                            continue
                        assert request(port, "GET", "/marker", name, passwords[other])[0] == 401
                        for path in [f"/{other}/marker", f"/../{other}/marker",
                                     f"/%2e%2e/{other}/marker"]:
                            assert request(port, "GET", path, name, passwords[name])[0] in (400, 403, 404)
                for name in ACCOUNTS:
                    assert request(port, "GET", "/marker", name, passwords[name]) == (200, name.encode())
                    updated = name.encode() + b"-updated"
                    assert request(port, "PUT", "/marker", name, passwords[name], updated)[0] in (201, 204)
                    assert request(port, "GET", "/marker", name, passwords[name]) == (200, updated)
                    assert request(port, "DELETE", "/marker", name, passwords[name])[0] == 204
                print("Three WebDAV accounts: authentication, independent CRUD and directory isolation passed")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()
