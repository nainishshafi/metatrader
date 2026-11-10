# MetaTrader 5 Algorithmic Trading Framework & AutoTrade EA

A modular, high-performance **MetaTrader 5 (MQL5)** algorithmic trading framework and on-chart trading assistant designed for **XAU/USD (Gold)**.

The project combines an interactive on-chart dashboard with an automated trend-following engine powered by the **Hull Moving Average Non-Repainting (HMA NRP)** indicator and M15 breakout continuation rules.

---

## 📖 Simple Explanation: What Does This Project Do?

1. **Interactive On-Chart Trading Panel (Manual Trading):**
   * Gives traders clean on-chart buttons: **BUY**, **SELL**, **Close All**, **Close Half** (partial volume close), **Update SL** (moves Stop Loss to entry price/breakeven for profitable trades), and a **Trade: ON/OFF** toggle.
   * Displays a live dashboard showing account equity, calculated lot size, live bid/ask quotes, open positions summary, floating P/L, and current HMA trend status.

2. **Automated Trading Engine (AutoTrade):**
   * When toggled **ON**, the EA monitors M15 and M1 market structure in real time.
   * Executes automated Buy/Sell orders when the HMA trend aligns with M15 breakout and expansion criteria.
   * Features automatic reversal management: if the trend flips against an active automated trade, the EA can safely exit the trade.

3. **Dynamic Equity-Based Position Sizing:**
   * Automatically calculates lot sizing based on current account equity (default: **$50,000 Equity = 1.0 Lot**, scalable proportionally; e.g. $25,000 = 0.50 lot, $10,000 = 0.20 lot).
   * Fully quantizes volume against broker constraints (`SYMBOL_VOLUME_STEP`, `SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_MAX`).

4. **Dollar-Distance Stops & Targets:**
   * Configurable price distance for Take Profit and Stop Loss (e.g., +$5.00 gold move: Buy at $4,100.00 -> TP at $4,105.00).

---

## 🏛️ Two-Tier Architecture

To avoid monolithic script sprawl and enable cross-project reuse, the codebase follows a **Two-Tier Architecture**:

```
mt5/
├── include/                          <-- TIER 1: Generic Reusable Framework
│   ├── Common/
│   │   └── SymbolHelper.mqh          <-- Lot step quantization, stops levels, filling modes
│   ├── Indicators/
│   │   └── IndicatorHandle.mqh       <-- RAII handle lifecycle with 46s freeze guard
│   ├── Trade/
│   │   └── PositionManager.mqh       <-- Magic-isolated CloseAll, CloseHalf, Breakeven
│   ├── GUI/
│   │   └── ChartGUI.mqh              <-- Delta-cached labels, styled buttons & panels
│   └── Strategy/
│       └── ISignal.mqh               <-- Generic strategy signal interface
│
└── experts/                          <-- TIER 2: EA-Specific Implementation
    ├── EA_autotrade.mq5              <-- Lean entry point (< 100 lines)
    └── include/AutoTrade/
        ├── Defines.mqh               <-- AutoTrade button IDs & configuration structs
        ├── HMASignal.mqh             <-- HMA NRP + M15 breakout strategy (implements ISignal)
        ├── DashboardPanel.mqh        <-- XAU/USD dashboard layout (uses ChartGUI)
        └── TradingSystem.mqh         <-- High-level Facade coordinating subsystems
```

* **Tier 1 (Generic Framework):** Reusable across *any* future Expert Advisor, indicator, or strategy with zero modifications.
* **Tier 2 (Domain Implementation):** Implements the specific rules, parameters, and HUD layout for `EA_autotrade`.

---

## ⚡ Core Coding Practices & Performance Principles

Trading systems process rapid tick spikes (up to 200 ticks/sec during volatility on Gold). The codebase enforces strict quantitative engineering standards:

### 1. The `< 1.0 ms` `OnTick()` Execution Budget
* The tick handler only executes fast-path logic: state checks, $O(1)$ indicator buffer slicing (fetching only bars 0 and 1), signal evaluation, and order dispatch.
* Never run unbounded loops, historical back-scans, or heap allocations (`new`/`delete`) inside `OnTick()`.

### 2. Decoupled Visuals & GDI Font Throttling
* **Problem:** Updating chart label text on every tick forces the Windows GDI subsystem to repeatedly re-rasterize font glyphs, causing high CPU usage and dropped mouse clicks.
* **Solution:**
  * Chart redraws and dashboard refreshes run on a 1-second background timer (`OnTimer()`) and on user button clicks—**never on raw ticks**.
  * `CChartGUI::SetLabelIfChanged()` only modifies chart objects if text or color has actually changed (delta-caching).

### 3. Chronological Z-Order Visual Stacking
* In MetaTrader 5, objects are visually layered in their **chronological order of creation**:
  1. `OBJ_RECTANGLE_LABEL` (Background panel) is created **first** (`ZORDER = 0`).
  2. `OBJ_LABEL` (Informational text) is created **second** (`ZORDER = 10`).
  3. `OBJ_BUTTON` (Interactive controls) are created **last** (`ZORDER = 100`, `SELECTABLE = false`).
* This eliminates click-blocking bugs where background rectangles intercept button mouse events.

### 4. Magic Number Isolation & Safe Loop Iteration
* Manual panel buttons trade under `InpMagicManual` (default: `9999`).
* Automated trades execute under `InpMagicAuto` (default: `1234`).
* All position closures and modifications strictly check **both** `Symbol` and `Magic Number`, ensuring external EAs or manual trades on the same account are never accidentally closed.
* All closure loops iterate in reverse (`for int i = PositionsTotal() - 1 down to 0`) to prevent skipping orders when tickets shift upon closure.

### 5. Broker Safety & Constraint Validation
* **Stops Level Validation:** SL/TP distances are validated against $\max(\text{StopsLevel}, \text{Spread})$ before order submission, preventing broker error `10016` (`TRADE_RETCODE_INVALID_STOPS`).
* **Order Filling Auto-Detection:** Dynamically inspects `SYMBOL_FILLING_MODE` to set `ORDER_FILLING_FOK`, `ORDER_FILLING_IOC`, or `ORDER_FILLING_RETURN`, preventing execution rejections across different broker book models.
* **Volume Normalization:** Lot sizing is quant-stepped with `SYMBOL_VOLUME_STEP` and clamped between `MIN` and `MAX`.

### 6. Indicator Thread-Lock Guard
* Calling `CopyBuffer()` on an indicator that has not completed initial bar calculation causes an internal MT5 synchronous freeze of **~46.7 seconds**.
* `CIndicatorHandle::IsReady()` guards every call with `BarsCalculated(handle) >= 2`.

### 7. Pragmatic Flat Composition (Anti-Over-Engineering)
* Avoids deep inheritance hierarchies and "abstract factory factories".
* Maximum 1 level of inheritance (`CHMASignal : public ISignal`).
* Flat composition through a top-level facade (`CTradingSystem`).

---

## 🚀 Installation & Setup

### Prerequisites
* **MetaTrader 5 Desktop Terminal** (64-bit).
* **HMA nrp indicator** (`HMA nrp.ex5` or `HMA nrp.mq5`) placed in your terminal's `MQL5\Indicators\` folder.

### Installation Steps
1. Open MetaTrader 5 and click **File -> Open Data Folder**.
2. Copy the folders from this repository to your terminal directory:
   * Copy `mt5/include/*` to `MQL5\Include\`
   * Copy `mt5/experts/EA_autotrade.mq5` and `mt5/experts/include/` to `MQL5\Experts\`
   * Copy `mt5/indicators/*` to `MQL5\Indicators\`
3. Open **MetaEditor** (press `F4` in MT5), open `EA_autotrade.mq5`, and press **Compile** (`F7`).
   * Verify output: `0 errors, 0 warnings`.
4. In MT5, enable **Algo Trading**:
   * Click the **Algo Trading** button in the top toolbar (turns green).
   * In MT5 menu: **Tools -> Options -> Expert Advisors -> Allow Algo Trading**.
5. Attach `EA_autotrade` to an **XAU/USD (Gold)** chart (recommended timeframe: **M15**).

---

## 📚 Reference & Technical Documentation

For in-depth standards, audit rubrics, and technical post-mortems, consult the reference guides in the `reference/` directory:

* **[MQL5 Code Writer & Implementation Standard](reference/MQL5_WRITER_GUIDE.md):** Clean coding rules, RAII patterns, hot-path optimization, and two-tier library structuring.
* **[MQL5 Code Reviewer & Checker Manual](reference/MQL5_CHECKER_GUIDE.md):** 10-point pre-deployment pass/fail checklist, failure mode audits, and headless automated compilation scripts.
* **[OOP vs. Procedural & Data-Oriented Performance Guide](reference/MQL5_OOP_VS_PROCEDURAL_PERFORMANCE_GUIDE.md):** In-depth CPU hardware, cache line, and VTable analysis of OOP vs Procedural math in quantitative systems.
* **[Technical Learnings & Post-Mortem Guide](MQL5_DEVELOPMENT_REFERENCE_AND_LEARNINGS.md):** Detailed technical discoveries from past bugs (46s freeze, input group compiler bug, GDI font thrashing).

---

## 📄 License
This project is licensed under the MIT License - see the repository for details.

