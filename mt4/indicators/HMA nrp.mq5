//+------------------------------------------------------------------+
//|                                                    HMA nrp.mq5   |
//|                                  Copyright 2026, www.forex-station.com |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright   "www.forex-station.com"
#property link        "www.forex-station.com"
#property version     "2.10"
#property description "Hull Moving Average (HMA) Non-Repainting with MTF, Alerts & Multi-Price/MA Types"

#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   3

//--- Plot 1: HMA Line
#property indicator_label1  "HMA"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLimeGreen, clrOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- Plot 2: Up Arrow
#property indicator_label2  "HMA Up Arrow"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLimeGreen
#property indicator_width2  2

//--- Plot 3: Down Arrow
#property indicator_label3  "HMA Down Arrow"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrOrange
#property indicator_width3  2

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum enPrices
{
   pr_close,      // Close
   pr_open,       // Open
   pr_high,       // High
   pr_low,        // Low
   pr_median,     // Median (high+low)/2
   pr_typical,    // Typical (high+low+close)/3
   pr_weighted,   // Weighted (high+low+close+close)/4
   pr_average,    // Average (high+low+open+close)/4
   pr_medianb,    // Average median body (open+close)/2
   pr_tbiased,    // Trend biased price
   pr_tbiased2,   // Trend biased (extreme) price
   pr_haclose,    // Heiken ashi close
   pr_haopen,     // Heiken ashi open
   pr_hahigh,     // Heiken ashi high
   pr_halow,      // Heiken ashi low
   pr_hamedian,   // Heiken ashi median
   pr_hatypical,  // Heiken ashi typical
   pr_haweighted, // Heiken ashi weighted
   pr_haaverage,  // Heiken ashi average
   pr_hamedianb,  // Heiken ashi median body
   pr_hatbiased,  // Heiken ashi trend biased price
   pr_hatbiased2  // Heiken ashi trend biased (extreme) price
};

enum enMaTypes
{
   ma_sma,    // Simple moving average
   ma_ema,    // Exponential moving average
   ma_smma,   // Smoothed MA
   ma_lwma,   // Linear weighted MA
   ma_tema    // Triple exponential moving average - TEMA
};

enum enDisplay
{
   en_lin,  // Display line
   en_lid,  // Display lines with dots
   en_dot   // Display dots
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "--- HMA Settings ---"
input ENUM_TIMEFRAMES TimeFrame       = PERIOD_M15;     // Time frame to use
input int             HMAPeriod       = 21;             // Hma Period to use (21 is standard for M15)
input enPrices        HMAPrice        = pr_haweighted;  // Price to use
input enMaTypes       HMAMethod       = ma_lwma;        // Hma average type
input double          HMASpeed        = 1.8;            // Hma Speed (divisor modification)
input enDisplay       DisplayType     = en_lin;         // Display type
input int             Shift           = 0;              // Hull shift
input int             LinesWidth      = 3;              // Lines width (when lines are displayed)

input group "--- Alert Settings ---"
input bool            alertsOn        = true;           // Turn alerts on?
input bool            alertsOnCurrent = false;          // Alerts on still open bar?
input bool            alertsMessage   = true;           // Alerts should show popup message?
input bool            alertsSound     = false;          // Alerts should play a sound?
input bool            alertsEmail     = false;          // Alerts should send email?
input bool            alertsPushNotif = false;          // Alerts should send notification?

input group "--- Arrow Settings ---"
input bool            ArrowOnFirst    = true;           // Arrow on first bars
input int             UpArrowSize     = 2;              // Up Arrow size
input int             DnArrowSize     = 2;              // Down Arrow size
input int             UpArrowCode     = 159;            // Up Arrow code (Wingdings)
input int             DnArrowCode     = 159;            // Down Arrow code (Wingdings)
input double          UpArrowGap      = 0.5;            // Up Arrow gap (ATR multiplier)
input double          DnArrowGap      = 0.5;            // Dn Arrow gap (ATR multiplier)
input color           UpArrowColor    = clrLimeGreen;   // Up Arrow Color
input color           DnArrowColor    = clrOrange;      // Down Arrow Color

input group "--- MTF Settings ---"
input bool            Interpolate     = true;           // Interpolate in multi time frame mode?

//+------------------------------------------------------------------+
//| Indicator Buffers                                                |
//+------------------------------------------------------------------+
double HmaBuffer[];
double HmaColorBuffer[];
double ArrowUpBuffer[];
double ArrowDnBuffer[];
double TrendBuffer[];
double TemBuffer[];

//+------------------------------------------------------------------+
//| Custom helper: Timeframe to String                               |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_CURRENT: return "Current";
      case PERIOD_M1:      return "M1";
      case PERIOD_M2:      return "M2";
      case PERIOD_M3:      return "M3";
      case PERIOD_M4:      return "M4";
      case PERIOD_M5:      return "M5";
      case PERIOD_M6:      return "M6";
      case PERIOD_M10:     return "M10";
      case PERIOD_M12:     return "M12";
      case PERIOD_M15:     return "M15";
      case PERIOD_M20:     return "M20";
      case PERIOD_M30:     return "M30";
      case PERIOD_H1:      return "H1";
      case PERIOD_H2:      return "H2";
      case PERIOD_H3:      return "H3";
      case PERIOD_H4:      return "H4";
      case PERIOD_H6:      return "H6";
      case PERIOD_H8:      return "H8";
      case PERIOD_H12:     return "H12";
      case PERIOD_D1:      return "D1";
      case PERIOD_W1:      return "W1";
      case PERIOD_MN1:     return "MN";
      default:             return EnumToString(tf);
   }
}

//+------------------------------------------------------------------+
//| Alerts Handler                                                   |
//+------------------------------------------------------------------+
void DoAlert(const string doWhat, const datetime barTime)
{
   static string   previousAlert = "";
   static datetime previousTime  = 0;

   if(previousAlert != doWhat || previousTime != barTime)
   {
      previousAlert = doWhat;
      previousTime  = barTime;

      string message = StringFormat("%s %s at %s Hull trend changed to %s",
                                    TimeframeToString((ENUM_TIMEFRAMES)_Period),
                                    _Symbol,
                                    TimeToString(TimeLocal(), TIME_SECONDS),
                                    doWhat);

      if(alertsMessage)   Alert(message);
      if(alertsPushNotif) SendNotification(message);
      if(alertsEmail)     SendMail(_Symbol + " Hull", message);
      if(alertsSound)     PlaySound("alert2.wav");
   }
}

//+------------------------------------------------------------------+
//| Calculate Price Series (including Heiken Ashi options)          |
//+------------------------------------------------------------------+
void CalculatePrices(const double &open[],
                     const double &high[],
                     const double &low[],
                     const double &close[],
                     const int total,
                     const enPrices tprice,
                     double &price[])
{
   if(total <= 0)
      return;
   if(ArraySize(price) != total)
      ArrayResize(price, total);

   if(tprice >= pr_haclose)
   {
      double haOpen = 0.0, haClose = 0.0, haHigh = 0.0, haLow = 0.0;
      double prevHaOpen = 0.0, prevHaClose = 0.0;

      for(int r = 0; r < total; r++)
      {
         if(r == 0)
            haOpen = (open[0] + close[0]) / 2.0;
         else
            haOpen = (prevHaOpen + prevHaClose) / 2.0;

         haClose = (open[r] + high[r] + low[r] + close[r]) / 4.0;
         haHigh  = MathMax(high[r], MathMax(haOpen, haClose));
         haLow   = MathMin(low[r],  MathMin(haOpen, haClose));

         prevHaOpen  = haOpen;
         prevHaClose = haClose;

         switch(tprice)
         {
            case pr_haclose:     price[r] = haClose; break;
            case pr_haopen:      price[r] = haOpen; break;
            case pr_hahigh:      price[r] = haHigh; break;
            case pr_halow:       price[r] = haLow; break;
            case pr_hamedian:    price[r] = (haHigh + haLow) / 2.0; break;
            case pr_hamedianb:   price[r] = (haOpen + haClose) / 2.0; break;
            case pr_hatypical:   price[r] = (haHigh + haLow + haClose) / 3.0; break;
            case pr_haweighted:  price[r] = (haHigh + haLow + haClose + haClose) / 4.0; break;
            case pr_haaverage:   price[r] = (haHigh + haLow + haClose + haOpen) / 4.0; break;
            case pr_hatbiased:
               price[r] = (haClose > haOpen) ? ((haHigh + haClose) / 2.0) : ((haLow + haClose) / 2.0);
               break;
            case pr_hatbiased2:
               price[r] = (haClose > haOpen) ? haHigh : (haClose < haOpen) ? haLow : haClose;
               break;
            default:
               price[r] = haClose;
               break;
         }
      }
   }
   else
   {
      for(int r = 0; r < total; r++)
      {
         switch(tprice)
         {
            case pr_close:    price[r] = close[r]; break;
            case pr_open:     price[r] = open[r]; break;
            case pr_high:     price[r] = high[r]; break;
            case pr_low:      price[r] = low[r]; break;
            case pr_median:   price[r] = (high[r] + low[r]) / 2.0; break;
            case pr_medianb:  price[r] = (open[r] + close[r]) / 2.0; break;
            case pr_typical:  price[r] = (high[r] + low[r] + close[r]) / 3.0; break;
            case pr_weighted: price[r] = (high[r] + low[r] + close[r] + close[r]) / 4.0; break;
            case pr_average:  price[r] = (high[r] + low[r] + close[r] + open[r]) / 4.0; break;
            case pr_tbiased:
               price[r] = (close[r] > open[r]) ? ((high[r] + close[r]) / 2.0) : ((low[r] + close[r]) / 2.0);
               break;
            case pr_tbiased2:
               price[r] = (close[r] > open[r]) ? high[r] : (close[r] < open[r]) ? low[r] : close[r];
               break;
            default:
               price[r] = close[r];
               break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate Moving Average Engine (SMA, EMA, SMMA, LWMA, TEMA)     |
//+------------------------------------------------------------------+
void CalculateMa(const double &src[], const int total, const int period, const enMaTypes mode, double &dst[])
{
   if(total <= 0)
      return;

   double temp[];
   if(ArrayResize(temp, total) < 0)
      return;

   int p = (period < 1) ? 1 : period;

   switch(mode)
   {
      case ma_sma:
      {
         for(int r = 0; r < total; r++)
         {
            double sum = 0.0;
            int count = 0;
            for(int k = 0; k < p && (r - k) >= 0; k++)
            {
               sum += src[r - k];
               count++;
            }
            temp[r] = (count > 0) ? (sum / (double)count) : src[r];
         }
         break;
      }

      case ma_ema:
      {
         double alpha = 2.0 / (1.0 + (double)p);
         for(int r = 0; r < total; r++)
         {
            if(r == 0 || p <= 1)
               temp[r] = src[r];
            else
               temp[r] = temp[r - 1] + alpha * (src[r] - temp[r - 1]);
         }
         break;
      }

      case ma_smma:
      {
         for(int r = 0; r < total; r++)
         {
            if(r <= 1 || p <= 1)
               temp[r] = src[r];
            else
               temp[r] = temp[r - 1] + (src[r] - temp[r - 1]) / (double)p;
         }
         break;
      }

      case ma_lwma:
      {
         if(p <= 1)
         {
            for(int r = 0; r < total; r++)
               temp[r] = src[r];
            break;
         }
         for(int r = 0; r < total; r++)
         {
            double sumw = 0.0;
            double sum  = 0.0;
            for(int k = 0; k < p && (r - k) >= 0; k++)
            {
               double weight = (double)(p - k);
               sumw += weight;
               sum  += weight * src[r - k];
            }
            temp[r] = (sumw > 0.0) ? (sum / sumw) : src[r];
         }
         break;
      }

      case ma_tema:
      {
         if(p <= 1)
         {
            for(int r = 0; r < total; r++)
               temp[r] = src[r];
            break;
         }
         double alpha = 2.0 / (1.0 + (double)p);
         double tema1 = 0.0, tema2 = 0.0, tema3 = 0.0;
         for(int r = 0; r < total; r++)
         {
            if(r == 0)
            {
               tema1 = src[r];
               tema2 = src[r];
               tema3 = src[r];
            }
            else
            {
               tema1 = tema1 + alpha * (src[r] - tema1);
               tema2 = tema2 + alpha * (tema1 - tema2);
               tema3 = tema3 + alpha * (tema2 - tema3);
            }
            temp[r] = tema3 + 3.0 * (tema1 - tema2);
         }
         break;
      }

      default:
      {
         for(int r = 0; r < total; r++)
            temp[r] = src[r];
         break;
      }
   }

   for(int r = 0; r < total; r++)
      dst[r] = temp[r];
}

//+------------------------------------------------------------------+
//| Calculate HMA Series Pipeline                                    |
//+------------------------------------------------------------------+
void CalculateHmaSeries(const double &open[],
                        const double &high[],
                        const double &low[],
                        const double &close[],
                        const int total,
                        int hmaPeriod,
                        double hmaSpeed,
                        enPrices priceType,
                        enMaTypes maType,
                        double &outHma[],
                        double &outTrend[],
                        double &outTem[])
{
   if(total <= 0)
      return;

   int period     = MathMax(2, hmaPeriod);
   double speed   = (hmaSpeed > 0.0) ? hmaSpeed : 1.8;
   int halfPeriod = (int)MathFloor((double)period / speed);
   if(halfPeriod < 1) halfPeriod = 1;
   int hullPeriod = (int)MathFloor(MathSqrt((double)period));
   if(hullPeriod < 1) hullPeriod = 1;

   double price[];
   CalculatePrices(open, high, low, close, total, priceType, price);

   double maHalf[];
   double maFull[];
   CalculateMa(price, total, halfPeriod, maType, maHalf);
   CalculateMa(price, total, period,     maType, maFull);

   for(int r = 0; r < total; r++)
      outTem[r] = 2.0 * maHalf[r] - maFull[r];

   CalculateMa(outTem, total, hullPeriod, maType, outHma);

   outTrend[0] = 0.0;
   for(int r = 1; r < total; r++)
   {
      if(outHma[r] > outHma[r - 1])
         outTrend[r] = 1.0;
      else if(outHma[r] < outHma[r - 1])
         outTrend[r] = -1.0;
      else
         outTrend[r] = outTrend[r - 1];
   }
}

//+------------------------------------------------------------------+
//| Calculate Smoothed ATR for Arrow Offsets                         |
//+------------------------------------------------------------------+
void CalculateAtr(const double &high[],
                  const double &low[],
                  const double &close[],
                  const int total,
                  const int period,
                  double &atr[])
{
   if(total <= 0)
      return;
   if(ArraySize(atr) != total)
      ArrayResize(atr, total);

   int p = (period < 1) ? 1 : period;
   double tr[];
   ArrayResize(tr, total);

   for(int r = 0; r < total; r++)
   {
      if(r == 0)
         tr[r] = high[r] - low[r];
      else
      {
         double d1 = high[r] - low[r];
         double d2 = MathAbs(high[r] - close[r - 1]);
         double d3 = MathAbs(low[r]  - close[r - 1]);
         tr[r] = MathMax(d1, MathMax(d2, d3));
      }
   }

   CalculateMa(tr, total, p, ma_smma, atr);
}

//+------------------------------------------------------------------+
//| Find Corresponding Higher Timeframe Bar Index                    |
//+------------------------------------------------------------------+
int FindHtfBar(const datetime searchTime, const MqlRates &htfRates[], const int htfCount)
{
   int left  = 0;
   int right = htfCount - 1;
   int found = -1;

   while(left <= right)
   {
      int mid = left + (right - left) / 2;
      if(htfRates[mid].time <= searchTime)
      {
         found = mid;
         left  = mid + 1;
      }
      else
      {
         right = mid - 1;
      }
   }
   return found;
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Map Indicator Buffers
   SetIndexBuffer(0, HmaBuffer,      INDICATOR_DATA);
   SetIndexBuffer(1, HmaColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, ArrowUpBuffer,  INDICATOR_DATA);
   SetIndexBuffer(3, ArrowDnBuffer,  INDICATOR_DATA);
   SetIndexBuffer(4, TrendBuffer,    INDICATOR_DATA);
   SetIndexBuffer(5, TemBuffer,      INDICATOR_CALCULATIONS);

   //--- Empty values
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- Shift & Width
   PlotIndexSetInteger(0, PLOT_SHIFT, Shift);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, LinesWidth);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, UpArrowColor);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, DnArrowColor);

   //--- Arrow Styles
   PlotIndexSetInteger(1, PLOT_ARROW, UpArrowCode);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, UpArrowSize);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, UpArrowColor);

   PlotIndexSetInteger(2, PLOT_ARROW, DnArrowCode);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, DnArrowSize);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, DnArrowColor);

   //--- Display Type Configuration
   if(DisplayType == en_lin)
   {
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_LINE);
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_NONE);
   }
   else if(DisplayType == en_lid)
   {
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_LINE);
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
   }
   else // en_dot
   {
      PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);
      PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_ARROW);
      PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_ARROW);
   }

   //--- Short name
   string shortName = StringFormat("HMA nrp(%s, %d, speed:%.1f)",
                                   TimeframeToString((ENUM_TIMEFRAMES)TimeFrame),
                                   HMAPeriod,
                                   HMASpeed);
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
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
      return 0;

   ENUM_TIMEFRAMES currentTf = (ENUM_TIMEFRAMES)_Period;
   ENUM_TIMEFRAMES targetTf  = (TimeFrame == PERIOD_CURRENT || TimeFrame <= currentTf) ? currentTf : TimeFrame;

   //+------------------------------------------------------------------+
   //| Single Timeframe Mode                                            |
   //+------------------------------------------------------------------+
   if(targetTf == currentTf)
   {
      CalculateHmaSeries(open, high, low, close, rates_total,
                         HMAPeriod, HMASpeed, HMAPrice, HMAMethod,
                         HmaBuffer, TrendBuffer, TemBuffer);

      double atr[];
      CalculateAtr(high, low, close, rates_total, 15, atr);

      for(int i = 0; i < rates_total; i++)
      {
         HmaColorBuffer[i] = (TrendBuffer[i] == 1.0) ? 0.0 : 1.0;
         ArrowUpBuffer[i]  = EMPTY_VALUE;
         ArrowDnBuffer[i]  = EMPTY_VALUE;

         if(i > 0 && TrendBuffer[i] != TrendBuffer[i - 1])
         {
            if(TrendBuffer[i] == 1.0)
               ArrowUpBuffer[i] = MathMin(HmaBuffer[i], low[i])  - atr[i] * UpArrowGap;
            else if(TrendBuffer[i] == -1.0)
               ArrowDnBuffer[i] = MathMax(HmaBuffer[i], high[i]) + atr[i] * DnArrowGap;
         }
      }

      if(alertsOn && rates_total >= 3)
      {
         int whichBar = alertsOnCurrent ? (rates_total - 1) : (rates_total - 2);
         int prevBar  = whichBar - 1;
         if(whichBar >= 1 && TrendBuffer[whichBar] != TrendBuffer[prevBar])
         {
            if(TrendBuffer[whichBar] == 1.0)
               DoAlert("sloping up", time[whichBar]);
            else if(TrendBuffer[whichBar] == -1.0)
               DoAlert("sloping down", time[whichBar]);
         }
      }

      return rates_total;
   }

   //+------------------------------------------------------------------+
   //| Multi-Timeframe (MTF) Mode                                       |
   //+------------------------------------------------------------------+
   MqlRates htfRates[];
   ArraySetAsSeries(htfRates, false);
   int copied = CopyRates(_Symbol, targetTf, 0, rates_total, htfRates);
   if(copied < 2)
      return prev_calculated;

   double htfOpen[], htfHigh[], htfLow[], htfClose[];
   ArrayResize(htfOpen,  copied);
   ArrayResize(htfHigh,  copied);
   ArrayResize(htfLow,   copied);
   ArrayResize(htfClose, copied);

   for(int k = 0; k < copied; k++)
   {
      htfOpen[k]  = htfRates[k].open;
      htfHigh[k]  = htfRates[k].high;
      htfLow[k]   = htfRates[k].low;
      htfClose[k] = htfRates[k].close;
   }

   double htfHma[], htfTrend[], htfTem[];
   CalculateHmaSeries(htfOpen, htfHigh, htfLow, htfClose, copied,
                      HMAPeriod, HMASpeed, HMAPrice, HMAMethod,
                      htfHma, htfTrend, htfTem);

   double atr[];
   CalculateAtr(high, low, close, rates_total, 15, atr);

   long targetTfSec = PeriodSeconds(targetTf);
   if(targetTfSec <= 0) targetTfSec = 3600;

   for(int i = 0; i < rates_total; i++)
   {
      ArrowUpBuffer[i] = EMPTY_VALUE;
      ArrowDnBuffer[i] = EMPTY_VALUE;

      int k = FindHtfBar(time[i], htfRates, copied);
      if(k < 0)
      {
         HmaBuffer[i]      = EMPTY_VALUE;
         HmaColorBuffer[i] = 0.0;
         TrendBuffer[i]    = 0.0;
         TemBuffer[i]      = EMPTY_VALUE;
         continue;
      }

      TrendBuffer[i]    = htfTrend[k];
      HmaColorBuffer[i] = (htfTrend[k] == 1.0) ? 0.0 : 1.0;
      TemBuffer[i]      = htfTem[k];

      if(!Interpolate || k == 0)
      {
         HmaBuffer[i] = htfHma[k];
      }
      else
      {
         datetime htfBarTime  = htfRates[k].time;
         datetime nextHtfTime = (k < copied - 1) ? htfRates[k + 1].time : (htfBarTime + (datetime)targetTfSec);
         double duration = (double)(nextHtfTime - htfBarTime);
         if(duration <= 0.0) duration = (double)targetTfSec;

         double elapsed = (double)(time[i] - htfBarTime);
         double frac = elapsed / duration;
         if(frac < 0.0) frac = 0.0;
         if(frac > 1.0) frac = 1.0;

         HmaBuffer[i] = htfHma[k - 1] + (htfHma[k] - htfHma[k - 1]) * frac;
      }

      // Check for trend change arrows
      bool trendChanged = (k > 0 && htfTrend[k] != htfTrend[k - 1]);
      if(trendChanged)
      {
         bool shouldPlace = false;
         if(ArrowOnFirst)
         {
            int prevK = (i > 0) ? FindHtfBar(time[i - 1], htfRates, copied) : -1;
            shouldPlace = (prevK != k);
         }
         else
         {
            int nextK = (i < rates_total - 1) ? FindHtfBar(time[i + 1], htfRates, copied) : -1;
            shouldPlace = (nextK != k);
         }

         if(shouldPlace)
         {
            if(htfTrend[k] == 1.0)
               ArrowUpBuffer[i] = MathMin(HmaBuffer[i], low[i])  - atr[i] * UpArrowGap;
            else if(htfTrend[k] == -1.0)
               ArrowDnBuffer[i] = MathMax(HmaBuffer[i], high[i]) + atr[i] * DnArrowGap;
         }
      }
   }

   return rates_total;
}
//+------------------------------------------------------------------+
