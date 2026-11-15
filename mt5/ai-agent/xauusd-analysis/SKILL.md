---
name: xauusd-analysis
description: Comprehensive XAU/USD (Gold) analysis combining live MT5 technicals (50D/100D SMA, S1-S3/R1-R3 pivots, HMA nrp, AutoFibAutoTrend via MCP) with web research on macro catalysts, COMEX options expiries/OI pins, and retail/investor sentiment.
---

# XAU/USD (Gold) Comprehensive Analysis Skill

Use this skill whenever the user asks for a comprehensive **Gold (`XAU/USD`) market analysis** combining live MetaTrader 5 technicals, custom MQL5 indicators (`HMA nrp` and `AutoFibAutoTrend`), macroeconomic catalysts, COMEX options positioning, and trader sentiment.

---

## Workflow

### Step 1 — Gather Live MT5 Spot & Custom Indicators (via MCP)
Call `get_xauusd_snapshot(symbol="XAUUSD.p", timeframe="M15")` exposed by [`code/mcp_server.py`](code/mcp_server.py), which reads the live JSON exported by [`code/XauusdBridgeEA.mq5`](code/XauusdBridgeEA.mq5):

- Live `bid` / `ask`
- **`HMA nrp`** (`value`, `prev_value`, `trend` `+1`/`-1`, `candles_in_trend`, and `flip_candle`: `bars_ago`, `time`, `hma_value`, OHLC)
- **`AutoFibAutoTrend`** (`0.0%`–`100.0%` Fib levels, `161.8%` extension & trend channel)
- **`H4 CustomCandle`** (`h4_candle.last_h4` OHLC including last 4hr close, `h4_candle.current_h4` OHLC, and liquidity sweep flags: `took_prev_low` / `going_up` / `bullish_sweep_reversal` and `took_prev_high` / `going_down` / `bearish_sweep_reversal`)

### Step 2 — Web Research on Technicals, Macro, COMEX Options & Sentiment
Run targeted `search_web` queries (using current date context) across four pillars:

1. **50D/100D Moving Averages, Intraday Pivots & Decision Band:**
   - Latest XAU/USD spot price action, 50-day & 100-day moving averages, intraday support (`S1, S2, S3`) and resistance (`R1, R2, R3`) levels, and Dominion Markets' decision band.

1. **Macroeconomic Drivers & Upcoming Catalysts:**
   - Federal Reserve rate expectations (CME FedWatch / FOMC commentary), US 10-year Treasury & real yields (TIPS), and US Dollar Index (`DXY`).
   - Upcoming high-impact releases (**GDP, PCE, CPI, ECI, PMI, NFP, and central bank rate decisions**) and their expected transmission effect on bullion (e.g., hotter PCE/CPI → higher real yields / stronger DXY → headwind for non-yielding gold; dovish pivot / weaker PMI → tailwind).
2. **COMEX Gold Options Expiries & Open Interest:**
   - Upcoming COMEX Gold (`GC` / `OG`) monthly/weekly options expiries, notable strike open interest concentrations (major call walls and put walls), and **option pin / magnet levels**.
3. **Investor & Retail Trader Sentiment:**
   - Retail client positioning (e.g., IG/broker long-vs-short %, Myfxbook, TradingView, Reddit/X trading communities) and institutional/ETF flows to evaluate crowd bias (**bullish vs. bearish** and contrarian crowding risk).

### Step 3 — Synthesize Into Meaningful, Actionable Analysis
Do **not** dump raw MCP numbers (`trend = +1.0`, `61.8%: 3882.23`) without interpretation. Connect the live MT5 readings to the macro, pivot, options, and sentiment context:

1. **Multi-Timeframe Confluence vs. Conflict (`H4` CustomCandle + Intraday `HMA nrp`):**
   - Report the **last 4hr close** (`h4_candle.last_h4.close`) and its range (`high` / `low`).
   - Check `h4_candle` sweep status: has the current `H4` candle **taken the low of the last 4hr candle and turned up** (`bullish_sweep_reversal`: `took_prev_low` + `current_h4.close > last_h4.low` + `going_up`), or **taken the high of the last 4hr candle and turned down** (`bearish_sweep_reversal`: `took_prev_high` + `current_h4.close < last_h4.high` + `going_down`)?
   - Compare intraday `HMA nrp` direction (`trend` / `prev_trend`, and whether spot is above/below `hma.value`) and `H4` sweep structure against the higher-timeframe `50D`/`100D` moving averages. State clearly whether an intraday signal is **trend-aligned** or a **counter-trend bounce/pullback**.
2. **Fib + Channel Breakout + Decision Band Confluence:**
   - Identify the `AutoFibAutoTrend` swing direction (`anchor_1 = 0.0%` → `anchor_0 = 100.0%` in MT5 `OBJ_FIBO`) and flag exact price overlaps between Fib retracements/extensions (`23.6%`, `38.2%`, `50.0%`, `61.8%`, `78.6%`, `100.0%`, `161.8%`), classic `S1–S3`/`R1–R3` pivots, and Dominion Markets' decision band.
   - If `autofib.channel_present` is `true` (or a chart screenshot is provided), explicitly check whether price is **inside the `AutoFibAutoTrend` channel** or **breaking out** above/below its trendline. On a bullish channel breakout (pushing above `38.2%`), map the primary continuation targets as **`61.8%` (expected initial resistance)** and **`100.0%`**, followed by **`161.8%`** on extension (and vice versa for a bearish channel breakdown), alongside failed-breakout invalidation.
3. **Structured Report & Scenarios (Always Generate a Fresh Timestamped File):**
   - Save every skill run as a **fresh timestamped report** under `reports/YYYY-MM-DD_HHMM_xauusd_report.md` (do not overwrite prior reports).
   - **Top-of-Report BUY vs. SELL Probability, Reachable Levels Table & Breakdown:** Always place a BUY vs. SELL probability table (Intraday `M15`–`H1` and Swing `H4`–`D1`), a **Levels Gold Can Reach** table (upside BUY targets `61.8%`, `100.0%`, `161.8%` and downside SELL targets), and a **Probability Breakdown** explaining the technical/H4/daily/macro/sentiment weights at the very top of the report.
   - **Executive Bias & Trend Probability:** Clear Buy vs. Sell conviction grounded in technicals, macro, and positioning.
   - **Intraday Levels Table:** `S3–S1, P, R1–R3`, Fib confluence, and Dominion Markets decision band.
   - **Macro Catalysts & Transmission:** FedWatch, 10Y yields, DXY, and upcoming GDP/PCE/CPI/ECI/PMI events.
   - **COMEX Options & Sentiment:** Key strikes/pin magnets, retail long/short %, and contrarian liquidity risks.
   - **Actionable Scenarios:** Concrete **Bullish**, **Bearish**, and **Invalidation** triggers using `HMA nrp` value, Fib levels, and decision-band boundaries.
