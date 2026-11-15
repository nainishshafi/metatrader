# MetaTrader 5 MCP Server

> **Main Concepts:** See [`reference/MT5_AI_AGENT_CONCEPTS.md`](../../../reference/MT5_AI_AGENT_CONCEPTS.md) for the architectural overview and comparison of MT5 AI integration patterns.

A standalone **Model Context Protocol (MCP)** server built with `MCPServer` (`mcp>=2.0.0`) and the official `MetaTrader5` Python package. It exposes MT5 account state, market data, and guarded order execution to any MCP-compatible AI client over `stdio`.

---

## Files

```text
mt5/ai-agent/mcp/
├── README.md
├── requirements.txt
└── mcp_server.py
```

---

## Setup

Requires **Windows**, **Python 3.10+**, and a running **MetaTrader 5** terminal.

From the repository root, create and activate the shared `.venv`:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
.\.venv\Scripts\python.exe -m pip install -r mt5\ai-agent\mcp\requirements.txt
```

Run tests (from `mt5\ai-agent\mcp`):
```powershell
..\..\..\.venv\Scripts\python.exe -m pytest tests
```

> **Note:** `mcp_server.py` uses the official `MetaTrader5` Python package over Windows local IPC and requires a running **MetaTrader 5** desktop terminal (it does **not** support MT4).

---

## Running Independently (Without Claude Desktop or Cursor)

By default, `mcp.run()` in `mcp_server.py` uses **`stdio` transport** (waiting for JSON-RPC messages on `stdin`). To use it without Claude Desktop or Cursor:

* **Standalone HTTP server:** Change `mcp.run()` at the bottom of `mcp_server.py` to `mcp.run(transport="streamable-http")` (or `"sse"`), then run:
  ```powershell
  .\.venv\Scripts\python.exe mt5\ai-agent\mcp\mcp_server.py
  ```
* **Programmatic Python client (`stdio`):** Keep `mcp_server.py` unchanged and spawn it from your own Python script using `mcp.client.stdio.stdio_client` and `mcp.ClientSession`:
  ```python
  import asyncio
  from mcp import ClientSession, StdioServerParameters
  from mcp.client.stdio import stdio_client

  async def main():
      server = StdioServerParameters(
          command=r".venv\Scripts\python.exe",
          args=["mt5/ai-agent/mcp/mcp_server.py"],
      )
      async with stdio_client(server) as (read, write):
          async with ClientSession(read, write) as session:
              await session.initialize()
              print(await session.call_tool("get_account_info", {}))

  asyncio.run(main())
  ```

---

## Client Configuration

Add the server to your MCP client configuration (e.g., Claude Desktop, Cursor):

```json
{
  "mcpServers": {
    "mt5-mcp-server": {
      "command": ".venv\\Scripts\\python.exe",
      "args": ["mt5/ai-agent/mcp/mcp_server.py"],
      "env": {
        "MT5_MAX_LOT_SIZE": "0.10",
        "MT5_ALLOW_LIVE_TRADING": "false"
      }
    }
  }
}
```

---

## Exposed MCP Primitives

* **Resources:**
  * `mt5://account/summary` — Account balance, equity, margin, and leverage.
  * `mt5://positions/open` — Currently open positions.
* **Tools:**
  * `get_account_info()`
  * `get_symbol_tick(symbol)`
  * `get_rates(symbol, timeframe, count)`
  * `get_open_positions(symbol=None)`
  * `place_market_order(symbol, side, volume, sl=0.0, tp=0.0, comment="MCP-Agent")`
  * `close_position(ticket)`
* **Prompts:**
  * `risk_audit_prompt(max_risk_percent=2.0)`

---

## Environment Variables & Guardrails

`mcp_server.py` automatically loads `mt5/ai-agent/mcp/.env` (copy `.env.example` to `.env` if needed; `.env` is gitignored):

| Variable | Default | Description |
| :--- | :--- | :--- |
| `MT5_DEFAULT_MAGIC` | `202611` | Magic number attached to orders |
| `MT5_MAX_LOT_SIZE` | `1.0` | Hard cap on order volume |
| `MT5_DEFAULT_DEVIATION` | `20` | Max slippage in points |
| `MT5_ALLOW_LIVE_TRADING` | `false` | Must be `true` to execute orders (otherwise runs `order_check` dry-run only) |

Always test on a **demo account** before enabling `MT5_ALLOW_LIVE_TRADING=true`.
