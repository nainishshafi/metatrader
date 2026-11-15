# MetaTrader 5 ZeroMQ Socket Bridge (Pure Python)

> **Main Concepts:** See [`reference/MT5_AI_AGENT_CONCEPTS.md`](../../../reference/MT5_AI_AGENT_CONCEPTS.md) for the architectural overview and comparison of MT5 AI integration patterns.

Pure-Python **ZeroMQ (`ZMQ`)** server and client bridging MetaTrader 5 (`MetaTrader5` Python IPC) to external or remote AI agents—with no `.mq5` EA or `libzmq.dll` required in MT5.

* **`zmq_server.py` (Windows host with MT5):** Connects to MT5 via `MetaTrader5` IPC and binds:
  * `REP` (`tcp://127.0.0.1:5555`) — Synchronous JSON commands (`PING`, `ACCOUNT_INFO`, `TICK`, `POSITIONS`, `ORDER_SEND`, `CLOSE_POSITION`).
  * `PUB` (`tcp://127.0.0.1:5556`) — Asynchronous live tick stream for `ZMQ_PUB_SYMBOLS`.
* **`zmq_client.py` (Agent / Client):** `ZmqMt5Client` (`REQ` + `SUB`) and CLI that can run locally or from another process/container/OS.

---

## Files

```text
mt5/ai-agent/zeromq/
├── README.md
├── .env.example
├── requirements.txt
├── zmq_server.py           # ZeroMQ REP/PUB server wrapping MetaTrader5 IPC
├── zmq_client.py           # ZeroMQ REQ/SUB client & CLI
└── tests/
    ├── test_zmq_client.py
    └── test_zmq_server.py
```

---

## 1. Setup

From the repository root, create and activate the shared `.venv`:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
.\.venv\Scripts\python.exe -m pip install -r mt5\ai-agent\zeromq\requirements.txt
```

---

## 2. Running the Server & Client

### Terminal 1 — Start the ZeroMQ Server (Windows with MT5 open)
```powershell
.\.venv\Scripts\python.exe mt5\ai-agent\zeromq\zmq_server.py
```

### Terminal 2 — Test with the Client CLI & Unit Tests
```powershell
.\.venv\Scripts\python.exe mt5\ai-agent\zeromq\zmq_client.py --ping --account --positions
.\.venv\Scripts\python.exe mt5\ai-agent\zeromq\zmq_client.py --stream EURUSD
.\.venv\Scripts\python.exe -m pytest mt5\ai-agent\zeromq\tests
```

### Using `ZmqMt5Client` in an Agent
```python
from zmq_client import ZmqMt5Client

with ZmqMt5Client() as mt5_zmq:
    print(mt5_zmq.get_account_info())
    print(mt5_zmq.get_tick("EURUSD"))
```

---

## 3. Environment Variables & Guardrails

Both `zmq_server.py` and `zmq_client.py` automatically load `mt5/ai-agent/zeromq/.env` (copy `.env.example` to `.env` if needed; `.env` is gitignored):

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ZMQ_CMD_ENDPOINT` | `tcp://127.0.0.1:5555` | Command `REQ/REP` endpoint |
| `ZMQ_TICK_ENDPOINT` | `tcp://127.0.0.1:5556` | Tick `PUB/SUB` endpoint |
| `ZMQ_TIMEOUT_MS` | `5000` | Client socket send/receive timeout in ms |
| `ZMQ_POLL_INTERVAL_MS` | `50` | Server poll interval in ms |
| `ZMQ_PUB_SYMBOLS` | `EURUSD` | Comma-separated symbols published on `PUB` |
| `MT5_MAX_LOT_SIZE` | `1.0` | Hard cap on order volume |
| `MT5_ALLOW_LIVE_TRADING` | `false` | Must be `true` to execute orders (otherwise dry-run) |

Always test on a **demo account** before enabling `MT5_ALLOW_LIVE_TRADING=true`.
