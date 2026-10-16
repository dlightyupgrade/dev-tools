# servicing-triage-ui

Local triage board for the servicing support agent. It runs the `failure_triage` tool through headless Claude Code, turns the text output into findings, links each finding to Sumo Logic monitor definitions, and can start an investigation or open one in an interactive Claude Code session.

## Run

```
python3 -m servicing_triage_ui --open          # http://127.0.0.1:4177
python3 -m servicing_triage_ui sync-monitors   # refresh the Sumo monitor index
python3 -m servicing_triage_ui import FILE     # load a saved failure_triage output
```

Options: `--port`, `--sumo-config`, `--cwd` (directory the Claude Code session starts in, default `~/code`).
Env: `TRIAGE_UI_HOME` (default `~/.servicing-triage-ui`), `TRIAGE_UI_TIMEOUT_SECONDS` (900), `TRIAGE_UI_MAX_BUDGET_USD` (1.0 per run), `TRIAGE_UI_DRY_RUN=1` (record launches without opening a terminal).

Needs the `claude` CLI signed in with the servicing-plugin MCP server.

## What it does

- **Refresh** runs `failure_triage` headless (about 4 minutes, about $0.36 for one day).
- **Investigate** runs a read-only headless session for one finding (about 6 minutes, about $0.54). The result is shown as model output, not a verified finding, and can be continued in Claude Code.
- **Open in Claude Code** opens iTerm2 or Terminal with a prompt built server-side from the finding.
- **Known issues** are stored locally (state, note, ticket key).
- **Sumo monitors** come from a shallow clone of Credify/sumologic-config. Only monitor definitions are matched, not fired alerts.

## Security

Binds 127.0.0.1 only; Host header allowlist; POSTs need `application/json`, a per-process token and a matching Origin; no CORS; launches take a finding id and never a client prompt; headless runs use a read-only tool allowlist; every action is appended to `audit.jsonl`.

The data directory holds finding ids, amounts, error text and loan account numbers taken from the service output. It is not encrypted.

## Limits

The parser reads the service's text format and breaks if that format changes. A `json` output format on `failure_triage` would replace it.
