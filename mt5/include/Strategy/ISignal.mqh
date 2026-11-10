//+------------------------------------------------------------------+
//|                                                      ISignal.mqh |
//|                     Generic Trading Signal Strategy Interface    |
//|               Reusable across any MQL5 Expert Advisor            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

enum ENUM_STRATEGY_SIGNAL
{
   STRATEGY_SIGNAL_NONE = 0,
   STRATEGY_SIGNAL_BUY  = 1,
   STRATEGY_SIGNAL_SELL = -1
};

class ISignal
{
public:
   virtual ~ISignal() {}
   virtual bool                  Init(const string symbol, const ENUM_TIMEFRAMES tf) = 0;
   virtual void                  Deinit() = 0;
   virtual bool                  IsReady() const = 0;
   virtual ENUM_STRATEGY_SIGNAL  EvaluateSignal() = 0;
   virtual bool                  ShouldReverseExit(const ENUM_POSITION_TYPE currentPos) = 0;
};

