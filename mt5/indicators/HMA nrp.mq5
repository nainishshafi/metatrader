//+------------------------------------------------------------------+
//|                                                    HMA nrp.mq5   |
//|                                  Copyright 2026, www.forex-station.com |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright   "www.forex-station.com"
#property link        "www.forex-station.com"
#property version     "2.00"
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
//| Input Parameters (No 'input group' to preserve iCustom indexing) |
//+------------------------------------------------------------------+
//--- HMA Settings ---
input ENUM_TIMEFRAMES TimeFrame       = PERIOD_M15;     // Time frame to use
input int             HMAPeriod       = 21;             // Hma Period to use (21 is standard for M15)
input enPrices        HMAPrice        = pr_haweighted;  // Price to use
input enMaTypes       HMAMethod       = ma_lwma;        // Hma average type
input double          HMASpeed        = 1.8;            // Hma Speed (divisor modification)
input enDisplay       DisplayType     = en_lin;         // Display type
input int             Shift           = 0;              // Hull shift
input int             LinesWidth      = 3;              // Lines width (when lines are displayed)

//--- Alert Settings ---
input bool            alertsOn        = false;          // Turn alerts on?
input bool            alertsOnCurrent = false;          // Alerts on still open bar?
input bool            alertsMessage   = true;           // Alerts should show popup message?
input bool            alertsSound     = false;          // Alerts should play a sound?
input bool            alertsEmail     = false;          // Alerts should send email?
input bool            alertsPushNotif = false;          // Alerts should send notification?

//--- Arrow Settings ---
input bool            ArrowOnFirst    = true;           // Arrow on first bars
input int             UpArrowSize     = 2;              // Up Arrow size
input int             DnArrowSize     = 2;              // Down Arrow size
input int             UpArrowCode     = 159;            // Up Arrow code (Wingdings)
input int             DnArrowCode     = 159;            // Down Arrow code (Wingdings)
input double          UpArrowGap      = 0.5;            // Up Arrow gap (ATR multiplier)
input double          DnArrowGap      = 0.5;            // Dn Arrow gap (ATR multiplier)
input color           UpArrowColor    = clrLimeGreen;   // Up Arrow Color
input color           DnArrowColor    = clrOrange;      // Down Arrow Color

//--- MTF Settings ---
input bool            Interpolate     = true;           // Interpolate in multi time frame mode?

//+------------------------------------------------------------------+
//| Indicator Buffers & Persistent Working Arrays                    |
//+------------------------------------------------------------------+
double HmaBuffer[];
double HmaColorBuffer[];
double ArrowUpBuffer[];
double ArrowDnBuffer[];
double TrendBuffer[];
double TemBuffer[];

// Persistent arrays for O(1) incremental Single-Timeframe calculation
double g_stfPrice[];
double g_stfHaOpen[];
double g_stfHaClose[];
double g_stfMaHalf[];
double g_stfMaFull[];
double g_stfAtr[];

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
//| Validate & Resolve Target Timeframe                              |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ResolveTargetTimeframe(ENUM_TIMEFRAMES tf, ENUM_TIMEFRAMES currentTf)
{
   if(tf == PERIOD_CURRENT)
      return currentTf;
   int tfSec  = PeriodSeconds(tf);
   int curSec = PeriodSeconds(currentTf);
   if(tfSec <= 0 || tfSec <= curSec)
      return currentTf;
   return tf;
}

//+------------------------------------------------------------------+
//| Calculate Price Series (Incremental O(1) per tick)               |
//+------------------------------------------------------------------+
void CalculatePricesIncremental(const double &open[],
                                const double &high[],
                                const double &low[],
                                const double &close[],
                                const int total,
                                const int start,
                                const enPrices tprice,
                                double &price[],
                                double &haOpenArr[],
                                double &haCloseArr[])
{
   if(total <= 0)
      return;
   if(ArraySize(price) < total)
      ArrayResize(price, total, 1024);

   int begin = (start < 0) ? 0 : start;

   if(tprice >= pr_haclose)
   {
      if(ArraySize(haOpenArr) < total)  ArrayResize(haOpenArr, total, 1024);
      if(ArraySize(haCloseArr) < total) ArrayResize(haCloseArr, total, 1024);

      for(int r = begin; r < total; r++)
      {
         double haOpen  = (r == 0) ? (open[0] + close[0]) / 2.0 : (haOpenArr[r - 1] + haCloseArr[r - 1]) / 2.0;
         double haClose = (open[r] + high[r] + low[r] + close[r]) / 4.0;
         double haHigh  = MathMax(high[r], MathMax(haOpen, haClose));
         double haLow   = MathMin(low[r],  MathMin(haOpen, haClose));

         haOpenArr[r]  = haOpen;
         haCloseArr[r] = haClose;

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
      for(int r = begin; r < total; r++)
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
//| Calculate Moving Average Engine (Incremental O(1) per tick)      |
//+------------------------------------------------------------------+
void CalculateMaIncremental(const double &src[],
                            const int total,
                            const int start,
                            const int period,
                            const enMaTypes mode,
                            double &dst[])
{
   if(total <= 0)
      return;

   int p = (period < 1) ? 1 : period;
   int begin = (start < 0) ? 0 : start;

   switch(mode)
   {
      case ma_sma:
      {
         for(int r = begin; r < total; r++)
         {
            double sum = 0.0;
            int count = 0;
            for(int k = 0; k < p && (r - k) >= 0; k++)
            {
               sum += src[r - k];
               count++;
            }
            dst[r] = (count > 0) ? (sum / (double)count) : src[r];
         }
         break;
      }

      case ma_ema:
      {
         double alpha = 2.0 / (1.0 + (double)p);
         for(int r = begin; r < total; r++)
         {
            if(r == 0 || p <= 1)
               dst[r] = src[r];
            else
               dst[r] = dst[r - 1] + alpha * (src[r] - dst[r - 1]);
         }
         break;
      }

      case ma_smma:
      {
         for(int r = begin; r < total; r++)
         {
            if(r <= 1 || p <= 1)
               dst[r] = src[r];
            else
               dst[r] = dst[r - 1] + (src[r] - dst[r - 1]) / (double)p;
         }
         break;
      }

      case ma_lwma:
      {
         if(p <= 1)
         {
            for(int r = begin; r < total; r++)
               dst[r] = src[r];
            break;
         }
         for(int r = begin; r < total; r++)
         {
            double sumw = 0.0;
            double sum  = 0.0;
            for(int k = 0; k < p && (r - k) >= 0; k++)
            {
               double weight = (double)(p - k);
               sumw += weight;
               sum  += weight * src[r - k];
            }
            dst[r] = (sumw > 0.0) ? (sum / sumw) : src[r];
         }
         break;
      }

      case ma_tema:
      {
         if(p <= 1)
         {
            for(int r = begin; r < total; r++)
               dst[r] = src[r];
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
            dst[r] = tema3 + 3.0 * (tema1 - tema2);
         }
         break;
      }

      default:
      {
         for(int r = begin; r < total; r++)
            dst[r] = src[r];
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate HMA Series Pipeline (Incremental O(1) per tick)        |
//+------------------------------------------------------------------+
void CalculateHmaSeriesIncremental(const double &open[],
                                   const double &high[],
                                   const double &low[],
                                   const double &close[],
                                   const int total,
                                   const int start,
                                   int hmaPeriod,
                                   double hmaSpeed,
                                   enPrices priceType,
                                   enMaTypes maType,
                                   double &priceBuf[],
                                   double &haOpenBuf[],
                                   double &haCloseBuf[],
                                   double &maHalfBuf[],
                                   double &maFullBuf[],
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

   int begin = (start < 0) ? 0 : start;

   CalculatePricesIncremental(open, high, low, close, total, begin, priceType, priceBuf, haOpenBuf, haCloseBuf);

   if(ArraySize(maHalfBuf) < total) ArrayResize(maHalfBuf, total, 1024);
   if(ArraySize(maFullBuf) < total) ArrayResize(maFullBuf, total, 1024);

   CalculateMaIncremental(priceBuf, total, begin, halfPeriod, maType, maHalfBuf);
   CalculateMaIncremental(priceBuf, total, begin, period,     maType, maFullBuf);

   for(int r = begin; r < total; r++)
      outTem[r] = 2.0 * maHalfBuf[r] - maFullBuf[r];

   CalculateMaIncremental(outTem, total, begin, hullPeriod, maType, outHma);

   if(begin == 0)
      outTrend[0] = 0.0;
   int trendStart = (begin < 1) ? 1 : begin;
   for(int r = trendStart; r < total; r++)
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
//| Calculate Smoothed ATR (Incremental O(1) per tick)               |
//+------------------------------------------------------------------+
void CalculateAtrIncremental(const double &high[],
                             const double &low[],
                             const double &close[],
                             const int total,
                             const int start,
                             const int period,
                             double &atr[])
{
   if(total <= 0)
      return;
   if(ArraySize(atr) < total)
      ArrayResize(atr, total, 1024);

   int p = (period < 1) ? 1 : period;
   int begin = (start < p) ? 0 : start;
   double trSum = 0.0;

   for(int r = begin; r < total; r++)
   {
      double tr;
      if(r == 0)
      {
         tr = high[0] - low[0];
      }
      else
      {
         double hl = high[r] - low[r];
         double hc = MathAbs(high[r] - close[r - 1]);
         double lc = MathAbs(low[r] - close[r - 1]);
         tr = MathMax(hl, MathMax(hc, lc));
      }

      if(r < p)
      {
         trSum += tr;
         atr[r] = trSum / (double)(r + 1);
      }
      else
      {
         atr[r] = (atr[r - 1] * (double)(p - 1) + tr) / (double)p;
      }
   }
}

//+------------------------------------------------------------------+
//| Fast Binary Search for Higher Timeframe Bar Matching             |
//+------------------------------------------------------------------+
int FindHtfBar(const datetime barTime, const MqlRates &rates[], const int total)
{
   if(total <= 0) return -1;
   if(barTime < rates[0].time) return -1;
   if(barTime >= rates[total - 1].time) return total - 1;

   int left = 0, right = total - 1, ans = -1;
   while(left <= right)
   {
      int mid = left + (right - left) / 2;
      if(rates[mid].time <= barTime)
      {
         ans = mid;
         left = mid + 1;
      }
      else
      {
         right = mid - 1;
      }
   }
   return ans;
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

   //--- Label & ShortName
   ENUM_TIMEFRAMES currentTf = (ENUM_TIMEFRAMES)_Period;
   ENUM_TIMEFRAMES targetTf  = ResolveTargetTimeframe(TimeFrame, currentTf);
   string shortName = StringFormat("%s HMA(%d)", TimeframeToString(targetTf), HMAPeriod);

   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   PlotIndexSetString(0, PLOT_LABEL, shortName);
   PlotIndexSetString(1, PLOT_LABEL, shortName + " Up");
   PlotIndexSetString(2, PLOT_LABEL, shortName + " Down");

   return(INIT_SUCCEEDED);
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
   ENUM_TIMEFRAMES targetTf  = ResolveTargetTimeframe(TimeFrame, currentTf);

   //+------------------------------------------------------------------+
   //| Single Timeframe Mode (Incremental O(1) per tick)                |
   //+------------------------------------------------------------------+
   if(targetTf == currentTf)
   {
      int start = (prev_calculated > 2 && prev_calculated <= rates_total) ? (prev_calculated - 1) : 0;

      CalculateHmaSeriesIncremental(open, high, low, close, rates_total, start,
                                    HMAPeriod, HMASpeed, HMAPrice, HMAMethod,
                                    g_stfPrice, g_stfHaOpen, g_stfHaClose, g_stfMaHalf, g_stfMaFull,
                                    HmaBuffer, TrendBuffer, TemBuffer);

      CalculateAtrIncremental(high, low, close, rates_total, start, 15, g_stfAtr);

      for(int i = start; i < rates_total; i++)
      {
         HmaColorBuffer[i] = (TrendBuffer[i] == 1.0) ? 0.0 : 1.0;
         ArrowUpBuffer[i]  = EMPTY_VALUE;
         ArrowDnBuffer[i]  = EMPTY_VALUE;

         if(i > 0 && TrendBuffer[i] != TrendBuffer[i - 1])
         {
            if(TrendBuffer[i] == 1.0)
               ArrowUpBuffer[i] = MathMin(HmaBuffer[i], low[i])  - g_stfAtr[i] * UpArrowGap;
            else if(TrendBuffer[i] == -1.0)
               ArrowDnBuffer[i] = MathMax(HmaBuffer[i], high[i]) + g_stfAtr[i] * DnArrowGap;
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
   long targetTfSec = PeriodSeconds(targetTf);
   if(targetTfSec <= 0) targetTfSec = 3600;
   long curTfSec = MathMax(1, PeriodSeconds(currentTf));
   int  barsPerHtf = (int)MathMax(1, targetTfSec / curTfSec);
   int  htfBarsToCopy = MathMin(rates_total, (rates_total / barsPerHtf) + HMAPeriod * 3 + 20);

   MqlRates htfRates[];
   ArraySetAsSeries(htfRates, false);
   int copied = CopyRates(_Symbol, targetTf, 0, htfBarsToCopy, htfRates);
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

   double htfPrice[], htfHaOpen[], htfHaClose[], htfMaHalf[], htfMaFull[];
   double htfHma[], htfTrend[], htfTem[];
   ArrayResize(htfHma,   copied);
   ArrayResize(htfTrend, copied);
   ArrayResize(htfTem,   copied);

   CalculateHmaSeriesIncremental(htfOpen, htfHigh, htfLow, htfClose, copied, 0,
                                 HMAPeriod, HMASpeed, HMAPrice, HMAMethod,
                                 htfPrice, htfHaOpen, htfHaClose, htfMaHalf, htfMaFull,
                                 htfHma, htfTrend, htfTem);

   int start = (prev_calculated > 2 && prev_calculated <= rates_total)
               ? MathMax(0, prev_calculated - barsPerHtf * 2 - 2)
               : 0;

   CalculateAtrIncremental(high, low, close, rates_total, start, 15, g_stfAtr);

   for(int i = start; i < rates_total; i++)
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
               ArrowUpBuffer[i] = MathMin(HmaBuffer[i], low[i])  - g_stfAtr[i] * UpArrowGap;
            else if(htfTrend[k] == -1.0)
               ArrowDnBuffer[i] = MathMax(HmaBuffer[i], high[i]) + g_stfAtr[i] * DnArrowGap;
         }
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
