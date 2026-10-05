#!/usr/bin/env python3
"""Check private router discovery and actual chat completion from the WebUI guest."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def request(remote, endpoint, body=None):
    command = ["incus", "exec", remote + ":open-webui", "--project", "default", "-T", "--",
               "curl", "--fail", "--silent", "--show-error", "--connect-timeout", "15",
               "--max-time", "600", "http://garden-llama.garden.internal:8080" + endpoint]
    if body is not None:
        command += ["-H", "Content-Type: application/json", "--data-binary", "@-"]
    return json.loads(subprocess.run(command, input=None if body is None else json.dumps(body).encode(),
                                    check=True, stdout=subprocess.PIPE).stdout)


def main():
    models = json.loads((Path(__file__).resolve().parents[1] / "llama/models.lock.json").read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("remote")
    parser.add_argument("--model", choices=list(models), default="mimo")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", args.remote):
        parser.error("Invalid remote alias")
    request(args.remote, "/health")
    discovered = {item["id"] for item in request(args.remote, "/v1/models")["data"]}
    if not set(models).issubset(discovered):
        raise RuntimeError("Router did not advertise the configured models")
    result = request(args.remote, "/v1/chat/completions", {
        "model": args.model, "messages": [{"role": "user", "content": "Say hello in one short sentence."}],
        "max_tokens": 128, "stream": False, "chat_template_kwargs": {"enable_thinking": False},
    })
    message = result["choices"][0]["message"]["content"]
    if not message:
        raise RuntimeError("Completion returned no text")
    print("Private inference succeeded for " + args.model + ": " + message)


if __name__ == "__main__":
    main()
