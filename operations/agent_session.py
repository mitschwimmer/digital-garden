#!/usr/bin/env python3
"""Launch Pi or a development shell with a staged proxy-only vault session.

Unlike upstream `vault run`, this never fetches and trusts a CA at runtime.
The reviewed CA is installed in the NixOS system trust bundle.
"""
import json
import os
from pathlib import Path
import re
import stat
import sys
from urllib.parse import quote


def session_environment(config, environ, *, allow_missing_token=False):
    # Keep local store/activation operations available before session enrollment.
    # The daemon has no authenticated proxy in this state; host ACLs deny egress.
    if allow_missing_token and not Path(config["tokenFile"]).exists():
        return dict(environ)
    if not config["caReady"]:
        raise ValueError("Install the reviewed vault ca.pem and redeploy Pi before starting a session")
    token_path = Path(config["tokenFile"])
    with token_path.open() as token_file:
        mode = os.fstat(token_file.fileno()).st_mode
        if not stat.S_ISREG(mode) or mode & 0o007:
            raise ValueError("Session token must be a regular file without access for other users")
        token = token_file.read().strip()
    if not re.fullmatch(r"av_sess_[A-Za-z0-9_-]+", token):
        raise ValueError("Stage a vault-scoped session token in av_sess format")
    if not Path(config["caBundle"]).is_file():
        raise ValueError("System CA bundle is unavailable")
    proxy = (f'http://{quote(token, safe="")}:{quote(config["vault"], safe="")}@'
             f'{config["proxyHost"]}:{config["proxyPort"]}')
    env = dict(environ)
    # Overwrite both cases: libcurl and other subprocesses differ in precedence.
    for name in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY"):
        env[name] = env[name.lower()] = proxy
    env["NO_PROXY"] = env["no_proxy"] = "localhost,127.0.0.1"
    for name in ("SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS", "REQUESTS_CA_BUNDLE",
                 "CURL_CA_BUNDLE", "GIT_SSL_CAINFO", "DENO_CERT", "NPM_CONFIG_CAFILE",
                 "NIX_SSL_CERT_FILE"):
        env[name] = config["caBundle"]
    env["NODE_USE_ENV_PROXY"] = "1"
    env["NPM_CONFIG_PROXY"] = env["NPM_CONFIG_HTTPS_PROXY"] = proxy
    # gh requires a nonempty token locally; the proxy replaces this placeholder.
    env["GH_TOKEN"] = "__github_pat__"
    env["GIT_TERMINAL_PROMPT"] = "0"
    return env


def main():
    config_file, pi_binary, *arguments = sys.argv[1:]
    config = json.loads(Path(config_file).read_text())
    allow_missing = arguments[:1] == ["--allow-missing-session"]
    if allow_missing:
        arguments = arguments[1:]
    env = session_environment(config, os.environ, allow_missing_token=allow_missing)
    command = arguments[1:] if arguments[:1] == ["--"] else [pi_binary, *arguments]
    command = command or [pi_binary]
    os.execvpe(command[0], command, env)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        # Never print config, proxy URL, token contents, or child environment.
        print(f"garden-agent: {error}", file=sys.stderr)
        sys.exit(1)
