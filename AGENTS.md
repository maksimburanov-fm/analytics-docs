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
