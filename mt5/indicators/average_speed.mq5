//+------------------------------------------------------------------+
//|                                                Average_Speed.mq5 |
//|                                Copyright 2013, Totom Sukopratomo |
//|                        https://login.mql5.com/en/users/tomsuk001 |
//|                               Modernized and cleaned up for MQL5 |
//+------------------------------------------------------------------+
// Mathematical approach:
// Speed: v = d / t
//   d = distance between price series (in points)
//   t = bar duration (in minutes)
//   v = speed unit (points / minute)
// Average Speed:
//   A = (1 / n) * Sum(v_1 + ... + v_n)
//+------------------------------------------------------------------+
#property copyright   "Copyright 2013, Totom Sukopratomo"
#property link        "https://login.mql5.com/en/users/tomsuk001"
#property version     "2.00"
#property description "Average Speed: Calculates price movement speed in points/minute"
#property indicator_separate_window
#property indicator_minimum 0.0
#property indicator_buffers 1
#property indicator_plots   1

//--- Plot Output
#property indicator_label1  "Average Speed"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_level1  2.0
#property indicator_levelcolor clrGray
#property indicator_levelstyle STYLE_DASHDOTDOT

//--- Input parameters
//--- Average Speed Settings ---
input int                InpPeriod       = 5;              // Averaging Period (bars)
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_WEIGHTED; // Applied Price

//--- Indicator buffers
double OutputBuffer[];

//--- Global Variables
int    g_period = 5;

//+------------------------------------------------------------------+
//| Calculate applied price value at specific bar index              |
//+------------------------------------------------------------------+
inline double GetAppliedPrice(ENUM_APPLIED_PRICE applied_price,
                              const double &open[],
                              const double &high[],
                              const double &low[],
                              const double &close[],
                              int index)
  {
   switch(applied_price)
     {
      case PRICE_OPEN:     return(open[index]);
      case PRICE_HIGH:     return(high[index]);
      case PRICE_LOW:      return(low[index]);
      case PRICE_MEDIAN:   return((high[index] + low[index]) * 0.5);
      case PRICE_TYPICAL:  return((high[index] + low[index] + close[index]) / 3.0);
      case PRICE_WEIGHTED: return((high[index] + low[index] + close[index] + close[index]) * 0.25);
      case PRICE_CLOSE:
      default:             return(close[index]);
     }
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_period = (InpPeriod < 1) ? 1 : InpPeriod;

   //--- Indicator buffers mapping
   SetIndexBuffer(0, OutputBuffer, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

   //--- Set indicator labels and precision
   string short_name = StringFormat("Average Speed(%d)", g_period);
   IndicatorSetString(INDICATOR_SHORTNAME, short_name);
   PlotIndexSetString(0, PLOT_LABEL, short_name);
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   return(INIT_SUCCEEDED);
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
   if(rates_total <= g_period)
      return(0);

   int limit;
   if(prev_calculated == 0)
     {
      limit = g_period;
      ArrayInitialize(OutputBuffer, 0.0);
     }
   else
     {
      limit = prev_calculated - 1;
     }

   if(limit < g_period)
      limit = g_period;

   // Timeframe duration in minutes
   double t_min = PeriodSeconds(_Period) / 60.0;
   if(t_min <= 0.0)
      t_min = 1.0;

   // Point size guard
   double pt = (_Point > 0.0) ? _Point : 0.0001;

   for(int i = limit; i < rates_total && !IsStopped(); i++)
     {
      double sum_speed = 0.0;

      for(int j = i - g_period + 1; j <= i; j++)
        {
         double p_curr = GetAppliedPrice(InpAppliedPrice, open, high, low, close, j);
         double p_prev = GetAppliedPrice(InpAppliedPrice, open, high, low, close, j - 1);

         double distance_points = MathAbs(p_curr - p_prev) / pt;
         double speed = distance_points / t_min; // points per minute
         sum_speed += speed;
        }

      OutputBuffer[i] = sum_speed / g_period;
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+

