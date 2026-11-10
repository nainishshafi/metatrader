# MQL5 Code Writer & Implementation Standard

> **Target Audience:** Quantitative Developers, Algorithmic Traders, and MQL5 Code Authors.  
> **Core Objective:** Provide concrete implementation patterns, clean idiomatic MQL5 code templates, algorithmic complexity rules, and anti-over-engineering guardrails to build high-performance, crash-resilient trading systems.

---

## Table of Contents
1. [Core Architecture & Execution Budget](#1-core-architecture--execution-budget)
2. [Idiomatic MQL5 & Resource Management (RAII)](#2-idiomatic-mql5--resource-management-raii)
3. [Order Execution & Broker Safety Standards](#3-order-execution--broker-safety-standards)
4. [Algorithmic Complexity & Hot-Path Optimization](#4-algorithmic-complexity--hot-path-optimization)
5. [Guardrails Against Over-Engineering ("Pattern-itis")](#5-guardrails-against-over-engineering-pattern-itis)
6. [High-Performance On-Chart UI & Presentation](#6-high-performance-on-chart-ui--presentation)
7. [Complete Production-Ready Code Templates](#7-complete-production-ready-code-templates)

---

## 1. Core Architecture & Execution Budget

Trading software executes in a single-threaded chart loop shared with user input and chart graphics. 

```
                               TICK INFLUX
                        (50 - 200 ticks/sec on Gold)
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        OnTick() Hot-Path Budget                        │
│                         Target: < 1.0 Millisecond                      │
│                                                                        │
│  [Fast-Exit Guards] ──► [O(1) Data Slice] ──► [Deterministic Math]    │
│   Trade Active?          CopyBuffer(2 bars)    No heap allocations     │
│   Position Active?       Stack value types     No linear scans         │
│                                                       │                │
│                                                       ▼                │
│                                              [CTrade Execution]        │
└────────────────────────────────────────────────────────────────────────┘
                                     │
                   (Decoupled from Visual Rendering)
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                    OnTimer() Background Thread (1 Hz)                  │
│                                                                        │
│  [Delta Cache Check] ──► [Update Changed Only] ──► [ChartRedraw(0)]    │
└────────────────────────────────────────────────────────────────────────┘
```

### The Rules of the Hot-Path
1. **Never stall `OnTick()`:** Total execution time per tick must remain below **1.0 millisecond**.
2. **Decouple visuals from execution:** Never call `ChartRedraw(0)` or update chart object properties inside `OnTick()`. UI rendering belongs in `OnTimer()` (at 1 Hz) or in direct response to `OnChartEvent()`.
3. **Fail fast:** If auto-trading is toggled off and no open positions need management, return immediately on line 1 of `OnTick()`.

---

## 2. Idiomatic MQL5 & Resource Management (RAII)

MQL5 is an object-oriented language derived from C++. Use stack allocation and RAII (Resource Acquisition Is Initialization) to manage indicator handles, file handles, and graphical assets.

### 2.1 Encapsulated Indicator Wrapper (RAII)

Indicator handles must be safely allocated, guarded against MT5 thread timeouts, and automatically deallocated upon destruction.

```mql5
//+------------------------------------------------------------------+
//| Safe RAII Indicator Handle Wrapper                               |
//+------------------------------------------------------------------+
class CIndicatorHandle
{
private:
   int              m_handle;
   string           m_symbol;
   ENUM_TIMEFRAMES  m_timeframe;

public:
   CIndicatorHandle() : m_handle(INVALID_HANDLE), m_symbol(""), m_timeframe(PERIOD_CURRENT) {}
   
   ~CIndicatorHandle()
   {
      Release();
   }

   void Release()
   {
      if(m_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_handle);
         m_handle = INVALID_HANDLE;
      }
   }

   bool Attach(const int handle, const string symbol, const ENUM_TIMEFRAMES tf)
   {
      Release();
      m_handle    = handle;
      m_symbol    = symbol;
      m_timeframe = tf;
      return (m_handle != INVALID_HANDLE);
   }

   int  Handle() const { return m_handle; }
   bool IsValid() const { return (m_handle != INVALID_HANDLE); }

   // Guard against the 46.7-second MT5 synchronous freeze
   bool IsReady() const
   {
      return (m_handle != INVALID_HANDLE && BarsCalculated(m_handle) >= 2);
   }
};
```

### 2.2 Parameter Passing Standard
* Pass primitive types (`int`, `double`, `ulong`, `datetime`) **by value**.
* Pass complex objects, strings, arrays, and structs **by `const &` (constant reference)** to eliminate memory copying overhead:
  ```mql5
  // Fast: zero copying overhead
  void ProcessMarketSnapshot(const MqlTick &tick, const string &symbol);
  
  // Slow: copies full string and struct buffers
  void ProcessMarketSnapshot(MqlTick tick, string symbol);
  ```

---

## 3. Order Execution & Broker Safety Standards

### 3.1 Dynamic Volume Normalization

Never use raw arithmetic for lot sizes. Floating point inaccuracies cause broker order rejection.

```mql5
//+------------------------------------------------------------------+
//| Step-quantized, broker-clamped lot calculation                   |
//+------------------------------------------------------------------+
double NormalizeLot(const string symbol, double volume)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxV = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0) step = 0.01;
   if(minV <= 0.0) minV = 0.01;
   if(maxV <= 0.0) maxV = 100.0;

   // Quantize to broker step size
   volume = MathFloor(volume / step) * step;

   // Clamp to broker boundaries
   if(volume < minV) volume = minV;
   if(volume > maxV) volume = maxV;

   int digits = (step >= 0.1) ? 1 : 2;
   return NormalizeDouble(volume, digits);
}
```

### 3.2 Dynamic Broker Order Filling Adaptation

Many ECN and CFD brokers reject default `ORDER_FILLING_FOK` (Fill or Kill) requests. Configure filling modes dynamically:

```mql5
void ConfigureBrokerFilling(CTrade &trade, const string symbol)
{
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   
   if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}
```

### 3.3 Stops & Freeze Level Validation

Always ensure SL and TP distances satisfy the broker's minimum distance requirements to prevent error code `10016` (`TRADE_RETCODE_INVALID_STOPS`).

```mql5
bool ValidateStopsDistance(const string symbol, const double openPrice, const double sl, const double tp)
{
   double stopsLevel = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double spread     = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * _Point;
   double minAllowed = MathMax(stopsLevel, spread);

   if(sl > 0.0 && MathAbs(openPrice - sl) < minAllowed)
      return false;

   if(tp > 0.0 && MathAbs(openPrice - tp) < minAllowed)
      return false;

   return true;
}
```

---

## 4. Algorithmic Complexity & Hot-Path Optimization

### 4.1 Windowed Slicing: $O(1)$ vs. $O(N)$ Buffer Copying

* **Anti-Pattern:** Copying hundreds or thousands of bars on every tick:
  ```mql5
  // WRONG: O(N) allocation and copying across 5,000 bars on every tick
  CopyBuffer(hIndicator, 0, 0, 5000, buffer);
  ```
* **Optimal Pattern:** Query only the active evaluation slice ($O(1)$ time complexity):
  ```mql5
  // RIGHT: O(1) slice of bar 0 (unclosed) and bar 1 (last closed)
  double buffer[2];
  ArraySetAsSeries(buffer, true);
  if(CopyBuffer(hIndicator, 0, 0, 2, buffer) == 2)
  {
     double currentVal  = buffer[0];
     double previousVal = buffer[1];
  }
  ```

### 4.2 Incremental Indicator Calculation Loop

In custom indicators, calculate only new or unclosed bars using `prev_calculated`:

```mql5
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < 2) return 0;

   // O(1) start point for incremental calculation
   int start = prev_calculated - 1;
   if(start < 0) start = 0; // Full calculation on first run only

   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      // Incremental bar calculation
   }
   return rates_total;
}
```

### 4.3 Pre-Allocating Array Memory

Avoid dynamic array resizing without a memory reservation buffer inside calculation loops:

```mql5
// Reserve memory expansion blocks of 1024 elements to prevent reallocations
ArrayResize(workingArray, totalBars, 1024);
```

---

## 5. Guardrails Against Over-Engineering ("Pattern-itis")

When designing MQL5 applications, prioritize **flat composition and zero-cost stack allocations** over deep enterprise OOP hierarchies.

```
                  DESIGN PATTERN SELECTION RUBRIC

┌────────────────────────┬──────────────────────────────────────────────┐
│ Requirement            │ Pragmatic Implementation                     │
├────────────────────────┼──────────────────────────────────────────────┤
│ Multiple Trade Signals │ Flat Strategy Interface (1 level inheritance)│
│ Lot / Risk Sizing      │ Direct Value Struct + Helper Class           │
│ Order Management       │ Encapsulated Position Manager                │
│ Chart Display          │ Delta-Cached Dashboard Component             │
│ Top-Level EA Glue      │ Facade Class (CTradingSystem)                │
└────────────────────────┴──────────────────────────────────────────────┘
```

### 5.1 Prohibition of Heap Allocation on Tick
* **Do NOT call `new` or `delete` in `OnTick()`:** Calling the CRT heap on every price tick creates heap fragmentation, introduces micro-stutters, and risks memory leaks.
* **Do use stack structs or pre-allocated members:**
  ```mql5
  // BAD: Allocates on CRT heap every tick
  CSignalData *sig = new CSignalData();
  // ...
  delete sig;

  // GOOD: Zero-allocation stack struct
  MqlSignalData sig;
  ```

### 5.2 The Rule of Flat Composition
* Avoid inheritance hierarchies deeper than **1 level** (`class CHMASignal : public ISignal`).
* Prefer **has-a** (composition) over **is-a** (inheritance).
* Do not write Abstract Factory Factories, Service Locators, or reflection emulators.

### 5.3 The Two-Tier Architecture Standard (Generic Framework vs. EA-Specific Implementation)

A common mistake is creating "include files" that hardcode EA-specific variables (e.g. putting HMA reversal logic into `PositionManager.mqh`, or hardcoding button coordinates into a GUI helper).

Professional MQL5 codebases enforce a strict two-tier directory separation:

```
┌────────────────────────────────────────────────────────────────────────┐
│ TIER 1: Generic Framework (Reusable across ANY EA or Indicator)        │
│ Location: mt5/include/                                                 │
│                                                                        │
│   ├── Common/SymbolHelper.mqh       --> Step lots, stops, filling modes│
│   ├── Indicators/IndicatorHandle.mqh--> RAII wrapper, 46s freeze guard │
│   ├── Trade/PositionManager.mqh     --> Magic isolation, CloseAll/Half │
│   ├── GUI/ChartGUI.mqh              --> Delta-cached panels/labels/btns│
│   └── Strategy/ISignal.mqh          --> Generic strategy interface     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ (Imported via #include)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ TIER 2: EA-Specific Implementation (Domain & Trading Logic)            │
│ Location: mt5/experts/include/<EAName>/ or mt5/experts/                │
│                                                                        │
│   ├── HMASignal.mqh                 --> Implements ISignal for HMA+M15 │
│   ├── DashboardPanel.mqh            --> Layouts specific buttons/HUD   │
│   ├── TradingSystem.mqh             --> System facade coordinating both│
│   └── EA_autotrade.mq5              --> Lean entry script (< 100 lines)│
└────────────────────────────────────────────────────────────────────────┘
```

#### Reusability Litmus Test:
* If you write a completely different EA tomorrow (e.g., an RSI Mean Reversion EA), can you import `SymbolHelper.mqh`, `PositionManager.mqh`, `IndicatorHandle.mqh`, and `ChartGUI.mqh` **with zero modifications**?
* If the answer is **Yes**, the framework is properly decoupled.
* If you find indicator names, button coordinates, or strategy math inside those headers, **the separation is broken**.

---

## 6. High-Performance On-Chart UI & Presentation

### 6.1 Delta-Cached Label Updates (GDI Throttling)

Calling `ObjectSetString()` on every timer event or tick forces the Windows GDI subsystem to repeatedly re-rasterize font glyphs, causing high CPU usage and dropped mouse clicks.

```mql5
//+------------------------------------------------------------------+
//| Touch chart objects ONLY when text or color actually changes     |
//+------------------------------------------------------------------+
bool SetLabelIfChanged(const string name, string &cacheText, color &cacheColor,
                       const string newText, const color newColor)
{
   bool changed = false;

   if(cacheText != newText)
   {
      ObjectSetString(0, name, OBJPROP_TEXT, newText);
      cacheText = newText;
      changed   = true;
   }

   if(newColor != clrNONE && cacheColor != newColor)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, newColor);
      cacheColor = newColor;
      changed    = true;
   }

   return changed;
}
```

### 6.2 Strict Visual Creation Sequence
To ensure buttons are interactive and not covered by panels:
1. **Background Panels (`OBJ_RECTANGLE_LABEL`):** Create FIRST (`ZORDER = 0`).
2. **Informational Labels (`OBJ_LABEL`):** Create SECOND (`ZORDER = 10`).
3. **Interactive Buttons (`OBJ_BUTTON`):** Create LAST (`ZORDER = 100`, `SELECTABLE = false`).

---

## 7. Complete Production-Ready Code Templates

### 7.1 Abstract Signal Strategy Interface (`ISignal.mqh`)

```mql5
#property copyright "Copyright 2026"
#property strict

enum ENUM_TRADE_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
};

class ISignal
{
public:
   virtual ~ISignal() {}
   virtual bool               Init(const string symbol, const ENUM_TIMEFRAMES tf) = 0;
   virtual void               Deinit() = 0;
   virtual ENUM_TRADE_SIGNAL  CheckSignal() = 0;
   virtual bool               ShouldReverseExit(const ENUM_POSITION_TYPE currentPos) = 0;
};
```

### 7.2 Magic-Isolated Position Manager (`PositionManager.mqh`)

```mql5
#property copyright "Copyright 2026"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CPositionManager
{
private:
   CTrade         m_trade;
   CPositionInfo  m_position;
   string         m_symbol;
   ulong          m_magic;

public:
   CPositionManager() : m_symbol(""), m_magic(0) {}

   bool Init(const string symbol, const ulong magic, const ulong slippage)
   {
      m_symbol = symbol;
      m_magic  = magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage);
      
      // Auto configure broker filling mode
      uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)
         m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((filling & SYMBOL_FILLING_IOC) != 0)
         m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

      return true;
   }

   // Always iterate backwards
   int CloseAllPositions()
   {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_position.SelectByIndex(i))
         {
            // Strict Magic and Symbol Isolation
            if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic)
            {
               if(m_trade.PositionClose(m_position.Ticket()))
                  closed++;
            }
         }
      }
      return closed;
   }

   bool HasOpenPosition()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_position.SelectByIndex(i))
         {
            if(m_position.Symbol() == m_symbol && m_position.Magic() == m_magic)
               return true;
         }
      }
      return false;
   }
};
```

### 7.3 High-Performance Lean EA Shell (`EA_Main.mq5`)

```mql5
#property copyright "Copyright 2026"
#property version   "3.00"

#include <AutoTrade\TradingSystem.mqh>

//--- Inputs
input group "=== Risk Management ==="
input double InpEquityPer1Lot   = 50000.0;
input double InpTakeProfitDist  = 5.0;
input double InpStopLossDist    = 0.0;

input group "=== Magic Numbers ==="
input ulong  InpMagicAuto       = 1234;
input ulong  InpMagicManual     = 9999;
input ulong  InpSlippage        = 30;

//--- Top-Level Facade Instance
CTradingSystem g_system;

int OnInit()
{
   return g_system.Init(InpEquityPer1Lot, InpTakeProfitDist, InpStopLossDist,
                        InpMagicAuto, InpMagicManual, InpSlippage);
}

void OnDeinit(const int reason)
{
   g_system.Deinit(reason);
}

void OnTick()
{
   g_system.OnTick();
}

void OnTimer()
{
   g_system.OnTimer();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   g_system.OnChartEvent(id, lparam, dparam, sparam);
}
```

