# MQL5 Code & Architecture Reviewer / Checker Manual

> **Target Audience:** Lead Quantitative Developers, Code Reviewers, Trading System Auditors, and QA Engineers.  
> **Core Objective:** Provide a comprehensive inspection standard, pre-deployment pass/fail audit checklist, and detection rubric for bugs, performance bottlenecks, and over-engineering in MQL5 trading systems.

---

## Table of Contents
1. [The Reviewer's Mandate & Audit Philosophy](#1-the-reviewers-mandate--audit-philosophy)
2. [The 10-Point Pre-Deployment Pass/Fail Checklist](#2-the-10-point-pre-deployment-passfail-checklist)
3. [Audit Area 1: Trade Safety & Magic Number Isolation](#3-audit-area-1-trade-safety--magic-number-isolation)
4. [Audit Area 2: Broker Execution & Constraint Compliance](#4-audit-area-2-broker-execution--constraint-compliance)
5. [Audit Area 3: Algorithmic Complexity & Hot-Path Latency](#5-audit-area-3-algorithmic-complexity--hot-path-latency)
6. [Audit Area 4: Indicator Lifecycles & Synchronous Freezes](#6-audit-area-4-indicator-lifecycles--synchronous-freezes)
7. [Audit Area 5: UI Responsiveness & GDI Throttling](#7-audit-area-5-ui-responsiveness--gdi-throttling)
8. [Audit Area 6: Over-Engineering & Architectural Bloat](#8-audit-area-6-over-engineering--architectural-bloat)
9. [Automated Verification & CLI Build Commands](#9-automated-verification--cli-build-commands)

---

## 1. The Reviewer's Mandate & Audit Philosophy

MQL5 systems control real capital in asynchronous, volatile financial markets. Unlike web applications where an unhandled exception or latency spike affects a single HTTP request:
* A 100-millisecond chart freeze drops incoming tick events and delays stop orders.
* A missing magic number filter can close or modify external trades running on the same account.
* A violation of broker freeze/stop constraints results in silent order rejections.

Reviewers must enforce **deterministic behavior, zero memory fragmentation, and strict execution isolation**.

---

## 2. The 10-Point Pre-Deployment Pass/Fail Checklist

Every MQL5 Expert Advisor pull request must achieve a 100% pass score on this checklist before being approved for live deployment:

| # | Check Item | Pass Criteria | Failure Mode | Status |
| :-: | :--- | :--- | :--- | :-: |
| **1** | **Magic Number Isolation** | All position modifications, closures, and counts check BOTH `Symbol` and `Magic`. | Modifies/closes manual trades or external EAs. | [ ] |
| **2** | **Reverse Pool Iteration** | All position loops that close or modify orders iterate backwards: `for(int i = PositionsTotal() - 1; i >= 0; i--)`. | Skipped positions due to index shifting. | [ ] |
| **3** | **46.7s Freeze Guard** | Every `CopyBuffer()` call is preceded by `if(BarsCalculated(h) < 2) return false;`. | ~46s synchronous terminal freeze on startup. | [ ] |
| **4** | **Stops Level Validation** | SL and TP are verified against $\max(\text{StopsLevel}, \text{Spread})$ before order submission. | Broker rejection with retcode `10016`. | [ ] |
| **5** | **Execution Filling Mode** | `CTrade::SetTypeFilling` is configured dynamically based on `SYMBOL_FILLING_MODE`. | Immediate rejection on IOC/Return ECN brokers. | [ ] |
| **6** | **Lot Step Quantization** | Sizing uses `MathFloor(vol / step) * step` clamped between `MIN` and `MAX` volume. | Order rejected with `10014` (Invalid Volume). | [ ] |
| **7** | **Zero Redraw in Tick** | `ChartRedraw(0)` is absent from `OnTick()`, firing only in `OnTimer()` or on button clicks. | Windows GDI font thrashing & CPU spikes. | [ ] |
| **8** | **Delta-Cached Labels** | GUI updates use caching to avoid redundant `ObjectSetString` calls. | Dropped mouse clicks and UI unresponsiveness. | [ ] |
| **9** | **Indicator Handle Cleanup**| All allocated indicator handles are released in `OnDeinit()` with `IndicatorRelease()`. | Handle memory leaks and background CPU drain. | [ ] |
| **10**| **No Modal Dialogs** | No modal `Alert()` or blocking message boxes in event handlers. | Freezes MT5 thread until user manual click. | [ ] |

---

## 3. Audit Area 1: Trade Safety & Magic Number Isolation

### 3.1 Detecting Magic Number Bleed

Inspect all loops accessing the position pool (`PositionsTotal()`).

#### ❌ Reject Pattern:
```mql5
// DANGEROUS: Closes ANY trade on the symbol, including user manual trades!
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == _Symbol) // Fails to check Magic!
            m_trade.PositionClose(m_position.Ticket());
      }
   }
}
```

#### ✅ Required Pattern:
```mql5
void CloseAllPositions(const ulong targetMagic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(m_position.SelectByIndex(i))
      {
         if(m_position.Symbol() == _Symbol && m_position.Magic() == targetMagic)
            m_trade.PositionClose(m_position.Ticket());
      }
   }
}
```

### 3.2 Detecting Forward-Iteration Order Loops

Ensure order closure loops never iterate forwards:
* `for(int i = 0; i < PositionsTotal(); i++)` is **STRICTLY FORBIDDEN** when closing or deleting orders. Closing ticket `0` shifts ticket `1` into index `0`. The loop counter advances to `1`, permanently skipping the shifted ticket.

---

## 4. Audit Area 2: Broker Execution & Constraint Compliance

### 4.1 Order Stops & Spread Validation

Audit all SL and TP calculations. Brokers define minimum distances from the current price where orders may not be placed or modified:

$$\text{Minimum Distance} = \max\left(\text{SYMBOL\_TRADE\_STOPS\_LEVEL}, \text{SYMBOL\_SPREAD}\right) \times \text{\_Point}$$

Ensure code rejects or adjusts any order where:
$$|\text{OpenPrice} - \text{SL}| < \text{Minimum Distance} \quad \text{or} \quad |\text{OpenPrice} - \text{TP}| < \text{Minimum Distance}$$

### 4.2 Broker Filling Mode Adaptation

Inspect initialization of `CTrade`. MT5 accounts default to `ORDER_FILLING_FOK`. If the broker's liquidity provider only supports `ORDER_FILLING_IOC` or `ORDER_FILLING_RETURN`, market orders fail.

Ensure the code inspects `SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE)` and calls `SetTypeFilling()` accordingly.

---

## 5. Audit Area 3: Algorithmic Complexity & Hot-Path Latency

### 5.1 Scanning `OnTick()` Complexity

Inspect all code called inside `OnTick()`:
* **Time Complexity Target:** Must be strictly **$\mathcal{O}(1)$**.
* **Forbidden Constructs in `OnTick()`:**
  - ❌ Nested loops over price timeseries.
  - ❌ `CopyBuffer()` requesting $> 5$ bars.
  - ❌ Re-instantiating indicator handles via `iCustom()` or `iMA()`.
  - ❌ Unbounded loops (`while(condition) { ... }`).

```mql5
// ❌ REJECT: O(N) linear scan over 5,000 bars inside OnTick()
for(int i = 0; i < 5000; i++)
{
   if(iHigh(_Symbol, PERIOD_CURRENT, i) > highestPrice) ...
}

// ✅ APPROVE: O(1) query using built-in terminal cache
int highestBar = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, 5000, 0);
double highestPrice = iHigh(_Symbol, PERIOD_CURRENT, highestBar);
```

### 5.2 Dynamic Memory Allocation Audit

Search for `new ` and `delete ` across the codebase.
* Any call to `new ` inside `OnTick()`, `OnTimer()`, or `OnCalculate()` is a **blocker**.
* Require zero-allocation stack structs or pre-allocated object pools initialized once in `OnInit()`.

---

## 6. Audit Area 4: Indicator Lifecycles & Synchronous Freezes

### 6.1 The 46.7-Second Synchronous Blocking Freeze

* **Symptom:** Terminal locks up for ~46 seconds when the EA is loaded on a chart.
* **Mechanism:** Calling `CopyBuffer()` before an indicator has calculated its bars forces MT5 into an internal wait loop with a ~46-second timeout.
* **Detection:** Search for every occurrence of `CopyBuffer`.
* **Requirement:** Guard every call with:
  ```mql5
  if(BarsCalculated(handle) < 2)
     return false; // Fast exit; wait for calculation to finish
  ```

### 6.2 The `input group` Parameter Offset Bug in `iCustom`

* **Symptom:** Indicators loaded via `iCustom()` calculate wrong values or receive corrupted parameters.
* **Mechanism:** In MQL5, `input group "..."` declarations count as active `TYPE_STRING` parameter index slots at the compiler level. When an EA calls `iCustom()`, passing parameters by position shifts every argument by the number of preceding `input group` headers.
* **Detection:** Inspect all indicators called by `iCustom()`. If any indicator contains `input group`, it must be replaced with regular comments (`//--- Group Header`).

### 6.3 Indicator Buffer Memory Collapse

* **Symptom:** Indicator loops terminate prematurely without drawing plots.
* **Mechanism:** Managed indicator buffers assigned via `SetIndexBuffer()` return `0` when `ArraySize(buffer)` is called from secondary threads (e.g. `iCustom` instances).
* **Detection:** Look for `ArraySize(buffer)` or `ArrayResize(buffer)` on managed buffers. Loops must be bounded strictly by `rates_total`.

---

## 7. Audit Area 5: UI Responsiveness & GDI Throttling

### 7.1 Visual Creation Hierarchy vs. Click Event Priority

* **The Problem:** In MT5, graphical objects are visually stacked and rendered strictly in the **chronological order of creation**.
* **Review Rule:** Verify the creation sequence:
  1. `OBJ_RECTANGLE_LABEL` (Background) created **first** (`ZORDER = 0`).
  2. `OBJ_LABEL` (Text) created **second** (`ZORDER = 10`).
  3. `OBJ_BUTTON` (Interactive elements) created **last** (`ZORDER = 100`, `SELECTABLE = false`).

### 7.2 GDI Delta Caching

Verify that labels on dashboards are not updated on every tick:
```mql5
// ❌ REJECT: Forces GDI font re-rasterization on every tick
ObjectSetString(0, "Label_Equity", OBJPROP_TEXT, newEquityString);

// ✅ APPROVE: Only touches chart object if text changed
SetLabelIfChanged("Label_Equity", m_cachedEquity, m_cachedColor, newEquityString, newColor);
```

---

## 8. Audit Area 6: Over-Engineering & Architectural Bloat

When reviewing OOP designs in MQL5, watch for "Pattern-itis" that adds cognitive and runtime overhead without benefits.

### Anti-Patterns to Reject:
1. **Inheritance Towers:** Class hierarchies deeper than 2 levels (`BaseEntity` -> `TradingEntity` -> `MarketEntity` -> `SignalEntity` -> `HMASignal`).
   * *Remedy:* Flatten to an interface and concrete implementation (`ISignal` -> `CHMASignal`).
2. **Abstract Factory Factories:** Complex object-generating factories where 1-2 static classes suffice.
3. **Event-Bus Abstractions in `OnTick`:** Routing ticks through generic dynamic subscriber lists rather than calling concrete strategy engines directly.
4. **Premature Microservices in MQL5:** Breaking an EA into 30 tiny header files that each contain 10 lines of code.
5. **Domain Coupling in Shared Headers (Pseudo-Modularity):**
   * *Anti-Pattern:* Placing strategy-specific indicator checks, EA-specific button IDs, or hardcoded coordinates into shared library headers named `PositionManager.mqh` or `GUIHelper.mqh`.
   * *Litmus Test:* Can the shared headers in `mt5/include/` (`SymbolHelper.mqh`, `PositionManager.mqh`, `IndicatorHandle.mqh`, `ChartGUI.mqh`, `ISignal.mqh`) be used in an entirely different EA without a single edit? If not, reject. Strategy logic belongs in an `ISignal` implementation; layout coordinates belong in the EA-specific dashboard.

---

## 9. Automated Verification & CLI Build Commands

Always verify that the code compiles with **0 errors and 0 warnings** using the headless MetaEditor 64-bit compiler.

### Headless Verification Script (PowerShell)

```powershell
$EditorPath = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$SourceFile = "$PSScriptRoot\..\mt5\experts\EA_autotrade.mq5"
$LogFile    = "$PSScriptRoot\..\compile.log"

if (Test-Path $LogFile) { Remove-Item $LogFile }

$Process = Start-Process -FilePath $EditorPath `
  -ArgumentList "/compile:`"$SourceFile`"", "/log:`"$LogFile`"" `
  -Wait -PassThru

$LogContent = Get-Content $LogFile -Raw
Write-Output $LogContent

if ($LogContent -match "0 errors, 0 warnings") {
    Write-Host "✅ Audit Pass: Compilation clean." -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Audit Failure: Compilation errors or warnings detected." -ForegroundColor Red
    exit 1
}
```

