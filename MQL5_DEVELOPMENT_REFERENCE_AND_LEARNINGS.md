# MQL5 Development Reference & Technical Learnings Guide

This document captures the technical lessons, architectural pitfalls, debugging discoveries, and best practices established during the MT4-to-MT5 migration and optimization of `EA_autotrade.mq5`, `HMA nrp.mq5`, and `CustomCandle.mq5`.

---

## 1. MQL5 Indicator Architecture & `iCustom` Parameter Binding

### 1.1 The `input group` Parameter Offset Bug
* **The Pitfall:** In MQL5, `input group "Header Text"` is visually treated as a group separator in the UI, but **at runtime and compiler level, each `input group` counts as a parameter index slot (`TYPE_STRING`)**.
* **Failure Mode:** Calling an indicator with `iCustom(_Symbol, tf, "IndicatorName", param1, param2)` when the indicator declared `input group` ahead of its variables caused `param1` to map to the `input group` slot and shifted the actual parameters. In `HMA nrp.mq5`, passing `PERIOD_M15` and `HMAPeriod = 21` caused `21` to be read into the `TimeFrame` parameter. MT5 treated `21` as an invalid timeframe, causing `CopyRates` to fail silently and leaving `BarsCalculated` at `0`.
* **Best Practice:** **Never use `input group` in custom indicators intended to be invoked programmatically via `iCustom()` or `IndicatorCreate()`.** Use standard comments (`//--- Group Name`) instead.

### 1.2 Managed Indicator Buffers vs. Dynamic Arrays
* **The Pitfall:** Calling `ArraySize(buffer)` on an indicator buffer mapped via `SetIndexBuffer()` returns `0` when called from secondary execution threads or programmatic `iCustom` instances.
* **Failure Mode:** Code like `int limit = MathMin(total, ArraySize(dst));` or `ArrayResize(dst, total)` fails on managed buffers:
  * `ArrayResize()` on a managed buffer returns an error (`cannot resize indicator buffer`).
  * `ArraySize()` returning `0` collapses calculation loops (`limit = 0`), leaving indicator outputs completely empty (`EMPTY_VALUE`).
* **Best Practice:**
  * Use local dynamic arrays for intermediate scratch calculations (`maHalf[]`, `maFull[]`) and explicitly size them using `ArrayResize(..., total, 1024)`.
  * For output buffers mapped with `SetIndexBuffer()`, iterate directly up to `total` (`rates_total`).

### 1.3 Indicator Buffer Types & MT5 Copy Access
* **`INDICATOR_DATA`**: Data exported to the chart window and fully accessible via `CopyBuffer()`.
* **`INDICATOR_COLOR_INDEX`**: Holds color index values for color lines/candles. Accessible via `CopyBuffer()`.
* **`INDICATOR_CALCULATIONS`**: Internal computation buffer; **not always accessible via `CopyBuffer()` in external EAs**.
* **Rule:** Any buffer that an EA must inspect (such as `TrendBuffer` containing `+1.0 / -1.0` trend states) must be mapped as `INDICATOR_DATA` rather than `INDICATOR_CALCULATIONS`.

---

## 2. Indicator Binding, Threading & `CopyBuffer` Timeouts

### 2.1 The Synchronous 46.7-Second Freeze
* **The Pitfall:** Calling `CopyBuffer(handle, 0, 0, count, array)` on an indicator handle where calculations have not yet completed triggers an internal MT5 synchronous wait loop with a **~46-second timeout**.
* **Symptom:** The entire EA thread freezes for ~46 seconds inside `OnInit()` or `OnTick()`. While blocked:
  * The chart UI stops responding.
  * Button clicks are dropped by the Windows message pump.
  * MT5 terminal logs show multi-minute gaps between `LoadHMAHandle()` and `EA AutoTrade initialized successfully`.
* **The Solution:** Always inspect `BarsCalculated(handle)` before calling `CopyBuffer()`:
  ```mql5
  // Guard against MT5 synchronous thread lock:
  if(g_hHMA == INVALID_HANDLE || BarsCalculated(g_hHMA) < 2)
     return(false); // Immediate 0-ms return; wait for next timer/tick
  ```

### 2.2 Handle Reinitialization & Stale Cache
* When an indicator `.mq5` or `.ex5` file is modified on disk, existing handles in running EAs can become stale.
* If `LoadHMAHandle()` fails or returns invalid data after recompilation, the EA should safely release the old handle with `IndicatorRelease(g_hHMA)` before acquiring a new one.

---

## 3. GUI Responsiveness, Hit-Testing & Chart Objects

```
┌────────────────────────────────────────────────────────┐
│ Visual Drawing Hierarchy (Chronological Creation):      │
│  1. PNL_BG (OBJ_RECTANGLE_LABEL)  -> Created FIRST     │
│  2. Labels (OBJ_LABEL)            -> Created SECOND    │
│  3. Buttons (OBJ_BUTTON)          -> Created LAST      │
└────────────────────────────────────────────────────────┘
```

### 3.1 Visual Layering vs. Event Priority (`OBJPROP_ZORDER`)
* **Visual Rendering:** MT5 paints chart objects strictly in the chronological order of creation. An object created later paints over an object created earlier.
* **Click Event Priority (`OBJPROP_ZORDER`):** Dictates which overlapping object receives `CHARTEVENT_OBJECT_CLICK`.
* **The Trap:** Creating buttons *first* and the background panel (`PNL_BG`) *second* caused `PNL_BG` to visually overlay the buttons or capture mouse events if `OBJPROP_BACK = false`.
* **Best Practice:**
  1. Create background panels **first** with `OBJPROP_BACK = false` and `OBJPROP_ZORDER = 0`.
  2. Create informational labels **second** with `OBJPROP_BACK = false` and `OBJPROP_ZORDER = 10`.
  3. Create interactive buttons **last** with `OBJPROP_ZORDER = 100` and `OBJPROP_SELECTABLE = false`.

### 3.2 Delta-Only UI Updates (GDI Font Throttling)
* **The Bottleneck:** Calling `ObjectSetString(0, label, OBJPROP_TEXT, ...)` and `ChartRedraw(0)` every second (or worse, every tick) forces the Windows GDI subsystem to repeatedly re-rasterize font glyphs, causing high CPU usage and dropped mouse events.
* **The Optimization:** Cache the displayed string and color. Only invoke MT5 object property setters and `ChartRedraw(0)` when a value actually changes:
  ```mql5
  bool SetLabelIfChanged(const string name, string &cache_text, color &cache_clr,
                         const string new_text, const color new_clr)
  {
     bool changed = false;
     if(cache_text != new_text) {
        ObjectSetString(0, name, OBJPROP_TEXT, new_text);
        cache_text = new_text;
        changed = true;
     }
     if(new_clr != clrNONE && cache_clr != new_clr) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, new_clr);
        cache_clr = new_clr;
        changed = true;
     }
     return changed;
  }
  ```

### 3.3 Event Redraw Decoupling
* **Never call `UpdateDashboard()` or `ChartRedraw(0)` on every tick in `OnTick()`.** On active instruments like XAU/USD with dozens of ticks per second, this floods the message queue.
* Drive dashboard refreshes via `OnTimer()` (1-second intervals) and on explicit user actions (`OnChartEvent` button clicks).

### 3.4 Modal Popups Freeze MT5 UI
* Avoid using modal `Alert(...)` inside trade verification functions (e.g. `CheckAlgoTradingAllowed()`). Modal dialogs freeze the chart message loop until dismissed. Use `Print()` or status label updates instead.

---

## 4. Algorithmic Optimization & Calculation Complexity

### 4.1 Incremental `O(1)` Calculation vs. Full `O(N)` Loops
* **The Issue:** `HMA nrp.mq5` previously calculated all `5,000+` bars on every single tick, executing multiple nested MA passes and dynamic allocations per price fluctuation.
* **The Optimization:** Utilize `prev_calculated`:
  * Full initial calculation on bar `0`: `start = 0`.
  * Incremental calculation on subsequent ticks: `start = prev_calculated - 1`.
  * Pre-allocate persistent static/global working buffers with capacity reserves (`ArrayResize(buf, total, 1024)`).
  * Reduces per-tick computational overhead from thousands of iterations to a single bar update.

### 4.2 Multi-Timeframe (MTF) Data Retrieval
* Rather than copying the entire lower-timeframe history into the HTF buffer (`CopyRates(_Symbol, targetTf, 0, rates_total, ...)`), compute the required HTF bar count:
  $$\text{htfBarsToCopy} = \frac{\text{rates\_total}}{\text{barsPerHtf}} + 3 \times \text{Period} + 20$$
* Use binary search (`O(\log N)`) rather than linear search (`O(N)`) to match lower timeframe timestamps to HTF bars.

### 4.3 Chart Background Object Filtering (`CustomCandle.mq5`)
* Indicators that draw historical candles or analytical shapes should never recreate closed historical objects on every tick:
  ```mql5
  // Fast skip: closed historical bars (k > 1) never change
  if(k > 1 && ObjectFind(0, candle_name) >= 0)
     return;
  ```
* Set `OBJPROP_BACK = true` and `OBJPROP_SELECTABLE = false` on background candles to ensure they never intercept chart mouse events.

---

## 5. Trading Execution & Position Sizing Rules

### 5.1 Dynamic Equity-Based Lot Sizing
* Target formula: **$10,000 Equity = 1.0 Lot** (scalable proportionally).
  $$\text{Lots} = \text{NormalizeLot}\left(\frac{\text{Equity}}{10000.0} \times \text{LotsPer10k}\right)$$
* Sized strictly against broker constraints (`SYMBOL_VOLUME_MIN`, `SYMBOL_VOLUME_MAX`, `SYMBOL_VOLUME_STEP`).

### 5.2 Dollar-Distance Take Profit & Stop Loss (XAU/USD)
* For Gold ($/oz), point value and tick size must translate cleanly to dollar moves:
  * **Buy Order TP:** $\text{Ask} + \text{InpTakeProfitPriceDist}$ (e.g. $4,100.00 \to $4,105.00 for $5.00 TP).
  * **Sell Order TP:** $\text{Bid} - \text{InpTakeProfitPriceDist}$ (e.g. $4,105.00 \to $4,100.00 for $5.00 TP).
  * Normalize to `_Digits` using `NormalizeDouble()`.

### 5.3 Magic Number Separation
* **`InpMagicManual` (9999):** Used by manual GUI panel buttons (`BUY`, `SELL`, `Close Half`, `Update SL`).
* **`InpMagicAuto` (1234):** Used exclusively by the automated trend-following engine.
* This separation prevents manual user trades from interfering with auto-reversal management or `InpAutoTradeOnce` state logic.
