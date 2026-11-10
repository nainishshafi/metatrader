//+------------------------------------------------------------------+
//|                                              IndicatorHandle.mqh |
//|                     Generic Safe RAII Indicator Handle Wrapper   |
//|               Reusable across any MQL5 Expert Advisor or Engine  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

class CIndicatorHandle
{
private:
   int               m_handle;
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;

public:
   CIndicatorHandle() : m_handle(INVALID_HANDLE), m_symbol(""), m_timeframe(PERIOD_CURRENT) {}

   ~CIndicatorHandle()
   {
      Release();
   }

   //+---------------------------------------------------------------+
   //| Release indicator handle from MetaTrader memory               |
   //+---------------------------------------------------------------+
   void Release()
   {
      if(m_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_handle);
         m_handle = INVALID_HANDLE;
      }
   }

   //+---------------------------------------------------------------+
   //| Attach existing handle and bind symbol / timeframe            |
   //+---------------------------------------------------------------+
   bool Attach(const int handle, const string symbol, const ENUM_TIMEFRAMES tf)
   {
      Release();
      m_handle    = handle;
      m_symbol    = symbol;
      m_timeframe = tf;
      return (m_handle != INVALID_HANDLE);
   }

   //+---------------------------------------------------------------+
   //| Create custom indicator directly via iCustom                  |
   //+---------------------------------------------------------------+
   bool CreateCustom(const string symbol, const ENUM_TIMEFRAMES tf, const string name)
   {
      int h = iCustom(symbol, tf, name);
      return Attach(h, symbol, tf);
   }

   //--- State & Property Accessors
   int             Handle()    const { return m_handle; }
   bool            IsValid()   const { return (m_handle != INVALID_HANDLE); }
   string          Symbol()    const { return m_symbol; }
   ENUM_TIMEFRAMES Timeframe() const { return m_timeframe; }

   //+---------------------------------------------------------------+
   //| Guard against the synchronous ~46-second MT5 thread freeze   |
   //+---------------------------------------------------------------+
   bool IsReady() const
   {
      return (m_handle != INVALID_HANDLE && BarsCalculated(m_handle) >= 2);
   }

   int GetBarsCalculated() const
   {
      return (m_handle != INVALID_HANDLE) ? BarsCalculated(m_handle) : -1;
   }

   //+---------------------------------------------------------------+
   //| Safe buffer slice copy with automatic series indexing (Bar 0) |
   //+---------------------------------------------------------------+
   int Copy(const int bufferNum, const int startPos, const int count, double &buffer[]) const
   {
      if(!IsReady())
         return -1;
      ArraySetAsSeries(buffer, true);
      return CopyBuffer(m_handle, bufferNum, startPos, count, buffer);
   }

   //+---------------------------------------------------------------+
   //| Safe single-value fetch at bar index (default: bar 0)         |
   //+---------------------------------------------------------------+
   double GetValue(const int bufferNum, const int barIndex = 0, const double defaultVal = EMPTY_VALUE) const
   {
      if(!IsReady())
         return defaultVal;
      double temp[1];
      if(CopyBuffer(m_handle, bufferNum, barIndex, 1, temp) == 1)
         return temp[0];
      return defaultVal;
   }

   //+---------------------------------------------------------------+
   //| Mathematical slope direction (+1.0 Up, -1.0 Down, 0.0 Flat)   |
   //+---------------------------------------------------------------+
   double GetSlope(const int bufferNum = 0) const
   {
      double vals[];
      if(Copy(bufferNum, 0, 2, vals) < 2)
         return 0.0;
      if(vals[0] > vals[1]) return 1.0;
      if(vals[0] < vals[1]) return -1.0;
      return 0.0;
   }
};
