---
name: agent-vault-cli
description: Request API access through Agent Vault when a proxied request fails with 401 or 403. Use placeholder API credentials; the proxy injects approved secrets. Includes the Pi sandbox proposal workflow for Agent Vault v0.40.0.
---

# Request API access

Make requests to the real upstream URL using clients that honor HTTP_PROXY and
HTTPS_PROXY. Use an existing placeholder or a dummy API key; the proxy replaces
it for configured services. Do not proactively discover access before trying the
request. On 401/403, confirm the endpoint and authentication scheme, then request
access through a proposal.

Use the environment supplied by `garden-agent`: AGENT_VAULT_TOKEN is the existing
vault-scoped proxy session, AGENT_VAULT_ADDR is the remote API on the isolated
link, and AGENT_VAULT_VAULT selects pi-agent. No local vault server or operator
login is needed. Never start a server, run auth login, request a human password,
read credentials, or use the vault token as an upstream API key.

Create a proposal with credential descriptions, never actual secret values:

```bash
agent-vault vault proposal create \
  --name mistral --host 'api.mistral.ai:443/v1/libraries*' \
  --auth-type bearer --token-key MISTRAL_API_KEY \
  --credential 'MISTRAL_API_KEY=Mistral Libraries API key' \
  -m 'Upload documents and poll library indexing status' --json
```

Choose the narrowest host, port and path matching the requests actually made.
For API-key headers use `--auth-type api-key --api-key-key KEY
--api-key-header HEADER`; for Basic use `--auth-type basic --username-key KEY
--password-key KEY`. Use `-f FILE` for complex JSON proposals. Inspect `--help`
for other supported flags.

Show the proposal ID and approval URL. Explain that the operator reviews and
supplies secrets locally in the vault guest; its loopback URL is not a public
dashboard. The operator can run `agent-vault vault proposal approve --vault
pi-agent NUMBER` there. Do not approve your own proposal.

Poll the scoped HTTP endpoint below: v0.40.0 has no `proposal get --json`, and
`proposal show`/`list` require a saved operator session. Replace NUMBER with the
returned integer ID. This reads the token from the environment without putting
it in command arguments:

```bash
python3 - NUMBER <<'PY'
import json
import os
import sys
import urllib.request

proposal_id = int(sys.argv[1])
request = urllib.request.Request(
    os.environ['AGENT_VAULT_ADDR'] + '/v1/proposals/' + str(proposal_id),
    headers={'Authorization': 'Bearer ' + os.environ['AGENT_VAULT_TOKEN'],
             'X-Vault': os.environ['AGENT_VAULT_VAULT']})
with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(
        request, timeout=10) as response:
    result = json.load(response)
print(json.dumps({'id': result['id'], 'status': result['status']}))
PY
```

Poll every 3 seconds for 30 seconds, then every 10 seconds, stopping after ten
minutes or on rejected/expired. On applied, retry the original request. For
OAuth connection errors, ask the operator to complete the connection instead of
retrying indefinitely.

If the three environment variables are absent, restart through `garden-agent`.
If the vault API times out, report a sandbox deployment/connectivity problem.
For an invalid/expired vault session, request operator token rotation. Never
print the token, proxy URLs containing it, or the complete environment.

Keep upstream service URLs in application configuration; HTTP_PROXY is the
forward proxy. Do not replace an upstream base URL with the forward proxy URL.
Keep credentials out of source, logs, process arguments and generated files.
