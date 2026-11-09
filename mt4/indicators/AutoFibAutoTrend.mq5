//+------------------------------------------------------------------+
//|                                             AutoFibAutoTrend.mq5 |
//|                                                    zzuegg        |
//|                                       when-money-makes-money.com |
//|                                       Converted to MQL5 for MT5  |
//+------------------------------------------------------------------+
#property copyright   "zzuegg"
#property link        "when-money-makes-money.com"
#property version     "1.00"
#property description "AutoFibAutoTrend: Automatic Fibonacci Retracement, Fibonacci Fan, and Trend Channel"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Inputs
input group             "--- General Settings ---"
input ENUM_TIMEFRAMES   InpPeriod           = PERIOD_CURRENT;    // Timeframe
input bool              InpUpdateOnNewBar   = true;              // Update only on new bar (false = every tick)

input group             "--- ZigZag Settings ---"
input int               InpDepth            = 12;                // ZigZag Depth
input int               InpDeviation        = 5;                 // ZigZag Deviation
input int               InpBackstep         = 3;                 // ZigZag Backstep
input string            InpZigZagPath       = "Examples\\ZigZag";// ZigZag indicator path

input group             "--- Fibonacci Retracement ---"
input bool              ShowFib             = true;              // Show Fibonacci Retracement
input color             FibColor            = clrRed;            // Fibonacci Color
input int               FibSize             = 1;                 // Fibonacci Width

input group             "--- Fibonacci Fan ---"
input bool              ShowFibFan          = false;             // Show Fibonacci Fan
input color             FibFanColor         = clrAqua;           // Fibonacci Fan Color
input int               FibFanSize          = 1;                 // Fibonacci Fan Width

input group             "--- Trend Channel ---"
input bool              ShowTrend           = true;              // Show Trend Channel
input color             TrendColor          = clrBlack;          // Trend Channel Color
input int               TrendSize           = 2;                 // Trend Channel Width

//--- Global Variables
string   g_fib1        = "";
string   g_trend       = "";
string   g_fibf1       = "";
int      g_hZigZag     = INVALID_HANDLE;
datetime g_curr_bar    = 0;

//+------------------------------------------------------------------+
//| Get the effective timeframe                                      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES GetEffectiveTimeframe()
  {
   return(InpPeriod == PERIOD_CURRENT ? Period() : InpPeriod);
  }

//+------------------------------------------------------------------+
//| Delete all objects created by this indicator                     |
//+------------------------------------------------------------------+
void DeleteChartObjects()
  {
   if(g_fib1 != "")
      ObjectDelete(0, g_fib1);
   if(g_trend != "")
      ObjectDelete(0, g_trend);
   if(g_fibf1 != "")
      ObjectDelete(0, g_fibf1);
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   ENUM_TIMEFRAMES tf = GetEffectiveTimeframe();
   string tf_str = IntegerToString((int)tf);

   g_fib1  = "fib1" + tf_str;
   g_trend = "trend1" + tf_str;
   g_fibf1 = "fibf1" + tf_str;
   g_curr_bar = 0;

   // Initialize ZigZag handle
   g_hZigZag = iCustom(_Symbol, tf, InpZigZagPath, InpDepth, InpDeviation, InpBackstep);
   if(g_hZigZag == INVALID_HANDLE)
     {
      // Try alternative path without folder
      g_hZigZag = iCustom(_Symbol, tf, "ZigZag", InpDepth, InpDeviation, InpBackstep);
     }

   if(g_hZigZag == INVALID_HANDLE)
     {
      Print("AutoFibAutoTrend: External ZigZag indicator not found. Built-in ZigZag engine will be used.");
     }

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteChartObjects();

   if(g_hZigZag != INVALID_HANDLE)
     {
      IndicatorRelease(g_hZigZag);
      g_hZigZag = INVALID_HANDLE;
     }

   Comment("");
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Fetch swings from external ZigZag indicator handle               |
//+------------------------------------------------------------------+
int GetSwingsFromIndicator(int handle, ENUM_TIMEFRAMES tf, double &values[], datetime &times[])
  {
   if(handle == INVALID_HANDLE)
      return(0);

   int available = iBars(_Symbol, tf);
   if(available < 10)
      return(0);

   int max_bars = 2000;
   if(max_bars > available)
      max_bars = available;

   double zz[];
   ArraySetAsSeries(zz, true);
   int copied = CopyBuffer(handle, 0, 0, max_bars, zz);
   if(copied <= 0)
      return(0);

   datetime dt[];
   ArraySetAsSeries(dt, true);
   if(CopyTime(_Symbol, tf, 0, copied, dt) != copied)
      return(0);

   int found = 0;
   for(int i = 0; i < copied && found < 4; i++)
     {
      if(zz[i] != 0.0 && zz[i] != EMPTY_VALUE)
        {
         values[found] = zz[i];
         times[found]  = dt[i];
         found++;
        }
     }
   return(found);
  }

//+------------------------------------------------------------------+
//| Built-in ZigZag calculation fallback                             |
//+------------------------------------------------------------------+
int GetSwingsInternal(ENUM_TIMEFRAMES tf, int depth, int deviation, int backstep, double &values[], datetime &times[])
  {
   int available = iBars(_Symbol, tf);
   if(available < depth + 1)
      return(0);

   int max_bars = 1000;
   if(max_bars > available)
      max_bars = available;

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(_Symbol, tf, 0, max_bars, rates);
   if(copied < depth + 1)
      return(0);

   double low_map[];
   double high_map[];
   double zz_buffer[];
   ArrayResize(low_map, copied);
   ArrayResize(high_map, copied);
   ArrayResize(zz_buffer, copied);
   ArrayInitialize(low_map, 0.0);
   ArrayInitialize(high_map, 0.0);
   ArrayInitialize(zz_buffer, 0.0);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double last_low = 0.0, last_high = 0.0;

   // 1. Search for high and low extremes
   for(int shift = depth; shift < copied; shift++)
     {
      // Low
      double min_val = rates[shift].low;
      for(int k = shift - 1; k > shift - depth && k >= 0; k--)
        {
         if(rates[k].low < min_val)
            min_val = rates[k].low;
        }

      double val = min_val;
      if(val == last_low)
         val = 0.0;
      else
        {
         last_low = val;
         if((rates[shift].low - val) > deviation * point)
            val = 0.0;
         else
           {
            for(int back = 1; back <= backstep; back++)
              {
               double res = low_map[shift - back];
               if(res != 0.0 && res > val)
                  low_map[shift - back] = 0.0;
              }
           }
        }
      if(rates[shift].low == val)
         low_map[shift] = val;
      else
         low_map[shift] = 0.0;

      // High
      double max_val = rates[shift].high;
      for(int k = shift - 1; k > shift - depth && k >= 0; k--)
        {
         if(rates[k].high > max_val)
            max_val = rates[k].high;
        }

      val = max_val;
      if(val == last_high)
         val = 0.0;
      else
        {
         last_high = val;
         if((val - rates[shift].high) > deviation * point)
            val = 0.0;
         else
           {
            for(int back = 1; back <= backstep; back++)
              {
               double res = high_map[shift - back];
               if(res != 0.0 && res < val)
                  high_map[shift - back] = 0.0;
              }
           }
        }
      if(rates[shift].high == val)
         high_map[shift] = val;
      else
         high_map[shift] = 0.0;
     }

   // 2. Filter peaks and bottoms
   last_low = 0.0;
   last_high = 0.0;
   int last_low_pos = 0;
   int last_high_pos = 0;
   int extreme_search = 0; // 0=undefined, 1=search peak, -1=search bottom

   for(int shift = depth; shift < copied; shift++)
     {
      switch(extreme_search)
        {
         case 0:
            if(last_low == 0.0 && last_high == 0.0)
              {
               if(high_map[shift] != 0.0)
                 {
                  last_high = rates[shift].high;
                  last_high_pos = shift;
                  extreme_search = -1;
                  zz_buffer[shift] = last_high;
                 }
               if(low_map[shift] != 0.0)
                 {
                  last_low = rates[shift].low;
                  last_low_pos = shift;
                  extreme_search = 1;
                  zz_buffer[shift] = last_low;
                 }
              }
            break;

         case 1: // searching for peak
            if(low_map[shift] != 0.0 && low_map[shift] < last_low && high_map[shift] == 0.0)
              {
               zz_buffer[last_low_pos] = 0.0;
               last_low_pos = shift;
               last_low = low_map[shift];
               zz_buffer[shift] = last_low;
              }
            if(high_map[shift] != 0.0 && low_map[shift] == 0.0)
              {
               last_high = high_map[shift];
               last_high_pos = shift;
               zz_buffer[shift] = last_high;
               extreme_search = -1;
              }
            break;

         case -1: // searching for bottom
            if(high_map[shift] != 0.0 && high_map[shift] > last_high && low_map[shift] == 0.0)
              {
               zz_buffer[last_low_pos] = 0.0;
               last_low_pos = shift;
               last_high = high_map[shift];
               zz_buffer[shift] = last_high;
              }
            if(low_map[shift] != 0.0 && high_map[shift] == 0.0)
              {
               last_low = low_map[shift];
               last_low_pos = shift;
               zz_buffer[shift] = last_low;
               extreme_search = 1;
              }
            break;
        }
     }

   // 3. Extract last 4 swings from the end (newest to oldest)
   int found = 0;
   for(int shift = copied - 1; shift >= 0 && found < 4; shift--)
     {
      if(zz_buffer[shift] != 0.0)
        {
         values[found] = zz_buffer[shift];
         times[found]  = rates[shift].time;
         found++;
        }
     }
   return(found);
  }

//+------------------------------------------------------------------+
//| Get swings with automatic indicator/fallback resolution          |
//+------------------------------------------------------------------+
int GetSwings(ENUM_TIMEFRAMES tf, double &values[], datetime &times[])
  {
   int found = 0;
   if(g_hZigZag != INVALID_HANDLE)
      found = GetSwingsFromIndicator(g_hZigZag, tf, values, times);

   if(found < 4)
     {
      int fallback_found = GetSwingsInternal(tf, InpDepth, InpDeviation, InpBackstep, values, times);
      if(fallback_found > found)
         found = fallback_found;
     }

   return(found);
  }

//+------------------------------------------------------------------+
//| Update Equidistant Channel object                                |
//+------------------------------------------------------------------+
void UpdateTrendChannel(datetime t1, double p1, datetime t2, double p2, datetime t3, double p3)
  {
   if(!ShowTrend)
     {
      ObjectDelete(0, g_trend);
      return;
     }

   if(ObjectFind(0, g_trend) < 0)
     {
      ObjectCreate(0, g_trend, OBJ_CHANNEL, 0, t1, p1, t2, p2, t3, p3);
     }
   else
     {
      ObjectMove(0, g_trend, 0, t1, p1);
      ObjectMove(0, g_trend, 1, t2, p2);
      ObjectMove(0, g_trend, 2, t3, p3);
     }

   ObjectSetInteger(0, g_trend, OBJPROP_COLOR, TrendColor);
   ObjectSetInteger(0, g_trend, OBJPROP_WIDTH, TrendSize);
   ObjectSetInteger(0, g_trend, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, g_trend, OBJPROP_RAY_RIGHT, true);
  }

//+------------------------------------------------------------------+
//| Update Fibonacci Retracement object                              |
//+------------------------------------------------------------------+
void UpdateFibonacci(datetime t1, double p1, datetime t2, double p2)
  {
   if(!ShowFib)
     {
      ObjectDelete(0, g_fib1);
      return;
     }

   if(ObjectFind(0, g_fib1) < 0)
     {
      ObjectCreate(0, g_fib1, OBJ_FIBO, 0, t1, p1, t2, p2);
     }
   else
     {
      ObjectMove(0, g_fib1, 0, t1, p1);
      ObjectMove(0, g_fib1, 1, t2, p2);
     }

   ObjectSetInteger(0, g_fib1, OBJPROP_COLOR, FibColor);
   ObjectSetInteger(0, g_fib1, OBJPROP_WIDTH, FibSize);
   ObjectSetInteger(0, g_fib1, OBJPROP_RAY_RIGHT, true);

   int levels = (int)ObjectGetInteger(0, g_fib1, OBJPROP_LEVELS);
   for(int i = 0; i < levels; i++)
     {
      ObjectSetInteger(0, g_fib1, OBJPROP_LEVELCOLOR, i, FibColor);
      ObjectSetInteger(0, g_fib1, OBJPROP_LEVELWIDTH, i, FibSize);
     }
  }

//+------------------------------------------------------------------+
//| Update Fibonacci Fan object                                      |
//+------------------------------------------------------------------+
void UpdateFibonacciFan(datetime t1, double p1, datetime t2, double p2)
  {
   if(!ShowFibFan)
     {
      ObjectDelete(0, g_fibf1);
      return;
     }

   if(ObjectFind(0, g_fibf1) < 0)
     {
      ObjectCreate(0, g_fibf1, OBJ_FIBOFAN, 0, t1, p1, t2, p2);
     }
   else
     {
      ObjectMove(0, g_fibf1, 0, t1, p1);
      ObjectMove(0, g_fibf1, 1, t2, p2);
     }

   ObjectSetInteger(0, g_fibf1, OBJPROP_COLOR, FibFanColor);
   ObjectSetInteger(0, g_fibf1, OBJPROP_WIDTH, FibFanSize);

   int levels = (int)ObjectGetInteger(0, g_fibf1, OBJPROP_LEVELS);
   for(int i = 0; i < levels; i++)
     {
      ObjectSetInteger(0, g_fibf1, OBJPROP_LEVELCOLOR, i, FibFanColor);
      ObjectSetInteger(0, g_fibf1, OBJPROP_LEVELWIDTH, i, FibFanSize);
     }
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
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
   ENUM_TIMEFRAMES tf = GetEffectiveTimeframe();

   datetime bar_time = iTime(_Symbol, tf, 0);
   if(bar_time == 0)
      return(prev_calculated);

   if(prev_calculated == 0)
      g_curr_bar = 0;

   if(InpUpdateOnNewBar && g_curr_bar == bar_time)
      return(rates_total);

   g_curr_bar = bar_time;

   double   swing_value[4] = {0, 0, 0, 0};
   datetime swing_date[4]  = {0, 0, 0, 0};

   int found = GetSwings(tf, swing_value, swing_date);

   // Trend Channel uses swings 3, 1, 2
   if(found >= 4 && ShowTrend)
     {
      UpdateTrendChannel(swing_date[3], swing_value[3], swing_date[1], swing_value[1], swing_date[2], swing_value[2]);
     }
   else if(!ShowTrend || found < 4)
     {
      ObjectDelete(0, g_trend);
     }

   // Fibonacci Retracement uses swings 2, 1
   if(found >= 3 && ShowFib)
     {
      UpdateFibonacci(swing_date[2], swing_value[2], swing_date[1], swing_value[1]);
     }
   else if(!ShowFib || found < 3)
     {
      ObjectDelete(0, g_fib1);
     }

   // Fibonacci Fan uses swings 2, 1
   if(found >= 3 && ShowFibFan)
     {
      UpdateFibonacciFan(swing_date[2], swing_value[2], swing_date[1], swing_value[1]);
     }
   else if(!ShowFibFan || found < 3)
     {
      ObjectDelete(0, g_fibf1);
     }

   Comment("");
   ChartRedraw(0);
   return(rates_total);
  }
//+------------------------------------------------------------------+

