# Agent Guidelines: MQL4 to MQL5 Migration & Development

## 1. Project Overview & Repository Structure
This repository contains MetaTrader 4 (MT4) legacy indicators and Expert Advisors (EAs) and their modernized MetaTrader 5 (MT5 / MQL5) counterparts.

```text
mt5-code/
├── mt4/                     # Legacy MT4 source code (.mq4, .mqh)
│   ├── indicators/          # MT4 indicators
│   ├── experts/             # MT4 Expert Advisors (EAs)
│   └── scripts/             # MT4 scripts
├── mt5/                     # Modernized MQL5 code (.mq5, .mqh, compiled .ex5)
│   ├── indicators/          # MT5 indicators
│   ├── experts/             # MT5 Expert Advisors
│   ├── include/             # Shared MQL5 header files
│   └── scripts/             # MT5 scripts
├── reference/               # Reference guides and cheatsheets
│   └── mql5_reference.md    # Comprehensive MQL4 -> MQL5 migration and coding reference
└── agent.md                 # Agent instructions, workflow, and testing procedures (this file)
```

---

## 2. Core Responsibilities & Workflow

Whenever assigned a task (e.g. converting a file, fixing a bug, adding features, or writing new MQL5 code):

1. **Analyze MT4 Source**:
   - Identify the file type (Indicator, Expert Advisor, Script, or Include Library).
   - Trace all entry points (`init`, `deinit`, `start`, `OnCalculate`, `OnTick`).
   - Catalog all input parameters, indicators called (`iCustom`, `iMA`, etc.), chart objects created, and trading actions.
   - Spot legacy bugs or typos in the MT4 source (e.g. invalid object references, infinite loops, missing array boundary checks).

2. **Develop MQL5 Version**:
   - Write modern, idiomatic MQL5 code adhering to MQL5 best practices.
   - Place converted indicators in `mt5/indicators/<Name>.mq5` (and mirror to `mt4/indicators/<Name>.mq5` if requested).
   - Use standard MQL5 event functions: `OnInit()`, `OnDeinit()`, `OnCalculate()`, `OnTick()`.
   - Maintain full functional parity with the original while fixing logic flaws, eliminating buffer overflows, and guaranteeing bounds safety.
   - Provide clean fallbacks (e.g. internal calculation engines if standard external indicator handles fail).

3. **Compile & Verify**:
   - Always compile using the local `MetaEditor64.exe` compiler via CLI.
   - Ensure **`0 errors, 0 warnings`**.
   - Inspect the compiler log to verify clean generation.

4. **Document Output**:
   - Clearly report the files created, structural conversions made, bug fixes applied, and compilation verification status.

---

## 3. MQL5 Coding Standards

- **Strict Mode**: MQL5 is strictly typed. Always ensure variables have explicit types and initialize structures and arrays properly.
- **Header Metadata**:
  ```mql5
  #property copyright   "..."
  #property link        "..."
  #property version     "1.00"
  #property description "..."
  #property indicator_chart_window // or indicator_separate_window
  #property indicator_buffers N
  #property indicator_plots   M
  ```
- **Input Organization**: Use `input group` to organize settings in the MT5 dialog:
  ```mql5
  input group "--- General Settings ---"
  input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; // Timeframe
  ```
- **Array Series Indexing**:
  - In MT4, arrays like `Open[]`, `High[]`, `Low[]`, `Close[]` are timeseries indexed (index 0 is current bar).
  - In MQL5, dynamic arrays are by default indexed oldest-to-newest (index 0 is oldest bar).
  - Always call `ArraySetAsSeries(arr, true)` if you want index 0 to represent the newest bar.
- **Indicator Handles**:
  - Create handles in `OnInit()` with `iCustom()` or technical indicator functions (`iMA()`, `iRSI()`, etc.).
  - Check for `INVALID_HANDLE`.
  - Always release handles in `OnDeinit()` using `IndicatorRelease(handle)`.
- **Chart Objects**:
  - Always specify `chart_id` (typically `0` for current chart).
  - Use `ObjectCreate`, `ObjectMove`, `ObjectSetInteger`, `ObjectSetDouble`, `ObjectSetString`.
  - When setting Fibonacci or Fan levels, remember `OBJPROP_LEVELCOLOR` and `OBJPROP_LEVELWIDTH` require the level index as modifier.
  - Trigger `ChartRedraw(0)` after batch object updates.
- **Resource Cleanup**:
  - Always clean up chart objects and indicator handles in `OnDeinit(const int reason)`.

---

## 4. How to Compile & Test via Command Line

### Local MetaEditor Configuration
- **MetaEditor Executable**: `C:\Program Files\MetaTrader 5\metaeditor64.exe`
- **Terminal Executable**: `C:\Program Files\MetaTrader 5\terminal64.exe`

### Compilation Command (PowerShell)
Execute compilation and capture logs:
```powershell
Start-Process -FilePath "C:\Program Files\MetaTrader 5\metaeditor64.exe" `
  -ArgumentList '/compile:"mt5\indicators\YourIndicator.mq5"', '/log:"compile.log"' `
  -Wait -PassThru
```

### Checking Results
Read the generated `compile.log`:
```powershell
Get-Content "compile.log" -Tail 5
```
Ensure the log ends with:
`Result: 0 errors, 0 warnings`

Always delete temporary `compile.log` files after verifying.

---

## 5. Detailed Reference
For in-depth mappings between MQL4 and MQL5 functions, chart objects, trading logic, and indicator conversions, consult:
- [`reference/mql5_reference.md`](reference/mql5_reference.md)

