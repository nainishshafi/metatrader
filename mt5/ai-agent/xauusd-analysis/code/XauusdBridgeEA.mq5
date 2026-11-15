//+------------------------------------------------------------------+
//|                                            XauusdBridgeEA.mq5    |
//|  Exports spot, HMA nrp & AutoFibAutoTrend chart state to JSON    |
//+------------------------------------------------------------------+
#property copyright "MT5 AI Agent XAUUSD Analysis"
#property version   "1.30"
#property strict

input string InpHmaPath       = "HMA nrp";        // HMA nrp indicator path (MQL5\Indicators)
input int    InpHmaPeriod     = 21;               // HMA Period
input int    InpTimerSeconds  = 5;                // Export interval (seconds)
input bool   InpExportToFile  = true;             // Write JSON to MQL5\Files

int      g_hHma         = INVALID_HANDLE;
datetime g_lastBarTime  = 0;
bool     g_loggedWait   = false;

string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return EnumToString(tf);
   }
}

string BuildAutoFibJson()
{
   string tfStr   = IntegerToString((int)_Period);
   string fibName = "fib1" + tfStr;
   string chName  = "trend1" + tfStr;

   bool hasFib = (ObjectFind(0, fibName) >= 0);
   bool hasCh  = (ObjectFind(0, chName) >= 0);
   if(!hasFib && !hasCh)
      return "{\"present\":false}";

   double p0 = hasFib ? ObjectGetDouble(0, fibName, OBJPROP_PRICE, 0) : 0.0;
   double p1 = hasFib ? ObjectGetDouble(0, fibName, OBJPROP_PRICE, 1) : 0.0;
   // In MT5 OBJ_FIBO, 0.0% is at anchor_1 (p1) and 100.0% is at anchor_0 (p0)
   double span = p0 - p1;

   return StringFormat(
      "{\"present\":%s,\"anchor_0\":%.2f,\"anchor_1\":%.2f,"
      "\"levels\":{\"0.0\":%.2f,\"23.6\":%.2f,\"38.2\":%.2f,\"50.0\":%.2f,\"61.8\":%.2f,\"78.6\":%.2f,\"100.0\":%.2f,\"161.8\":%.2f},"
      "\"channel_present\":%s}",
      hasFib ? "true" : "false", p0, p1,
      p1, p1 + span * 0.236, p1 + span * 0.382, p1 + span * 0.500, p1 + span * 0.618, p1 + span * 0.786, p0, p1 + span * 1.618,
      hasCh ? "true" : "false"
   );
}

bool CopyHmaTrendSeries(int lookback, double &trendSeries[], int &copied)
{
   ArraySetAsSeries(trendSeries, true);
   copied = CopyBuffer(g_hHma, 4, 0, lookback, trendSeries);
   if(copied >= 2)
      return true;

   double colorSeries[];
   ArraySetAsSeries(colorSeries, true);
   copied = CopyBuffer(g_hHma, 1, 0, lookback, colorSeries);
   if(copied < 2)
      return false;

   ArrayResize(trendSeries, copied);
   ArraySetAsSeries(trendSeries, true);
   for(int i = 0; i < copied; i++)
      trendSeries[i] = (colorSeries[i] == 0.0) ? 1.0 : -1.0;
   return true;
}

int FindHmaFlipShift(const double &trendSeries[], int count, double trendCurr)
{
   for(int i = 0; i < count - 1; i++)
   {
      if(trendSeries[i + 1] != trendCurr)
         return i;
   }
   return -1;
}

string BuildHmaJson()
{
   int calc = (g_hHma != INVALID_HANDLE) ? BarsCalculated(g_hHma) : -1;
   // Guard against MT5's ~46.7s synchronous CopyBuffer wait loop
   if(g_hHma == INVALID_HANDLE || calc < 2)
   {
      if(!g_loggedWait)
      {
         PrintFormat("XauusdBridgeEA: waiting for HMA nrp calculation (BarsCalculated=%d)", calc);
         g_loggedWait = true;
      }
      return StringFormat("{\"ready\":false,\"period\":%d,\"bars_calculated\":%d}", InpHmaPeriod, calc);
   }

   int lookback = MathMin(calc, 200);
   double hmaSeries[];
   ArraySetAsSeries(hmaSeries, true);
   int copiedHma = CopyBuffer(g_hHma, 0, 0, lookback, hmaSeries);
   if(copiedHma < 2)
   {
      PrintFormat("XauusdBridgeEA: CopyBuffer(0) failed err=%d", GetLastError());
      return StringFormat("{\"ready\":false,\"period\":%d,\"bars_calculated\":%d}", InpHmaPeriod, calc);
   }

   double trendSeries[];
   int copiedTrend = 0;
   if(!CopyHmaTrendSeries(lookback, trendSeries, copiedTrend))
      return StringFormat("{\"ready\":false,\"period\":%d,\"bars_calculated\":%d}", InpHmaPeriod, calc);

   int count = MathMin(copiedHma, copiedTrend);
   double trendCurr = trendSeries[0];
   double trendPrev = trendSeries[1];
   int flipShift = FindHmaFlipShift(trendSeries, count, trendCurr);
   int candlesInTrend = (flipShift >= 0) ? (flipShift + 1) : count;

   string flipJson = "{\"found\":false}";
   if(flipShift >= 0)
   {
      datetime flipTime = iTime(_Symbol, _Period, flipShift);
      double flipClose  = iClose(_Symbol, _Period, flipShift);
      double flipOpen   = iOpen(_Symbol, _Period, flipShift);
      double flipHigh   = iHigh(_Symbol, _Period, flipShift);
      double flipLow    = iLow(_Symbol, _Period, flipShift);
      flipJson = StringFormat(
         "{\"found\":true,\"bars_ago\":%d,\"time\":%I64d,\"hma_value\":%.2f,"
         "\"open\":%.2f,\"high\":%.2f,\"low\":%.2f,\"close\":%.2f}",
         flipShift, (long)flipTime, hmaSeries[flipShift],
         flipOpen, flipHigh, flipLow, flipClose
      );
   }

   g_loggedWait = false;
   return StringFormat(
      "{\"ready\":true,\"period\":%d,\"value\":%.2f,\"prev_value\":%.2f,"
      "\"trend\":%.1f,\"prev_trend\":%.1f,\"candles_in_trend\":%d,\"flip_candle\":%s}",
      InpHmaPeriod, hmaSeries[0], hmaSeries[1], trendCurr, trendPrev, candlesInTrend, flipJson
   );
}

string BuildH4CandleJson()
{
   MqlRates h4[];
   ArraySetAsSeries(h4, true);
   int copied = CopyRates(_Symbol, PERIOD_H4, 0, 2, h4);
   if(copied < 2)
      return "{\"present\":false}";

   MqlRates cur  = h4[0];
   MqlRates prev = h4[1];

   bool tookPrevLow  = (cur.low < prev.low);
   bool tookPrevHigh = (cur.high > prev.high);
   bool goingUp      = (cur.close > cur.open);
   bool goingDown    = (cur.close < cur.open);

   bool bullishSweepReversal = (tookPrevLow && cur.close > prev.low && goingUp);
   bool bearishSweepReversal = (tookPrevHigh && cur.close < prev.high && goingDown);

   return StringFormat(
      "{\"present\":true,"
      "\"last_h4\":{\"time\":%I64d,\"open\":%.2f,\"high\":%.2f,\"low\":%.2f,\"close\":%.2f},"
      "\"current_h4\":{\"time\":%I64d,\"open\":%.2f,\"high\":%.2f,\"low\":%.2f,\"close\":%.2f},"
      "\"took_prev_low\":%s,\"going_up\":%s,\"bullish_sweep_reversal\":%s,"
      "\"took_prev_high\":%s,\"going_down\":%s,\"bearish_sweep_reversal\":%s}",
      (long)prev.time, prev.open, prev.high, prev.low, prev.close,
      (long)cur.time, cur.open, cur.high, cur.low, cur.close,
      tookPrevLow ? "true" : "false",
      goingUp ? "true" : "false",
      bullishSweepReversal ? "true" : "false",
      tookPrevHigh ? "true" : "false",
      goingDown ? "true" : "false",
      bearishSweepReversal ? "true" : "false"
   );
}

string BuildSnapshotJson()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   string tfName = TimeframeToString(_Period);

   return StringFormat(
      "{\"symbol\":\"%s\",\"timeframe\":\"%s\",\"time\":%I64d,\"bid\":%.2f,\"ask\":%.2f,"
      "\"hma\":%s,\"autofib\":%s,\"h4_candle\":%s}",
      _Symbol, tfName, (long)TimeCurrent(), bid, ask,
      BuildHmaJson(), BuildAutoFibJson(), BuildH4CandleJson()
   );
}

void ExportSnapshot()
{
   if(!InpExportToFile)
      return;

   string payload = BuildSnapshotJson();
   string filename = StringFormat("xauusd_bridge_%s_%s.json", _Symbol, TimeframeToString(_Period));
   int fh = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("XauusdBridgeEA: FileOpen(%s) failed err=%d", filename, GetLastError());
      return;
   }
   FileWriteString(fh, payload);
   FileClose(fh);
}

int OnInit()
{
   g_loggedWait = false;
   g_hHma = iCustom(_Symbol, _Period, InpHmaPath, _Period, InpHmaPeriod);
   if(g_hHma == INVALID_HANDLE)
   {
      PrintFormat("XauusdBridgeEA: iCustom(%s) failed err=%d", InpHmaPath, GetLastError());
      return INIT_FAILED;
   }
   EventSetTimer(MathMax(1, InpTimerSeconds));
   ExportSnapshot();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_hHma != INVALID_HANDLE)
   {
      IndicatorRelease(g_hHma);
      g_hHma = INVALID_HANDLE;
   }
}

void OnTick()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime != g_lastBarTime)
   {
      g_lastBarTime = barTime;
      ExportSnapshot();
   }
}

void OnTimer()
{
   ExportSnapshot();
}
//+------------------------------------------------------------------+
