//+------------------------------------------------------------------+
//|                               BreakOut_PANCA_EAGLE__indicator.mq5|
//|                                                        hapalkos  |
//|                                                       2007.11.20 |
//|                                  Converted to MQL5 for MT5 (2026)|
//|   ++ modified so that rectangles do not overlay                  |
//|   ++ this makes color selection more versatile                   |
//|   ++ code consolidated & modernized                              |
//+------------------------------------------------------------------+
#property copyright   "hapalkos"
#property link        ""
#property version     "1.00"
#property description "BreakOut PANCA-EAGLE session breakout indicator"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Input parameters
//--- Session Time Settings ---
input int               NumberOfDays        = 50;           // Number of days to display
input string            periodBegin         = "00:00";      // Session start time (HH:MM)
input string            periodEnd           = "05:30";      // Session end time (HH:MM)
input string            BoxEnd              = "23:00";      // Breakout box end time (HH:MM)
input int               BoxBreakOut_Offset  = 10;           // Breakout offset (in points)

//--- Box Colors ---
input color             BoxHLColor          = clrNONE;      // High-Low Box Color (clrNONE = none)
input color             BoxBreakOutColor    = clrLimeGreen; // Breakout Boxes Color
input color             BoxPeriodColor      = clrOrangeRed; // Period Border Box Color

//--- Performance Settings ---
input bool              InpUpdateOnNewBar   = true;         // Update on new bar only (false = every tick)

//--- Constants
const string PREFIX = "PANCA_";

//--- Global Variables
datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_last_bar_time = 0;
   DeleteObjects();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteObjects();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Remove all indicator rectangles                                  |
//+------------------------------------------------------------------+
void DeleteObjects()
  {
   ObjectsDeleteAll(0, PREFIX);
  }

//+------------------------------------------------------------------+
//| Get day of week (0=Sunday, 1=Monday, ..., 6=Saturday)            |
//+------------------------------------------------------------------+
int GetDayOfWeek(datetime dt)
  {
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   return(mdt.day_of_week);
  }

//+------------------------------------------------------------------+
//| Decrement date by 24 hours                                       |
//+------------------------------------------------------------------+
datetime DecrementTradeDate(datetime dt)
  {
   return(dt - 86400);
  }

//+------------------------------------------------------------------+
//| Find highest high and lowest low in session time range           |
//+------------------------------------------------------------------+
bool GetSessionHighLow(datetime t_start, datetime t_end, double &high_val, double &low_val)
  {
   double highs[];
   double lows[];

   int count_h = CopyHigh(_Symbol, PERIOD_CURRENT, t_start, t_end, highs);
   int count_l = CopyLow(_Symbol, PERIOD_CURRENT, t_start, t_end, lows);

   if(count_h <= 0 || count_l <= 0)
      return(false);

   int max_idx = ArrayMaximum(highs);
   int min_idx = ArrayMinimum(lows);

   if(max_idx < 0 || min_idx < 0)
      return(false);

   high_val = highs[max_idx];
   low_val  = lows[min_idx];
   return(true);
  }

//+------------------------------------------------------------------+
//| Create or update a Rectangle object                              |
//+------------------------------------------------------------------+
void DrawObject(string sObjName, datetime dtTime1, datetime dtTime2, double dPrice1, double dPrice2, color cObjColor, int iOffSet, int iForm, double dPriceHigh, double dPriceLow)
  {
   if(cObjColor == clrNONE && iForm == 1)
     {
      ObjectDelete(0, sObjName);
      return;
     }

   if(ObjectFind(0, sObjName) < 0)
     {
      ObjectCreate(0, sObjName, OBJ_RECTANGLE, 0, dtTime1, dPrice1, dtTime2, dPrice2);
     }
   else
     {
      ObjectMove(0, sObjName, 0, dtTime1, dPrice1);
      ObjectMove(0, sObjName, 1, dtTime2, dPrice2);
     }

   ObjectSetInteger(0, sObjName, OBJPROP_COLOR, cObjColor);
   ObjectSetInteger(0, sObjName, OBJPROP_STYLE, STYLE_SOLID);

   if(iForm == 4) // Period border box
     {
      ObjectSetInteger(0, sObjName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, sObjName, OBJPROP_BACK, false);
      ObjectSetInteger(0, sObjName, OBJPROP_FILL, false);
     }
   else // Breakout & HL boxes
     {
      ObjectSetInteger(0, sObjName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, sObjName, OBJPROP_BACK, true);
      ObjectSetInteger(0, sObjName, OBJPROP_FILL, true);
     }

   ObjectSetInteger(0, sObjName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, sObjName, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, sObjName, OBJPROP_HIDDEN, true);

   string sObjDesc = StringFormat("High: %.*f  Low: %.*f  OffSet: %d", _Digits, dPriceHigh, _Digits, dPriceLow, iOffSet);
   ObjectSetString(0, sObjName, OBJPROP_TEXT, sObjDesc);
   ObjectSetString(0, sObjName, OBJPROP_TOOLTIP, sObjDesc);
  }

//+------------------------------------------------------------------+
//| Process and draw breakout boxes for a specific trade date        |
//+------------------------------------------------------------------+
void ProcessDay(datetime dtTradeDate, double offset)
  {
   string date_str = TimeToString(dtTradeDate, TIME_DATE);
   datetime dtTimeBegin  = StringToTime(date_str + " " + periodBegin);
   datetime dtTimeEnd    = StringToTime(date_str + " " + periodEnd);
   datetime dtTimeObjEnd = StringToTime(date_str + " " + BoxEnd);

   if(dtTimeEnd <= dtTimeBegin)
      dtTimeEnd += 86400;

   if(dtTimeObjEnd <= dtTimeBegin)
      dtTimeObjEnd += 86400;

   double dPriceHigh = 0.0, dPriceLow = 0.0;
   if(!GetSessionHighLow(dtTimeBegin, dtTimeEnd, dPriceHigh, dPriceLow))
      return;

   string date_tag = date_str;
   StringReplace(date_tag, ".", "_");

   string name_hl      = PREFIX + "BoxHL_" + date_tag;
   string name_bo_high = PREFIX + "BoxBreakOut_High_" + date_tag;
   string name_bo_low  = PREFIX + "BoxBreakOut_Low_" + date_tag;
   string name_period  = PREFIX + "BoxPeriod_" + date_tag;

   // 1. High-Low Box (inner range)
   DrawObject(name_hl, dtTimeBegin, dtTimeObjEnd, dPriceHigh, dPriceLow, BoxHLColor, 0, 1, dPriceHigh, dPriceLow);

   // 2. Upper BreakOut Box (High to High + Offset)
   DrawObject(name_bo_high, dtTimeBegin, dtTimeObjEnd, dPriceHigh, dPriceHigh + offset, BoxBreakOutColor, BoxBreakOut_Offset, 2, dPriceHigh, dPriceLow);

   // 3. Lower BreakOut Box (Low - Offset to Low)
   DrawObject(name_bo_low, dtTimeBegin, dtTimeObjEnd, dPriceLow - offset, dPriceLow, BoxBreakOutColor, BoxBreakOut_Offset, 3, dPriceHigh, dPriceLow);

   // 4. Period Box (Session border outline)
   DrawObject(name_period, dtTimeBegin, dtTimeEnd, dPriceHigh + offset, dPriceLow - offset, BoxPeriodColor, BoxBreakOut_Offset, 4, dPriceHigh, dPriceLow);
  }

//+------------------------------------------------------------------+
//| Update all breakout boxes                                        |
//+------------------------------------------------------------------+
void UpdateBoxes()
  {
   datetime d1_times[];
   ArraySetAsSeries(d1_times, true);
   int available_days = CopyTime(_Symbol, PERIOD_D1, 0, NumberOfDays, d1_times);

   double offset = BoxBreakOut_Offset * _Point;

   if(available_days > 0)
     {
      for(int i = 0; i < available_days; i++)
        {
         ProcessDay(d1_times[i], offset);
        }
     }
   else
     {
      datetime dtTradeDate = TimeCurrent();
      for(int i = 0; i < NumberOfDays; i++)
        {
         ProcessDay(dtTradeDate, offset);
         dtTradeDate = DecrementTradeDate(dtTradeDate);
         while(GetDayOfWeek(dtTradeDate) == 0 || GetDayOfWeek(dtTradeDate) == 6)
            dtTradeDate = DecrementTradeDate(dtTradeDate);
        }
     }

   ChartRedraw(0);
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

   datetime bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar_time == 0)
      return(prev_calculated);

   if(prev_calculated == 0)
      g_last_bar_time = 0;

   if(InpUpdateOnNewBar && g_last_bar_time == bar_time)
      return(rates_total);

   g_last_bar_time = bar_time;

   UpdateBoxes();
   return(rates_total);
  }
//+------------------------------------------------------------------+

