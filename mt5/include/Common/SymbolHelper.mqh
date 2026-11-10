//+------------------------------------------------------------------+
//|                                                 SymbolHelper.mqh |
//|                     Generic Broker & Symbol Helper Library       |
//|               Reusable across any MQL5 Expert Advisor or Script  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include <Trade\Trade.mqh>

class CSymbolHelper
{
public:
   //+---------------------------------------------------------------+
   //| Normalize and quantize volume according to broker specs       |
   //+---------------------------------------------------------------+
   static double NormalizeLot(const string symbol, double lot)
   {
      double step    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

      if(step <= 0.0)    step = 0.01;
      if(min_lot <= 0.0) min_lot = 0.01;
      if(max_lot <= 0.0) max_lot = 100.0;

      lot = MathFloor(lot / step) * step;
      if(lot < min_lot) lot = min_lot;
      if(lot > max_lot) lot = max_lot;

      int digits = (step >= 0.1) ? 1 : 2;
      return(NormalizeDouble(lot, digits));
   }

   //+---------------------------------------------------------------+
   //| Calculate volume dynamically based on current equity / balance|
   //+---------------------------------------------------------------+
   static double CalculateLotFromEquity(const string symbol,
                                        const bool useAuto,
                                        const double fixedLot,
                                        const double equityPerLot)
   {
      if(!useAuto)
         return(NormalizeLot(symbol, fixedLot));

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         equity = AccountInfoDouble(ACCOUNT_BALANCE);

      if(equity <= 0.0)
         return(SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN));

      double denom = (equityPerLot > 0.0) ? equityPerLot : 50000.0;
      double lots  = equity / denom;
      return(NormalizeLot(symbol, lots));
   }

   //+---------------------------------------------------------------+
   //| Auto-detect and configure broker filling mode for CTrade      |
   //+---------------------------------------------------------------+
   static void ConfigureFillingMode(CTrade &trade, const string symbol)
   {
      uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)
         trade.SetTypeFilling(ORDER_FILLING_FOK);
      else if((filling & SYMBOL_FILLING_IOC) != 0)
         trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         trade.SetTypeFilling(ORDER_FILLING_RETURN);
   }

   //+---------------------------------------------------------------+
   //| Calculate & normalize SL and TP with minimum stops enforcement|
   //+---------------------------------------------------------------+
   static void CalculateStops(const string symbol,
                              const ENUM_ORDER_TYPE orderType,
                              const double openPrice,
                              const double slDistance,
                              const double tpDistance,
                              double &sl,
                              double &tp)
   {
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0) point = 0.01;

      double stopsLevel = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
      double spread     = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;
      double minAllowed = MathMax(stopsLevel, spread);

      sl = 0.0;
      tp = 0.0;

      if(orderType == ORDER_TYPE_BUY)
      {
         if(slDistance > 0.0)
         {
            double rawSl = openPrice - slDistance;
            if(MathAbs(openPrice - rawSl) < minAllowed)
               rawSl = openPrice - minAllowed;
            sl = NormalizeDouble(rawSl, digits);
         }
         if(tpDistance > 0.0)
         {
            double rawTp = openPrice + tpDistance;
            if(MathAbs(rawTp - openPrice) < minAllowed)
               rawTp = openPrice + minAllowed;
            tp = NormalizeDouble(rawTp, digits);
         }
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         if(slDistance > 0.0)
         {
            double rawSl = openPrice + slDistance;
            if(MathAbs(rawSl - openPrice) < minAllowed)
               rawSl = openPrice + minAllowed;
            sl = NormalizeDouble(rawSl, digits);
         }
         if(tpDistance > 0.0)
         {
            double rawTp = openPrice - tpDistance;
            if(MathAbs(openPrice - rawTp) < minAllowed)
               rawTp = openPrice - minAllowed;
            tp = NormalizeDouble(rawTp, digits);
         }
      }
   }
};

