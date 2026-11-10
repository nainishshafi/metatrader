# MQL5 Complete Reference & MQL4-to-MQL5 Migration Manual

This document provides a comprehensive guide for writing, converting, and testing MQL5 code, with detailed mappings from legacy MQL4.

---

## Table of Contents
1. [MQL4 vs MQL5 Architecture Overview](#1-mql4-vs-mql5-architecture-overview)
2. [Program Types & Lifecycle Event Handlers](#2-program-types--lifecycle-event-handlers)
3. [Input Parameters & Data Types](#3-input-parameters--data-types)
4. [Timeseries & Price Data Access](#4-timeseries--price-data-access)
5. [Technical Indicators & Buffer Handling](#5-technical-indicators--buffer-handling)
6. [Graphical & Chart Objects](#6-graphical--chart-objects)
7. [Trading Operations: EAs & Scripts](#7-trading-operations-eas--scripts)
8. [Standard Library Helpers](#8-standard-library-helpers)
9. [How to Compile and Test](#9-how-to-compile-and-test)
10. [Common Pitfalls & Best Practices](#10-common-pitfalls--best-practices)

---

## 1. MQL4 vs MQL5 Architecture Overview

| Concept | MQL4 | MQL5 |
| :--- | :--- | :--- |
| **Execution Model** | 32-bit single-threaded | Native 64-bit multi-threaded, highly optimized |
| **Indicator Data** | Buffers double as both calculation & display storage | Clear separation between `INDICATOR_DATA` and `INDICATOR_CALCULATIONS` |
| **Technical Indicators** | Called synchronously per bar: `iMA(..., shift)` | Handle-based: `handle = iMA(...)` created once, then data fetched via `CopyBuffer()` |
| **Price Data Arrays** | Predefined `Open[]`, `Close[]`, `Time[]` (series index 0 = current bar) | Dynamic arrays or `OnCalculate` arrays, default index 0 = oldest bar (`ArraySetAsSeries` needed for series index) |
| **Trading System** | Single-step `OrderSend()` returning ticket | Asynchronous or synchronous orders with Position/Order/Deal separation (Hedging & Netting modes) |
| **Chart Objects** | Global object functions (`ObjectCreate`, `ObjectSet`) without chart ID | Chart ID aware (`0` = current chart), explicit integer/double/string setters |

---

## 2. Program Types & Lifecycle Event Handlers

### A. Custom Indicators

Indicators execute inside the chart interface thread and calculate values for plots or chart visual aids.

#### Properties Setup
```mql5
#property copyright   "Author"
#property link        "https://example.com"
#property version     "1.00"
#property indicator_chart_window   // Or indicator_separate_window
#property indicator_buffers 2      // Total memory buffers (calculations + plots)
#property indicator_plots   1      // Buffers actually drawn on chart

// Plot 1 definition
#property indicator_label1  "Fast Line"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
```

#### Event Handlers
```mql5
// 1. Initialization
int OnInit()
{
   // Map buffer 0 to Plot 1 (visible)
   SetIndexBuffer(0, ExtFastBuffer, INDICATOR_DATA);
   // Map buffer 1 for internal math only (hidden)
   SetIndexBuffer(1, ExtCalcBuffer, INDICATOR_CALCULATIONS);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   return(INIT_SUCCEEDED);
}

// 2. Deinitialization
void OnDeinit(const int reason)
{
   // Release indicator handles and clean up created chart objects
   if(hIndicator != INVALID_HANDLE)
      IndicatorRelease(hIndicator);
   ObjectsDeleteAll(0, "Prefix_");
}

// 3. Calculation Loop (Short Form)
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
   if(rates_total < 2)
      return(0);

   int start = prev_calculated - 1;
   if(start < 0)
      start = 0;

   for(int i = start; i < rates_total && !IsStopped(); i++)
   {
      ExtFastBuffer[i] = (high[i] + low[i]) / 2.0;
   }
   return(rates_total);
}
```

---

### B. Expert Advisors (EAs)

```mql5
int OnInit()
{
   // Setup trading handles, timers, and validations
   EventSetTimer(1); // 1-second timer
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTick()
{
   // Core tick logic: market analysis, signal generation, trade execution
}

void OnTimer()
{
   // Background / periodic maintenance (e.g. trailing stops, heartbeat)
}

void OnTrade()
{
   // Triggered when an order/position/deal state changes
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   // Detailed trade execution event (executions, modifications, SL/TP triggers)
}
```

---

### C. Scripts

Scripts execute sequentially in a single pass on demand.

```mql5
#property script_show_inputs

input double InpLotSize = 0.10;

void OnStart()
{
   Print("Script running on: ", _Symbol, " | Lot: ", InpLotSize);
}
```

---

## 3. Input Parameters & Data Types

### Parameter Grouping and Types
In MT4, inputs were declared as `extern` or `input`. In MQL5, use `input` and group them visually with `input group`:

```mql5
input group "=== Trading Settings ==="
input double          InpLotSize     = 0.10;           // Trade Lot Size
input int             InpStopLoss    = 50;             // Stop Loss (Points)
input int             InpTakeProfit  = 100;            // Take Profit (Points)

input group "=== Indicator Settings ==="
input ENUM_TIMEFRAMES InpTimeframe   = PERIOD_CURRENT; // Calculation Timeframe
input int             InpMAPeriod    = 20;             // MA Period
input ENUM_MA_METHOD  InpMAMethod    = MODE_SMA;       // MA Method
input ENUM_APPLIED_PRICE InpPrice    = PRICE_CLOSE;    // Applied Price

input group "=== Visuals ==="
input color           InpLineColor   = clrCrimson;     // Line Color
input int             InpLineWidth   = 2;              // Line Width
```

### Timeframe Conversion Table
| MT4 (Integer / Predefined) | MQL5 `ENUM_TIMEFRAMES` | Description |
| :--- | :--- | :--- |
| `0` or `PERIOD_CURRENT` | `PERIOD_CURRENT` | Current chart period |
| `1` | `PERIOD_M1` | 1 Minute |
| `5` | `PERIOD_M5` | 5 Minutes |
| `15` | `PERIOD_M15` | 15 Minutes |
| `30` | `PERIOD_M30` | 30 Minutes |
| `60` | `PERIOD_H1` | 1 Hour |
| `240` | `PERIOD_H4` | 4 Hours |
| `1440` | `PERIOD_D1` | Daily |
| `10080` | `PERIOD_W1` | Weekly |
| `43200` | `PERIOD_MN1` | Monthly |
| — | `PERIOD_M2`, `M3`, `M4`, `M6`, `M10`, `M12`, `M20`, `H2`, `H3`, `H6`, `H8`, `H12` | MQL5 extended timeframes |

---

## 4. Timeseries & Price Data Access

### Array Direction: Standard vs Series Indexing

- **Default MQL5 Array**: Index `0` is the **oldest** element; index `N - 1` is the newest element.
- **Timeseries Mode (like MT4)**: Index `0` is the **newest** (current/unclosed) bar.
- Use `ArraySetAsSeries(arr, true)` to switch an array to timeseries mode.

### Accessing Price Values

#### Method 1: Using Convenience Functions (Build 1860+)
```mql5
datetime bar_time  = iTime(_Symbol, PERIOD_CURRENT, 0); // Bar 0 time
double   bar_open  = iOpen(_Symbol, PERIOD_CURRENT, 0);
double   bar_high  = iHigh(_Symbol, PERIOD_CURRENT, 0);
double   bar_low   = iLow(_Symbol, PERIOD_CURRENT, 0);
double   bar_close = iClose(_Symbol, PERIOD_CURRENT, 0);
long     bar_vol   = iVolume(_Symbol, PERIOD_CURRENT, 0);
int      bars      = iBars(_Symbol, PERIOD_CURRENT);
```

#### Method 2: High-Performance Batch Copy (`CopyRates`, `CopyBuffer`)
```mql5
// Copy last 100 completed bars into series array
MqlRates rates[];
ArraySetAsSeries(rates, true);
int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, 100, rates);

if(copied > 0)
{
   // rates[0] is current bar, rates[1] is previous bar
   double close1 = rates[1].close;
   datetime time1 = rates[1].time;
}
```

---

## 5. Technical Indicators & Buffer Handling

### The MT4 vs MQL5 Indicator Paradigm

- **MT4 Model**:
  ```mql4
  // Calculated on every tick for bar shift i
  double val = iMA(Symbol(), Period(), 14, 0, MODE_SMA, PRICE_CLOSE, i);
  double cval = iCustom(Symbol(), Period(), "MyInd", param1, param2, buffer_index, i);
  ```

- **MQL5 Model**:
  ```mql5
  // 1. Create Handle in OnInit()
  int hMA = iMA(_Symbol, InpTimeframe, 14, 0, MODE_SMA, PRICE_CLOSE);
  int hCustom = iCustom(_Symbol, InpTimeframe, "Examples\\ZigZag", 12, 5, 3);

  // 2. Read Values in OnCalculate() or OnTick()
  double ma_values[];
  ArraySetAsSeries(ma_values, true);
  if(CopyBuffer(hMA, 0, 0, 3, ma_values) == 3)
  {
     double current_ma  = ma_values[0]; // Bar 0
     double previous_ma = ma_values[1]; // Bar 1
  }

  // 3. Release in OnDeinit()
  IndicatorRelease(hMA);
  IndicatorRelease(hCustom);
  ```

### Handling Custom Indicator Sub-Paths
In MT5, indicators shipped in subfolders (such as `MQL5\Indicators\Examples\ZigZag.mq5`) require the path prefix:
```mql5
handle = iCustom(_Symbol, tf, "Examples\\ZigZag", InpDepth, InpDeviation, InpBackstep);
if(handle == INVALID_HANDLE)
   handle = iCustom(_Symbol, tf, "ZigZag", InpDepth, InpDeviation, InpBackstep);
```

---

## 6. Graphical & Chart Objects

### Function Mapping

| Operation | MQL4 | MQL5 |
| :--- | :--- | :--- |
| **Create** | `ObjectCreate(name, OBJ_*, win, t1, p1, ...)` | `ObjectCreate(chart_id, name, OBJ_*, win, t1, p1, ...)` |
| **Move Anchor** | `ObjectMove(name, point, time, price)` | `ObjectMove(chart_id, name, point, time, price)` |
| **Delete** | `ObjectDelete(name)` | `ObjectDelete(chart_id, name)` |
| **Delete All** | `ObjectsDeleteAll(win, OBJ_*)` | `ObjectsDeleteAll(chart_id, prefix_or_win, sub_win, type)` |
| **Set Integer** | `ObjectSet(name, OBJPROP_COLOR, val)` | `ObjectSetInteger(chart_id, name, OBJPROP_COLOR, val)` |
| **Set Double** | `ObjectSet(name, OBJPROP_PRICE1, val)` | `ObjectSetDouble(chart_id, name, OBJPROP_PRICE1, val)` |
| **Set String** | `ObjectSetText(name, text, size, font, col)` | `ObjectSetString(chart_id, name, OBJPROP_TEXT, text)` |
| **Redraw** | `WindowRedraw()` | `ChartRedraw(chart_id)` |

### Setting Object Levels (Fibo, Fans, Channels)
In MT4, setting level properties applied globally:
```mql4
ObjectSet("Fib1", OBJPROP_LEVELCOLOR, Red); // MT4
```

In MQL5, `OBJPROP_LEVELCOLOR`, `OBJPROP_LEVELWIDTH`, and `OBJPROP_LEVELSTYLE` **require the level index as the modifier**:
```mql5
int total_levels = (int)ObjectGetInteger(0, "Fib1", OBJPROP_LEVELS);
for(int l = 0; l < total_levels; l++)
{
   ObjectSetInteger(0, "Fib1", OBJPROP_LEVELCOLOR, l, clrRed);
   ObjectSetInteger(0, "Fib1", OBJPROP_LEVELWIDTH, l, 1);
}
```

---

## 7. Trading Operations: EAs & Scripts

### Positions vs Orders vs Deals in MT5
- **Order**: A pending request or instruction to execute a trade.
- **Deal**: The physical transaction that occurred (trade executed).
- **Position**: The current open market exposure resulting from one or more deals.
  - In **Netting** mode, each symbol has at most 1 combined position.
  - In **Hedging** mode, multiple simultaneous long and short positions can coexist on the same symbol (like MT4).

### Using the Standard `CTrade` Class (Recommended)
Instead of manually populating `MqlTradeRequest` and `MqlTradeResult` structures, include `<Trade\Trade.mqh>`:

```mql5
#include <Trade\Trade.mqh>
CTrade trade;

int OnInit()
{
   trade.SetExpertMagicNumber(123456);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // Open Buy
   if(BuySignal())
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      trade.Buy(0.10, _Symbol, ask, ask - 100 * _Point, ask + 200 * _Point, "Buy Order");
   }

   // Close Position (Safe backward iteration with Magic Number isolation & linear guards)
   if(CloseSignal())
   {
      CPositionInfo pos;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!pos.SelectByIndex(i)) continue;
         if(pos.Symbol() != _Symbol || pos.Magic() != 123456) continue;
         trade.PositionClose(pos.Ticket());
      }
   }
}
```

---

## 8. Standard Library Helpers

MT5 includes built-in object-oriented libraries in `MQL5\Include\`:
- `<Trade\Trade.mqh>`: `CTrade` for order execution.
- `<Trade\PositionInfo.mqh>`: `CPositionInfo` for querying open positions.
- `<Trade\OrderInfo.mqh>`: `COrderInfo` for querying pending orders.
- `<Trade\AccountInfo.mqh>`: `CAccountInfo` for balance, equity, margin info.
- `<Trade\SymbolInfo.mqh>`: `CSymbolInfo` for bid, ask, point, spread, tick size info.
- `<ChartObjects\ChartObjectsLines.mqh>`: Managed wrapper classes for trendlines, channels, fibos.

---

## 9. How to Compile and Test

### Command Line Compilation
MetaEditor 64-bit supports headless command-line compilation:

```powershell
# Syntax:
# metaeditor64.exe /compile:"<source_file>" /log:"<output_log>"

Start-Process -FilePath "C:\Program Files\MetaTrader 5\metaeditor64.exe" `
  -ArgumentList '/compile:"mt5\indicators\AutoFibAutoTrend.mq5"', '/log:"compile.log"' `
  -Wait -PassThru
```

### Automated Verification Script (PowerShell)
You can test any file using this snippet:
```powershell
param([string]$FilePath)

$Editor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$Log = "$PSScriptRoot\compile_temp.log"

Start-Process -FilePath $Editor -ArgumentList "/compile:`"$FilePath`"", "/log:`"$Log`"" -Wait
Get-Content $Log
Remove-Item $Log -ErrorAction SilentlyContinue
```

---

## 10. Common Pitfalls & Best Practices

1. **Array Timeseries Default Direction**:
   - Always remember: `CopyBuffer` and `CopyRates` fill index `0` with the oldest bar unless `ArraySetAsSeries(arr, true)` is invoked beforehand!

2. **Handle Leaks**:
   - Every `iCustom` or `iMA` handle must be released in `OnDeinit` with `IndicatorRelease(handle)`. Neglecting this leaves the indicator calculating in the background.

3. **External Indicator Dependencies**:
   - If calling external indicators via `iCustom`, provide a graceful fallback (such as an embedded math engine) in case the target `.ex5` is absent on the user's terminal.

4. **Division by Zero with Points**:
   - On newly opened charts or synthetic instruments, `_Point` or `_Digits` may not be immediately initialized on tick 0. Check `SymbolInfoDouble(_Symbol, SYMBOL_POINT) > 0`.

5. **Loop Bounds & Limited History**:
   - Never write unbounded loops like `while(found < 4) { i++; }`. Check `i < bars_count` so the loop terminates gracefully when history is limited.

6. **Chart Redraw**:
   - When programmatically modifying chart objects, call `ChartRedraw(0)` once at the conclusion of calculations to reflect updates immediately without visual stutter.

