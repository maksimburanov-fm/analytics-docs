# Analytics Docs Agent Guidance

## Greenplum MCP

- The Greenplum MCP server is named `fmedia_gp`. Treat `freedom_gp` as a human
  alias, not as a second server.
- Use the server-specific `execute_sql` tool directly. Do not begin with generic
  MCP resource discovery: `postgres-mcp` exposes tools rather than resources.
- When connectivity is uncertain, run `SELECT 1 AS test_connection;` before any
  schema exploration or analytical query.
- Keep all database work read-only. Do not run DDL, DML, transaction-control
  statements, or stored procedures with side effects.
- Keep heavy processing in SQL and return aggregated results. Do not export
  user-level identifiers or personal data.
- Diagnose MCP/Docker startup failures separately from SQL correctness and
  Greenplum query-performance problems.
- For startup and troubleshooting, follow `docs/07_mcp_connections.md`.

## Jira REST API

- Jira is available through its REST API, not through an MCP server.
- The Jira base URL is `https://project.ffin.kz`; the default project is `FMAP`.
- Read the PAT from the Windows user-level `JIRA_PAT` environment variable.
  Never print it, request it in chat, or store it in the repository.
- Before Jira work in a new chat, run `.codex\scripts\check-jira.cmd`. This
  performs GET-only authentication, project, and permission checks.
- Run `.codex\scripts\invoke-jira.ps1` through `powershell.exe` with
  `-NoProfile -NonInteractive -ExecutionPolicy Bypass -File`. The script
  restricts requests to the configured Jira host and requires `-AllowWrite`
  for `POST`, `PUT`, and `DELETE`. Do not route Jira URLs through a `.cmd`
  wrapper because `&` in query strings can be corrupted by `cmd.exe`.
- For inspection and reporting requests, use GET-only calls.
- Create, update, transition, comment on, or delete Jira issues only when the
  user explicitly requests that external change. Resolve the exact issue key
  and inspect create/edit metadata before writing.
- Treat deletion as destructive: verify the exact issue key and do not infer a
  delete request from words such as "close", "cancel", or "remove from board".
- After a write, read the affected issue and report the resulting key/status.
- Follow `docs/08_jira_api.md` for endpoints, examples, and troubleshooting.
