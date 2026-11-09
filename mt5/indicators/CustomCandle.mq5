//+------------------------------------------------------------------+
//|                                                 CustomCandle.mq5 |
//|                                    Copyright © 2006, mankurt     |
//|                                              mankurt@freemail.ru |
//+------------------------------------------------------------------+
#property copyright   "Copyright © 2006, mankurt"
#property link        "mankurt@freemail.ru"
#property version     "2.00"
#property description "CustomCandle: Renders higher timeframe candles onto lower timeframe charts."
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input Parameters
//--- Timeframe Settings ---
input ENUM_TIMEFRAMES InpTimeFrame     = PERIOD_H1;          // Higher Timeframe
input int             InpMaxCandles    = 300;                // Max HTF Candles to Draw (0 = All)

//--- Candle Visual Settings ---
input color           InpUpCandle      = clrPaleTurquoise;   // Bullish Candle Color
input color           InpDnCandle      = clrMistyRose;       // Bearish Candle Color
input color           InpDojiColor     = clrYellow;          // Doji Candle Color
input int             InpWidth         = 1;                  // Border & Wick Width
input bool            InpBGCandle      = true;               // Background / Filled Body

//--- Display Settings ---
input bool            InpShowComment   = false;              // Show HTF OHLC in Comment

//--- Global Variables
ENUM_TIMEFRAMES ExtTimeFrame;
string          g_tf_name;
string          g_prefix;
datetime        g_last_htf_time;
double          g_last_open;
double          g_last_high;
double          g_last_low;
double          g_last_close;
int             g_last_copied_count;
bool            g_history_drawn;

//+------------------------------------------------------------------+
//| Validate and convert timeframe from integer/enum                 |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ValidateTimeFrame(int tf)
{
   switch(tf)
   {
      case 1:     return PERIOD_M1;
      case 2:     return PERIOD_M2;
      case 3:     return PERIOD_M3;
      case 4:     return PERIOD_M4;
      case 5:     return PERIOD_M5;
      case 6:     return PERIOD_M6;
      case 10:    return PERIOD_M10;
      case 12:    return PERIOD_M12;
      case 15:    return PERIOD_M15;
      case 20:    return PERIOD_M20;
      case 30:    return PERIOD_M30;
      case 60:    return PERIOD_H1;
      case 120:   return PERIOD_H2;
      case 180:   return PERIOD_H3;
      case 240:   return PERIOD_H4;
      case 360:   return PERIOD_H6;
      case 480:   return PERIOD_H8;
      case 720:   return PERIOD_H12;
      case 1440:  return PERIOD_D1;
      case 10080: return PERIOD_W1;
      case 43200: return PERIOD_MN1;
      default:    return (ENUM_TIMEFRAMES)tf;
   }
}

//+------------------------------------------------------------------+
//| Get readable timeframe name                                      |
//+------------------------------------------------------------------+
string GetTimeFrameName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:
      {
         string s = EnumToString(tf);
         StringReplace(s, "PERIOD_", "");
         return s;
      }
   }
}

//+------------------------------------------------------------------+
//| Get timeframe nominal span in seconds                            |
//+------------------------------------------------------------------+
int GetTimeframeSpanSeconds(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_W1)
      return (5 * 86400); // 5 trading days
   if(tf == PERIOD_MN1)
      return (22 * 86400); // ~22 trading days
   return PeriodSeconds(tf);
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   ExtTimeFrame = ValidateTimeFrame((int)InpTimeFrame);
   g_tf_name    = GetTimeFrameName(ExtTimeFrame);
   g_prefix     = StringFormat("CustomCandle_%s_", g_tf_name);

   int chart_sec = PeriodSeconds(_Period);
   int htf_sec   = PeriodSeconds(ExtTimeFrame);

   if(htf_sec <= chart_sec)
   {
      PrintFormat("CustomCandle Error: InpTimeFrame (%s) must be greater than chart period (%s).",
                  g_tf_name, EnumToString(_Period));
      Comment(StringFormat("\nCustomCandle: TimeFrame (%s) must be greater than chart period (%s)!",
                           g_tf_name, EnumToString(_Period)));
      return(INIT_PARAMETERS_INCORRECT);
   }

   IndicatorSetString(INDICATOR_SHORTNAME, StringFormat("CustomCandle(%s on %s)", g_tf_name, EnumToString(_Period)));

   g_last_htf_time     = 0;
   g_last_open         = 0.0;
   g_last_high         = 0.0;
   g_last_low          = 0.0;
   g_last_close        = 0.0;
   g_last_copied_count = 0;
   g_history_drawn     = false;

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, g_prefix);
   if(InpShowComment)
      Comment("");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Draw or update a single HTF candle (body and wicks)              |
//+------------------------------------------------------------------+
void DrawCandle(int k, const MqlRates &rate, int chart_sec, int span_sec)
{
   string candle_name = g_prefix + "Candle_" + IntegerToString((long)rate.time);

   // Fast skip: closed historical bars (k > 1) never change once created
   if(k > 1 && ObjectFind(0, candle_name) >= 0)
      return;

   datetime t_open   = rate.time;
   datetime t_close  = t_open + (datetime)(span_sec - chart_sec);
   datetime t_shadow = t_open + (datetime)((span_sec - chart_sec) / 2);

   double op = rate.open;
   double cl = rate.close;
   double hi = rate.high;
   double lo = rate.low;

   double body_top    = MathMax(op, cl);
   double body_bottom = MathMin(op, cl);

   color candle_color;
   bool  fill;
   bool  back = true;

   if(op < cl)
   {
      candle_color = InpUpCandle;
      fill         = InpBGCandle;
   }
   else if(op > cl)
   {
      candle_color = InpDnCandle;
      fill         = InpBGCandle;
   }
   else
   {
      candle_color = InpDojiColor;
      fill         = false;
   }

   string wick_h_name = g_prefix + "WickH_" + IntegerToString((long)rate.time);
   string wick_l_name = g_prefix + "WickL_" + IntegerToString((long)rate.time);

   // 1. Candle Body (OBJ_RECTANGLE)
   if(ObjectFind(0, candle_name) < 0)
   {
      ObjectCreate(0, candle_name, OBJ_RECTANGLE, 0, t_open, op, t_close, cl);
      ObjectSetInteger(0, candle_name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, candle_name, OBJPROP_WIDTH, InpWidth);
      ObjectSetInteger(0, candle_name, OBJPROP_BACK, back);
      ObjectSetInteger(0, candle_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, candle_name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, candle_name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, candle_name, OBJPROP_ZORDER, 0);
      ObjectSetString(0, candle_name, OBJPROP_TOOLTIP, "\n");
   }
   else
   {
      ObjectMove(0, candle_name, 0, t_open, op);
      ObjectMove(0, candle_name, 1, t_close, cl);
   }

   ObjectSetInteger(0, candle_name, OBJPROP_COLOR, candle_color);
   ObjectSetInteger(0, candle_name, OBJPROP_FILL, fill);

   // 2. High Wick (OBJ_TREND)
   if(hi > body_top)
   {
      if(ObjectFind(0, wick_h_name) < 0)
      {
         ObjectCreate(0, wick_h_name, OBJ_TREND, 0, t_shadow, body_top, t_shadow, hi);
         ObjectSetInteger(0, wick_h_name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, wick_h_name, OBJPROP_WIDTH, InpWidth);
         ObjectSetInteger(0, wick_h_name, OBJPROP_BACK, back);
         ObjectSetInteger(0, wick_h_name, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, wick_h_name, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, wick_h_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, wick_h_name, OBJPROP_SELECTED, false);
         ObjectSetInteger(0, wick_h_name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, wick_h_name, OBJPROP_ZORDER, 0);
         ObjectSetString(0, wick_h_name, OBJPROP_TOOLTIP, "\n");
      }
      else
      {
         ObjectMove(0, wick_h_name, 0, t_shadow, body_top);
         ObjectMove(0, wick_h_name, 1, t_shadow, hi);
      }
      ObjectSetInteger(0, wick_h_name, OBJPROP_COLOR, candle_color);
   }
   else if(ObjectFind(0, wick_h_name) >= 0)
   {
      ObjectDelete(0, wick_h_name);
   }

   // 3. Low Wick (OBJ_TREND)
   if(lo < body_bottom)
   {
      if(ObjectFind(0, wick_l_name) < 0)
      {
         ObjectCreate(0, wick_l_name, OBJ_TREND, 0, t_shadow, body_bottom, t_shadow, lo);
         ObjectSetInteger(0, wick_l_name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, wick_l_name, OBJPROP_WIDTH, InpWidth);
         ObjectSetInteger(0, wick_l_name, OBJPROP_BACK, back);
         ObjectSetInteger(0, wick_l_name, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, wick_l_name, OBJPROP_RAY_LEFT, false);
         ObjectSetInteger(0, wick_l_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, wick_l_name, OBJPROP_SELECTED, false);
         ObjectSetInteger(0, wick_l_name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, wick_l_name, OBJPROP_ZORDER, 0);
         ObjectSetString(0, wick_l_name, OBJPROP_TOOLTIP, "\n");
      }
      else
      {
         ObjectMove(0, wick_l_name, 0, t_shadow, body_bottom);
         ObjectMove(0, wick_l_name, 1, t_shadow, lo);
      }
      ObjectSetInteger(0, wick_l_name, OBJPROP_COLOR, candle_color);
   }
   else if(ObjectFind(0, wick_l_name) >= 0)
   {
      ObjectDelete(0, wick_l_name);
   }
}

//+------------------------------------------------------------------+
//| Clean up objects older than the oldest displayed candle          |
//+------------------------------------------------------------------+
void CleanupOldObjects(datetime oldest_time)
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_prefix) == 0)
      {
         datetime obj_time = (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0);
         if(obj_time > 0 && obj_time < oldest_time)
         {
            ObjectDelete(0, name);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update chart comment with current HTF OHLC                       |
//+------------------------------------------------------------------+
void UpdateComment(const MqlRates &cur_bar)
{
   if(!InpShowComment)
      return;

   Comment(StringFormat("%s, %s: O=%s, H=%s, L=%s, C=%s",
                        _Symbol, g_tf_name,
                        DoubleToString(cur_bar.open, _Digits),
                        DoubleToString(cur_bar.high, _Digits),
                        DoubleToString(cur_bar.low, _Digits),
                        DoubleToString(cur_bar.close, _Digits)));
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
   if(rates_total < 2)
      return(0);

   int chart_sec = PeriodSeconds(_Period);
   int span_sec  = GetTimeframeSpanSeconds(ExtTimeFrame);
   int htf_sec   = PeriodSeconds(ExtTimeFrame);

   if(htf_sec <= chart_sec)
      return(0);

   int available_htf = iBars(_Symbol, ExtTimeFrame);
   if(available_htf <= 0)
      return(0);

   int bars_to_count = available_htf;
   if(InpMaxCandles > 0 && bars_to_count > InpMaxCandles)
      bars_to_count = InpMaxCandles;

   MqlRates htf_rates[];
   ArraySetAsSeries(htf_rates, true);
   int copied = CopyRates(_Symbol, ExtTimeFrame, 0, bars_to_count, htf_rates);
   if(copied <= 0)
      return(0);

   bool is_new_htf_bar    = (htf_rates[0].time != g_last_htf_time);
   bool count_changed     = (copied != g_last_copied_count);
   bool need_full_rebuild = (prev_calculated == 0 || !g_history_drawn || is_new_htf_bar || count_changed);

   if(need_full_rebuild)
   {
      for(int k = copied - 1; k >= 0; k--)
      {
         DrawCandle(k, htf_rates[k], chart_sec, span_sec);
      }

      if(InpMaxCandles > 0 && copied > 0)
         CleanupOldObjects(htf_rates[copied - 1].time);

      g_last_htf_time     = htf_rates[0].time;
      g_last_open         = htf_rates[0].open;
      g_last_high         = htf_rates[0].high;
      g_last_low          = htf_rates[0].low;
      g_last_close        = htf_rates[0].close;
      g_last_copied_count = copied;
      g_history_drawn     = true;

      UpdateComment(htf_rates[0]);
      return(rates_total);
   }

   // On intra-bar tick: only update bar 0 if prices changed
   if(htf_rates[0].close != g_last_close ||
      htf_rates[0].high  != g_last_high  ||
      htf_rates[0].low   != g_last_low   ||
      htf_rates[0].open  != g_last_open)
   {
      DrawCandle(0, htf_rates[0], chart_sec, span_sec);

      g_last_open  = htf_rates[0].open;
      g_last_high  = htf_rates[0].high;
      g_last_low   = htf_rates[0].low;
      g_last_close = htf_rates[0].close;

      UpdateComment(htf_rates[0]);
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
