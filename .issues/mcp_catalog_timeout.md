# Bug: Finch Connection Timeout in MCP Catalog Fetching

## Description
When fetching the MCP catalog, the system encounters `RuntimeError` from Finch due to connection timeouts caused by excess queuing. This indicates that the HTTP pool is saturated, likely because of a high volume of concurrent requests to fetch individual catalog entries.

## Error Message
```
** (RuntimeError) Finch was unable to provide a connection within the timeout due to excess queuing for connections. Consider adjusting the pool size, count, timeout or reducing the rate of requests if it is possible that the downstream service is unable to keep up with the current rate.
```

## Stack Trace Snippet
```
    (nimble_pool 1.1.0) lib/nimble_pool.ex:518: NimblePool.exit!/3
    (finch 0.20.0) lib/finch/http1/pool.ex:63: Finch.HTTP1.Pool.request/6
    (squads 0.1.0) lib/squads/mcp/catalog.ex:161: Squads.MCP.Catalog.fetch_yaml/1
    (squads 0.1.0) lib/squads/mcp/catalog.ex:114: Squads.MCP.Catalog.fetch_server_entry/1
```

## Context
The error occurs in `Squads.MCP.Catalog.fetch_server_entry/1` which calls `fetch_yaml/1`. It appears multiple tasks are spawned concurrently to fetch different MCP server entries (e.g., `amazon-kendra-index`, `ais-fleet`, `airtable-mcp-server`), overwhelming the Finch connection pool.

## Proposed Resolution/Investigation
- **Increase Pool Size:** Adjust the Finch pool configuration in the application supervision tree to allow more concurrent connections.
- **Throttling/Concurrency Control:** Limit the number of concurrent tasks spawned by `Squads.MCP.Catalog` when fetching the catalog (e.g., using `Task.async_stream` with a `max_concurrency` limit).
- **Retry Mechanism:** Implement a backoff and retry strategy for failed requests.
- **Connection Timeout:** Increase the connection timeout settings for the Finch pool or the specific `Req` requests.
