# MT5 AI Agent Integrations

> **Full Architecture & Concepts Reference:** [`reference/MT5_AI_AGENT_CONCEPTS.md`](../../reference/MT5_AI_AGENT_CONCEPTS.md)

This directory contains two standalone ways to connect AI agents and LLMs to MetaTrader 5 (MT5): **MCP** and **ZeroMQ**.

| Folder | Transport | Best For | Docs |
| :--- | :--- | :--- | :--- |
| `mcp/` | **MCP** (`MCPServer` + `MetaTrader5` Python IPC) | Claude Desktop, Cursor, and MCP-compatible AI clients | [`mcp/README.md`](mcp/README.md) |
| `zeromq/` | **ZeroMQ** (`zmq_server.py` + `zmq_client.py`) | Low-latency `REQ/REP` commands and `PUB/SUB` tick streaming | [`zeromq/README.md`](zeromq/README.md) |
| `mql5-bridge/` | **MQL5 EA / Script** (`CopyBuffer` → HTTP/Socket/File) | Custom `.ex5` indicator buffers, chart state, and `OnTick` events | [`mql5-bridge/README.md`](mql5-bridge/README.md) |

---

## Python Environment (`.venv`)

Use the repository-root `.venv` for running and testing both `mcp/` and `zeromq/`:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r mt5\ai-agent\mcp\requirements.txt
.\.venv\Scripts\python.exe -m pip install -r mt5\ai-agent\zeromq\requirements.txt
```

Run the MCP unit tests from `mt5\ai-agent\mcp`:

```powershell
cd mt5\ai-agent\mcp
..\..\..\.venv\Scripts\python.exe -m pytest tests
```

> **Note:** Both `mcp/` and `zeromq/` use the official `MetaTrader5` Python package over Windows local IPC and require a running **MetaTrader 5** desktop terminal (they do **not** support MT4).

---

## Core Concepts

### 1. Why a Bridge Is Needed
MetaTrader 5 is a Windows desktop terminal whose native MQL5 code runs inside the terminal's sandboxed event loop, while AI agents and LLMs run in external clients, Python processes, or remote servers. A bridge defines **how market/account data leaves MT5** and **how trading instructions return safely**.

### 2. Model Context Protocol (MCP) — `mcp/`
MCP is an open client-server protocol that lets an AI client discover and invoke structured capabilities exposed by a server:
* **Resources:** Read-only context URIs (e.g., `mt5://account/summary`, `mt5://positions/open`).
* **Tools:** Typed functions the model can call dynamically (e.g., `get_symbol_tick`, `get_rates`, `place_market_order`, `close_position`).
* **Prompts:** Reusable workflow templates (e.g., `risk_audit_prompt`).

In `mcp/`, the Python server communicates with the running MT5 terminal over local IPC using the official `MetaTrader5` package and exposes these primitives to AI clients over `stdio`.

### 3. ZeroMQ Sockets (`ZMQ`) — `zeromq/`
ZeroMQ is an asynchronous, brokerless messaging library designed for low-latency, event-driven pipelines:
* **`REQ / REP` (Request–Reply):** Synchronous JSON command channel (`tcp://127.0.0.1:5555`). The Python client (`zmq_client.py`) sends a command (`PING`, `ACCOUNT_INFO`, `TICK`, `POSITIONS`, `ORDER_SEND`, `CLOSE_POSITION`) and receives a structured JSON response from `zmq_server.py` (which talks to MT5 via `MetaTrader5` IPC).
* **`PUB / SUB` (Publish–Subscribe):** Asynchronous one-way stream (`tcp://127.0.0.1:5556`). `zmq_server.py` publishes live ticks for configured symbols so external or remote Python agents can react without polling MT5 directly.

### 4. Choosing Between `mcp/` and `zeromq/`

| Aspect | `mcp/` | `zeromq/` |
| :--- | :--- | :--- |
| **Primary Consumer** | Interactive AI clients (Claude, Cursor, etc.) | Custom Python event loops, remote/Linux/Docker agents |
| **Communication Style** | Tool/resource discovery over `stdio` | `REQ/REP` commands + `PUB/SUB` tick stream |
| **Latency** | Moderate (request/response + LLM turn) | Low (binary socket framing, minimal overhead) |
| **MT5 Requirement** | Official `MetaTrader5` Python package (Windows) | `zmq_server.py` on Windows + `MetaTrader5` package |

### 5. Safety Guardrails
* **Dry-Run by Default:** Both implementations default to blocking live/demo order execution (`MT5_ALLOW_LIVE_TRADING=false`) until explicitly enabled.
* **Deterministic Risk Limits:** Volume caps (`MAX_LOT_SIZE` / `InpMaxLotSize`) and pre-trade checks (`order_check`) are enforced in code rather than relying on LLM prompts.
* **Demo First:** Always verify connectivity, serialization, and error handling on a demo account before touching live capital.
