//+------------------------------------------------------------------+
//|                                                    HMASignal.mqh |
//|                     HMA NRP & M15 Breakout Signal Implementation |
//|                     Implements Generic ISignal Interface         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "..\..\..\include\Strategy\ISignal.mqh"
#include "..\..\..\include\Indicators\IndicatorHandle.mqh"

class CHMASignal : public ISignal
{
private:
   CIndicatorHandle  m_indicator;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   string            m_indicatorName;
   int               m_period;
   bool              m_loggedWarning;

   // Cached last calculation
   double            m_lastTrend;
   double            m_lastPrice;

public:
   CHMASignal() : m_symbol(""), m_timeframe(PERIOD_M15), m_indicatorName("HMA nrp"), m_period(21),
                  m_loggedWarning(false), m_lastTrend(0.0), m_lastPrice(0.0) {}

   virtual bool Init(const string symbol, const ENUM_TIMEFRAMES tf) override
   {
      return Init(symbol, tf, "HMA nrp", 21);
   }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const string indicatorName, const int period)
   {
      m_symbol         = symbol;
      m_timeframe      = tf;
      m_indicatorName  = indicatorName;
      m_period         = period;
      m_loggedWarning  = false;
      m_lastTrend      = 0.0;
      m_lastPrice      = 0.0;

      return LoadHandle();
   }

   virtual void Deinit() override
   {
      m_indicator.Release();
   }

   virtual bool IsReady() const override
   {
      return m_indicator.IsReady();
   }

   int GetBarsCalculated() const
   {
      return m_indicator.GetBarsCalculated();
   }

   double GetLastTrend() const { return m_lastTrend; }
   double GetLastPrice() const { return m_lastPrice; }

   bool LoadHandle()
   {
      int handle = INVALID_HANDLE;

      // 1. Try direct indicator name with TimeFrame and Period
      handle = iCustom(m_symbol, m_timeframe, m_indicatorName, m_timeframe, m_period);
      if(handle != INVALID_HANDLE)
         return m_indicator.Attach(handle, m_symbol, m_timeframe);

      // 2. Try direct indicator name with default parameters
      handle = iCustom(m_symbol, m_timeframe, m_indicatorName);
      if(handle != INVALID_HANDLE)
         return m_indicator.Attach(handle, m_symbol, m_timeframe);

      // 3. Try with Indicators\\ path prefix
      handle = iCustom(m_symbol, m_timeframe, "Indicators\\" + m_indicatorName, m_timeframe, m_period);
      if(handle != INVALID_HANDLE)
         return m_indicator.Attach(handle, m_symbol, m_timeframe);

      // 4. Try with Indicators\\ path prefix with default parameters
      handle = iCustom(m_symbol, m_timeframe, "Indicators\\" + m_indicatorName);
      if(handle != INVALID_HANDLE)
         return m_indicator.Attach(handle, m_symbol, m_timeframe);

      if(!m_loggedWarning)
      {
         PrintFormat("Note: Indicator '%s' not loaded yet. Waiting for indicator file.", m_indicatorName);
         m_loggedWarning = true;
      }
      return false;
   }

   //+---------------------------------------------------------------+
   //| Fetch latest HMA trend direction and price value (O(1) slice) |
   //+---------------------------------------------------------------+
   bool FetchHMAData(double &trend, double &price)
   {
      if(!m_indicator.IsReady())
         return false;

      double price_arr[];
      int copied_price = m_indicator.Copy(0, 0, 2, price_arr);
      if(copied_price < 2 || price_arr[0] == EMPTY_VALUE || price_arr[0] <= 0.0)
         return false;

      price       = price_arr[0];
      m_lastPrice = price;

      // 1. Try reading Buffer 4 (TrendBuffer: +1.0 = Uptrend, -1.0 = Downtrend)
      double t = m_indicator.GetValue(4, 0);
      if(t != EMPTY_VALUE && t != 0.0)
      {
         trend       = t;
         m_lastTrend = trend;
         return true;
      }

      // 2. Try reading Buffer 1 (ColorBuffer: 0.0 = Uptrend, 1.0 = Downtrend)
      double c = m_indicator.GetValue(1, 0);
      if(c != EMPTY_VALUE)
      {
         trend       = (c == 0.0) ? 1.0 : -1.0;
         m_lastTrend = trend;
         return true;
      }

      // 3. Fallback: Mathematical Slope of HMA Line (price[0] vs price[1])
      trend       = (price_arr[0] > price_arr[1]) ? 1.0 : ((price_arr[0] < price_arr[1]) ? -1.0 : 0.0);
      m_lastTrend = trend;
      return true;
   }

   //+---------------------------------------------------------------+
   //| Evaluate Trading Signal (Implements ISignal)                  |
   //+---------------------------------------------------------------+
   virtual ENUM_STRATEGY_SIGNAL EvaluateSignal() override
   {
      double trend = 0.0, price = 0.0;
      if(!FetchHMAData(trend, price))
         return STRATEGY_SIGNAL_NONE;

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0)
         return STRATEGY_SIGNAL_NONE;

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0.0) point = 0.01;

      double o15 = iOpen(m_symbol, PERIOD_M15, 0);
      double o1  = iOpen(m_symbol, PERIOD_M1, 0);
      double h15 = iHigh(m_symbol, PERIOD_M15, 0);
      double l15 = iLow(m_symbol, PERIOD_M15, 0);

      // Buy Condition
      if(trend == 1.0 && bid > price &&
         bid > o15 && bid > o1 &&
         CheckPrev15MBuy(bid) &&
         GetBidPercentFromOpen(bid, o15) > 0.02 &&
         bid >= (h15 - point))
      {
         return STRATEGY_SIGNAL_BUY;
      }

      // Sell Condition
      if(trend == -1.0 && ask < price &&
         ask < o15 && ask < o1 &&
         CheckPrev15MSell(ask) &&
         GetAskPercentFromOpen(ask, o15) > 0.02 &&
         bid <= (l15 + point))
      {
         return STRATEGY_SIGNAL_SELL;
      }

      return STRATEGY_SIGNAL_NONE;
   }

   //+---------------------------------------------------------------+
   //| Check if position should exit on trend reversal (ISignal)     |
   //+---------------------------------------------------------------+
   virtual bool ShouldReverseExit(const ENUM_POSITION_TYPE currentPos) override
   {
      double trend = 0.0, price = 0.0;
      if(!FetchHMAData(trend, price))
         return false;

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(currentPos == POSITION_TYPE_BUY)
         return (trend == -1.0 && ask < price);

      if(currentPos == POSITION_TYPE_SELL)
         return (trend == 1.0 && bid > price);

      return false;
   }

private:
   bool CheckPrev15MBuy(const double bid) const
   {
      double c1 = iClose(m_symbol, PERIOD_M15, 1);
      double o1 = iOpen(m_symbol, PERIOD_M15, 1);
      double h1 = iHigh(m_symbol, PERIOD_M15, 1);
      return (c1 > o1 || bid > h1);
   }

   bool CheckPrev15MSell(const double ask) const
   {
      double c1 = iClose(m_symbol, PERIOD_M15, 1);
      double o1 = iOpen(m_symbol, PERIOD_M15, 1);
      double l1 = iLow(m_symbol, PERIOD_M15, 1);
      return (c1 < o1 || ask < l1);
   }

   double GetBidPercentFromOpen(const double bid, const double o15) const
   {
      if(o15 <= 0.0) return 0.0;
      return (((bid - o15) / o15) * 100.0);
   }

   double GetAskPercentFromOpen(const double ask, const double o15) const
   {
      if(o15 <= 0.0) return 0.0;
      return (((o15 - ask) / o15) * 100.0);
   }
};

