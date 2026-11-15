//+------------------------------------------------------------------+
//|                                                  RsiBridgeEA.mq5 |
//|     Exports MT5 built-in iRSI buffer values via File and/or HTTP |
//+------------------------------------------------------------------+
#property copyright "MT5 AI Agent Bridge"
#property version   "1.00"
#property strict

input int    InpRsiPeriod     = 14;                         // RSI Period
input int    InpBarsToExport  = 5;                          // Recent Bars to Export
input int    InpTimerSeconds  = 5;                          // Timer Interval (seconds)
input bool   InpExportToFile  = true;                       // Write JSON to MQL5\Files
input string InpPostUrl       = "http://127.0.0.1:8765/indicator"; // HTTP POST URL (empty to disable)

int      g_rsiHandle = INVALID_HANDLE;
datetime g_lastBarTime = 0;

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

string BuildIndicatorJson()
{
   int count = MathMax(1, InpBarsToExport);
   if(g_rsiHandle == INVALID_HANDLE || BarsCalculated(g_rsiHandle) < count)
      return "";

   double rsi[];
   ArraySetAsSeries(rsi, true);
   int copied = CopyBuffer(g_rsiHandle, 0, 0, count, rsi);
   if(copied <= 0)
   {
      PrintFormat("CopyBuffer failed: err=%d", GetLastError());
      return "";
   }

   string tfStr = TimeframeToString(_Period);
   string valuesJson = "[";
   for(int i = copied - 1; i >= 0; i--)
   {
      datetime barTime = iTime(_Symbol, _Period, i);
      double   closePx = iClose(_Symbol, _Period, i);
      string entry = StringFormat(
         "{\"time\":%I64d,\"close\":%.5f,\"rsi\":%.4f}",
         (long)barTime, closePx, rsi[i]
      );
      valuesJson += entry;
      if(i > 0)
         valuesJson += ",";
   }
   valuesJson += "]";

   string latestEntry = StringFormat(
      "{\"time\":%I64d,\"close\":%.5f,\"rsi\":%.4f}",
      (long)iTime(_Symbol, _Period, 0), iClose(_Symbol, _Period, 0), rsi[0]
   );

   return StringFormat(
      "{\"indicator\":\"RSI\",\"symbol\":\"%s\",\"timeframe\":\"%s\",\"period\":%d,\"latest\":%s,\"values\":%s}",
      _Symbol, tfStr, InpRsiPeriod, latestEntry, valuesJson
   );
}

void WriteSnapshotFile(const string payload)
{
   string filename = StringFormat("rsi_bridge_%s_%s.json", _Symbol, TimeframeToString(_Period));
   int fh = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(fh == INVALID_HANDLE)
   {
      PrintFormat("FileOpen(%s) failed: err=%d", filename, GetLastError());
      return;
   }
   FileWriteString(fh, payload);
   FileClose(fh);
}

void PostSnapshotHttp(const string payload)
{
   if(StringLen(InpPostUrl) == 0)
      return;

   char data[];
   int len = StringToCharArray(payload, data, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0)
      ArrayResize(data, len - 1); // strip null terminator

   char result[];
   string resultHeaders;
   string headers = "Content-Type: application/json\r\n";

   ResetLastError();
   int status = WebRequest("POST", InpPostUrl, headers, 3000, data, result, resultHeaders);
   if(status == -1)
      PrintFormat("WebRequest failed (add URL to MT5 Allowed URLs): err=%d", GetLastError());
}

void PublishSnapshot()
{
   string payload = BuildIndicatorJson();
   if(StringLen(payload) == 0)
      return;

   if(InpExportToFile)
      WriteSnapshotFile(payload);
   if(StringLen(InpPostUrl) > 0)
      PostSnapshotHttp(payload);
}

int OnInit()
{
   g_rsiHandle = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   if(g_rsiHandle == INVALID_HANDLE)
   {
      PrintFormat("iRSI failed: err=%d", GetLastError());
      return INIT_FAILED;
   }
   EventSetTimer(MathMax(1, InpTimerSeconds));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_rsiHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_rsiHandle);
      g_rsiHandle = INVALID_HANDLE;
   }
}

void OnTick()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime != g_lastBarTime)
   {
      g_lastBarTime = barTime;
      PublishSnapshot();
   }
}

void OnTimer()
{
   PublishSnapshot();
}
//+------------------------------------------------------------------+
