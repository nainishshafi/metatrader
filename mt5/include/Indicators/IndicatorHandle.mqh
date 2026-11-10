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

   void Release()
   {
      if(m_handle != INVALID_HANDLE)
      {
         IndicatorRelease(m_handle);
         m_handle = INVALID_HANDLE;
      }
   }

   bool Attach(const int handle, const string symbol, const ENUM_TIMEFRAMES tf)
   {
      Release();
      m_handle    = handle;
      m_symbol    = symbol;
      m_timeframe = tf;
      return (m_handle != INVALID_HANDLE);
   }

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
};

