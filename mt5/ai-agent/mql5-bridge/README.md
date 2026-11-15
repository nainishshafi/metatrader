# MQL5 EA / Script Bridge

> **Main Concepts:** See [`reference/MT5_AI_AGENT_CONCEPTS.md`](../../../reference/MT5_AI_AGENT_CONCEPTS.md) and [`mt5/ai-agent/README.md`](../README.md) for how this fits alongside `mcp/` and `zeromq/`.

An **MQL5 EA / Script Bridge** runs *inside* the MetaTrader 5 terminal to expose data and events that the external `MetaTrader5` Python package cannot access.

---

## Why This Bridge Is Needed

Both [`mcp/`](../mcp/README.md) and [`zeromq/`](../zeromq/README.md) connect to MT5 from Python using MetaQuotes' official `MetaTrader5` Python package over Windows local IPC. While that package handles account state, ticks, OHLCV bars, and order execution, it has hard architectural limits:

1. **No Indicator API in Python:**
   The `MetaTrader5` Python package has **no** `iRSI`, `iMA`, `iMACD`, `iCustom`, or `CopyBuffer` functions. You cannot read built-in or custom (`.ex5`) indicator buffers from Python IPC.
2. **No Access to Chart State or Objects:**
   External Python processes cannot read indicators attached to an open chart, trendlines/chart objects, or internal Expert Advisor state.
3. **MQL5 Sandbox Boundary:**
   Custom indicators (`.ex5`) and EAs execute strictly inside MT5's sandboxed MQL5 runtime. External AI agents cannot call into MQL5 memory directly—an MQL5 program inside the terminal must call `CopyBuffer(...)` and push or serve the values outward.
4. **No Event-Driven Callbacks:**
   Python IPC is polling-based. Only an MQL5 EA can react natively to `OnTick()`, `OnTimer()`, and `OnTradeTransaction()` inside the terminal.

---

## When to Use This vs. Computing in Python

| Need | Recommended Approach |
| :--- | :--- |
| Standard indicators (EMA, SMA, RSI, MACD, ATR) | Fetch OHLCV bars via `get_rates` (`copy_rates_from_pos`) and compute in Python (`mcp/` or `zeromq/`) |
| Custom / proprietary `.ex5` indicators | **MQL5 EA Bridge** calling `iCustom()` + `CopyBuffer()` inside MT5 |
| Exact parity with MT5 chart indicator buffers | **MQL5 EA Bridge** calling `CopyBuffer()` |
| Instant `OnTick` / `OnTradeTransaction` push events | **MQL5 EA Bridge** |

---

## Architecture

```text
┌───────────────────────────────────────────┐
│ MetaTrader 5 Terminal (MQL5 Runtime)      │
│                                           │
│  Custom/Built-in Indicator (.ex5)         │
│         │  iCustom / CopyBuffer           │
│         ▼                                 │
│  Bridge EA / Service (.mq5)               │
└─────────┬─────────────────────────────────┘
          │  HTTP (WebRequest) / TCP Socket / File
          ▼
┌───────────────────────────────────────────┐
│ External Python Process                   │
│  (MCP Server / ZeroMQ Server / AI Agent)  │
└───────────────────────────────────────────┘
```

---

## Common Transport Options from MQL5

* **Local HTTP (`WebRequest`):**
  The EA sends JSON snapshots (e.g., on new bar or timer) to a local Python HTTP/MCP endpoint. Requires whitelisting the localhost URL under *Tools → Options → Expert Advisors → Allow WebRequest for listed URL*.
* **TCP / ZeroMQ Sockets (`SocketCreate` or `libzmq.dll`):**
  Low-latency bidirectional messaging or tick/indicator streaming. Native `Socket*` functions require no DLLs; `libzmq.dll` requires enabling *Allow DLL imports* in MT5.
* **Shared File (`MQL5\Files\`):**
  Zero-network, zero-DLL option where the EA writes JSON/CSV indicator values into `MQL5\Files\` and Python reads them. Simple for low-frequency (e.g., M5/H1 bar-close) workflows.

---

## Reference Implementation (RSI Bridge)

```text
mt5/ai-agent/mql5-bridge/
├── README.md
├── RsiBridgeEA.mq5           # MQL5 EA using iRSI + CopyBuffer (exports via File + WebRequest)
├── bridge_server.py          # Python HTTP receiver (POST/GET /indicator) + file reader
└── tests/
    └── test_bridge_server.py
```

1. **Start the Python receiver:**
   ```powershell
   .\.venv\Scripts\python.exe mt5\ai-agent\mql5-bridge\bridge_server.py
   ```
   Listens on `http://127.0.0.1:8765` (configurable via `MQL5_BRIDGE_HOST` and `MQL5_BRIDGE_PORT`). Endpoints:
   - `POST /indicator` — Receives JSON snapshots from `RsiBridgeEA.mq5` (max `1 MiB`).
   - `GET /indicator?symbol=XAUUSD.p&timeframe=M15` — Returns the latest stored snapshot (`200`), `400` if params are missing, or `404` if not yet received.
   - `GET /health` — Lists currently available `(symbol, timeframe)` pairs.
2. **Deploy & attach `RsiBridgeEA.mq5` in MetaTrader 5:**
   - Copy `RsiBridgeEA.mq5` into your terminal's `AppData\Roaming\MetaQuotes\Terminal\<Instance_ID>\MQL5\Experts\` folder and compile in MetaEditor (`0 errors, 0 warnings`).
   - Attach it to a chart (e.g., `XAUUSD.p` `M15`). `OnInit()` guards `CopyBuffer()` with `BarsCalculated()` so startup never blocks MT5's 46.7s synchronous wait.
   - To enable HTTP push, add `http://127.0.0.1:8765` under *Tools → Options → Expert Advisors → Allow WebRequest for listed URL*. (Without this, MT5 logs `WebRequest failed ... err=4014`.)
   - File export (`InpExportToFile=true`) writes `MQL5\Files\rsi_bridge_<SYMBOL>_<TF>.json` even without `WebRequest`, readable via `bridge_server.read_indicator_file(...)`.

### Sample Live Payload (`GET /indicator?symbol=XAUUSD.P&timeframe=M15`)

```json
{
  "ok": true,
  "data": {
    "indicator": "RSI",
    "symbol": "XAUUSD.p",
    "timeframe": "M15",
    "period": 14,
    "latest": {"time": 1794613500, "close": 3882.0, "rsi": 52.0163},
    "values": [
      {"time": 1794609900, "close": 3878.49, "rsi": 46.3657},
      {"time": 1794613500, "close": 3882.0, "rsi": 52.0163}
    ]
  }
}
```

### Tests & Coverage

Run unit and HTTP integration tests from `mt5\ai-agent\mql5-bridge`:
```powershell
cd mt5\ai-agent\mql5-bridge
..\..\..\.venv\Scripts\python.exe -m pytest tests
```

`tests/test_bridge_server.py` covers:
- `IndicatorStore` thread-safe `put`/`get`/`list_keys`, case normalization, and `empty`/`null` string validation.
- `read_indicator_file()` JSON parsing and `FileNotFoundError` handling.
- Live `ThreadingHTTPServer` `200` happy paths (`POST /indicator`, `GET /indicator`, `GET /health`) and error paths (`400` on `null` symbol, invalid `Content-Length`, malformed JSON, missing query params; `413` on oversized `Content-Length`; `404` on unknown symbol/route).
