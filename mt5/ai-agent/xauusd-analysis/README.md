# XAU/USD (Gold) Analysis MCP + MQL5 Bridge + Skill

Combines live MetaTrader 5 spot & three custom MQL5 indicators ([`HMA nrp.mq5`](../../indicators/HMA%20nrp.mq5), [`AutoFibAutoTrend.mq5`](../../indicators/AutoFibAutoTrend.mq5), and [`CustomCandle.mq5`](../../indicators/CustomCandle.mq5) via `code/XauusdBridgeEA.mq5` + `code/mcp_server.py`) with an agent skill ([`SKILL.md`](SKILL.md)) to produce structured, actionable Gold (`XAU/USD`) market reports.

---

## What the Skill Does ([`SKILL.md`](SKILL.md))

1. **Reads Live MT5 Spot & All 3 Indicators (via MCP `get_xauusd_snapshot`):**
   - **`HMA nrp` (Period 21):** Current/previous HMA values, trend direction (`+1.0` / `-1.0`), `candles_in_trend`, and the exact **`flip_candle`** (`bars_ago`, `time`, `hma_value`, OHLC).
   - **`AutoFibAutoTrend`:** Active swing anchors (`0.0%` → `100.0%`), Fib levels (`0.0%`, `23.6%`, `38.2%`, `50.0%`, `61.8%`, `78.6%`, `100.0%`, `161.8%`), and `channel_present` breakout state.
   - **`H4 CustomCandle`:** Last completed 4-hour candle (`last_h4` OHLC & **last 4hr close**), current 4-hour candle (`current_h4` OHLC), and liquidity-sweep reversal flags (`took_prev_low`, `going_up`, `bullish_sweep_reversal`, `took_prev_high`, `going_down`, `bearish_sweep_reversal`).
2. **Researches Macro, Pivots, Options & Sentiment (via Web Search):**
   - `50D`/`100D` moving averages, classic daily `S1–S3`/`R1–R3` pivots, and Dominion Markets' decision band.
   - Fed rate expectations (CME FedWatch), US 10-year Treasury yields, `DXY`, and upcoming GDP/PCE/CPI/ECI/PMI/NFP catalysts.
   - COMEX Gold (`GC`/`OG`) options expiries, call/put walls, and gamma pin/magnet levels.
   - Retail positioning (IG / Myfxbook) and global gold ETF flows.
3. **Generates a Structured Report (saved under `reports/`):**
   - **Top-of-Report BUY vs. SELL Probability:** Separate Intraday (`M15`–`H1`) and Swing (`H4`–`D1`) conviction percentages.
   - **Levels Gold Can Reach Table & Breakdown:** Maps `AutoFibAutoTrend` channel breakout targets (`38.2%` → **`61.8%`** initial resistance → **`100.0%`** → **`161.8%`**) and downside targets (`HMA nrp` → `0.0%` / `last_h4` low), with a clear driver breakdown explaining why each probability weight is assigned.
   - **Multi-Timeframe Confluence & Scenarios:** Connects `M15` `HMA` flips and `H4` sweep structure to daily MAs, macro headwinds/tailwinds, and concrete Bullish, Bearish, and Invalidation triggers.

---

## Files

```text
mt5/ai-agent/xauusd-analysis/
├── SKILL.md                  # Agent skill workflow & report structure
├── README.md
├── reports/                  # Generated XAU/USD analysis reports
│   └── 2026-11-15_xauusd_report.md
└── code/
    ├── XauusdBridgeEA.mq5    # MQL5 EA exporting HMA nrp (with flip candle), AutoFibAutoTrend & H4 CustomCandle
    ├── mcp_server.py         # Standalone MCP server exposing get_xauusd_snapshot & prompt
    ├── requirements.txt
    └── tests/
        └── test_xauusd_mcp.py
```

---

## Setup & Usage

1. **Install dependencies** (from repo root, using the shared `.venv`):
   ```powershell
   .\.venv\Scripts\python.exe -m pip install -r mt5\ai-agent\xauusd-analysis\code\requirements.txt
   ```
2. **Deploy `code/XauusdBridgeEA.mq5` in MT5:**
   - Ensure `HMA nrp.ex5` and `AutoFibAutoTrend.ex5` are in `MQL5\Indicators\`.
   - Copy `code/XauusdBridgeEA.mq5` (or compiled `XauusdBridgeEA.ex5`) to `MQL5\Experts\` and attach it to your `XAUUSD.p` chart (with `AutoFibAutoTrend` attached on the chart).
   - It writes `MQL5\Files\xauusd_bridge_<SYMBOL>_<TF>.json` on each new bar and timer tick.
3. **Run the MCP server:**
   ```powershell
   .\.venv\Scripts\python.exe mt5\ai-agent\xauusd-analysis\code\mcp_server.py
   ```
4. **Run unit tests (from `mt5\ai-agent\xauusd-analysis\code`):**
   ```powershell
   cd mt5\ai-agent\xauusd-analysis\code
   ..\..\..\..\.venv\Scripts\python.exe -m pytest tests
   ```
