//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|                     Generic Magic-Isolated Position Manager      |
//|               Reusable across any MQL5 Expert Advisor            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "..\Common\SymbolHelper.mqh"

class CPositionManager
{
protected:
   CTrade         m_trade;
   CPositionInfo  m_position;
   string         m_symbol;
   ulong          m_slippage;

   //+---------------------------------------------------------------+
   //| Fast Guard: Match Symbol & Magic Number Isolation             |
   //+---------------------------------------------------------------+
   bool IsMatchingPosition(const ulong targetMagic = 0) const
   {
      return (m_position.Symbol() == m_symbol &&
             (targetMagic == 0 || m_position.Magic() == targetMagic));
   }

public:
   CPositionManager() : m_symbol(""), m_slippage(30) {}

   bool Init(const string symbol, const ulong slippage = 30)
   {
      m_symbol   = symbol;
      m_slippage = slippage;

      m_trade.SetDeviationInPoints(slippage);
      CSymbolHelper::ConfigureFillingMode(m_trade, m_symbol);

      return true;
   }

   //+---------------------------------------------------------------+
   //| Execute BUY Order with SL/TP Distance                         |
   //+---------------------------------------------------------------+
   bool ExecuteBuy(const double lots, const ulong magic, const double slDist, const double tpDist, const string comment = "Buy Order")
   {
      m_trade.SetExpertMagicNumber(magic);

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(ask <= 0.0)
      {
         Print("ExecuteBuy failed: Ask price is invalid.");
         return false;
      }

      double sl = 0.0, tp = 0.0;
      CSymbolHelper::CalculateStops(m_symbol, ORDER_TYPE_BUY, ask, slDist, tpDist, sl, tp);

      bool res = m_trade.Buy(lots, m_symbol, ask, sl, tp, comment);
      if(res)
      {
         int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
         PrintFormat("BUY executed: Lots=%.2f, Price=%.*f, SL=%.*f, TP=%.*f, Magic=%I64u",
                     lots, digits, ask, digits, sl, digits, tp, magic);
      }
      else
      {
         PrintFormat("BUY order error: %s (Code: %u)", m_trade.ResultComment(), m_trade.ResultRetcode());
      }
      return res;
   }

   //+---------------------------------------------------------------+
   //| Execute SELL Order with SL/TP Distance                        |
   //+---------------------------------------------------------------+
   bool ExecuteSell(const double lots, const ulong magic, const double slDist, const double tpDist, const string comment = "Sell Order")
   {
      m_trade.SetExpertMagicNumber(magic);

      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(bid <= 0.0)
      {
         Print("ExecuteSell failed: Bid price is invalid.");
         return false;
      }

      double sl = 0.0, tp = 0.0;
      CSymbolHelper::CalculateStops(m_symbol, ORDER_TYPE_SELL, bid, slDist, tpDist, sl, tp);

      bool res = m_trade.Sell(lots, m_symbol, bid, sl, tp, comment);
      if(res)
      {
         int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
         PrintFormat("SELL executed: Lots=%.2f, Price=%.*f, SL=%.*f, TP=%.*f, Magic=%I64u",
                     lots, digits, bid, digits, sl, digits, tp, magic);
      }
      else
      {
         PrintFormat("SELL order error: %s (Code: %u)", m_trade.ResultComment(), m_trade.ResultRetcode());
      }
      return res;
   }

   //+---------------------------------------------------------------+
   //| Close all positions (Strict Magic and Symbol Isolation)       |
   //| If targetMagic == 0, closes all positions on symbol.          |
   //+---------------------------------------------------------------+
   int CloseAll(const ulong targetMagic = 0)
   {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_position.SelectByIndex(i) || !IsMatchingPosition(targetMagic))
            continue;

         if(m_trade.PositionClose(m_position.Ticket()))
            closed++;
      }
      PrintFormat("CloseAll: Closed %d position(s) on %s (Magic: %I64u)", closed, m_symbol, targetMagic);
      return closed;
   }

   //+---------------------------------------------------------------+
   //| Close half volume of positions matching Magic & Symbol        |
   //+---------------------------------------------------------------+
   int CloseHalf(const ulong targetMagic = 0)
   {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_position.SelectByIndex(i) || !IsMatchingPosition(targetMagic))
            continue;

         double volume   = m_position.Volume();
         double half_vol = CSymbolHelper::NormalizeLot(m_symbol, volume * 0.5);
         double min_vol  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

         if(half_vol < min_vol || half_vol >= volume)
            continue;

         if(m_trade.PositionClosePartial(m_position.Ticket(), half_vol))
         {
            PrintFormat("Closed half volume %.2f of position #%I64u", half_vol, m_position.Ticket());
            closed++;
         }
      }
      return closed;
   }

   //+---------------------------------------------------------------+
   //| Move Stop Loss to Entry Price (Breakeven) for profitable trades|
   //+---------------------------------------------------------------+
   int MoveToBreakeven(const ulong targetMagic = 0)
   {
      int updated = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_position.SelectByIndex(i) || !IsMatchingPosition(targetMagic))
            continue;

         double open_price    = m_position.PriceOpen();
         double current_sl    = m_position.StopLoss();
         double current_tp    = m_position.TakeProfit();
         double current_price = m_position.PriceCurrent();
         ENUM_POSITION_TYPE type = m_position.PositionType();

         bool isProfitable = (type == POSITION_TYPE_BUY)
                             ? (current_price > open_price && (current_sl < open_price || current_sl == 0.0))
                             : (current_price < open_price && (current_sl > open_price || current_sl == 0.0));

         if(!isProfitable)
            continue;

         if(m_trade.PositionModify(m_position.Ticket(), open_price, current_tp))
            updated++;
      }
      PrintFormat("MoveToBreakeven: Updated %d position(s) to breakeven", updated);
      return updated;
   }

   //+---------------------------------------------------------------+
   //| Close specific position by ticket                             |
   //+---------------------------------------------------------------+
   bool CloseTicket(const ulong ticket)
   {
      return m_trade.PositionClose(ticket);
   }

   //+---------------------------------------------------------------+
   //| Check if open trade exists for symbol and magic               |
   //+---------------------------------------------------------------+
   bool HasPosition(const ulong targetMagic = 0)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(m_position.SelectByIndex(i) && IsMatchingPosition(targetMagic))
            return true;
      }
      return false;
   }

   //+---------------------------------------------------------------+
   //| Get Position Counts, Volume, and Floating P/L                 |
   //+---------------------------------------------------------------+
   void GetSummary(int &buyCount, int &sellCount, double &totalLots, double &totalProfit, const ulong targetMagic = 0)
   {
      buyCount    = 0;
      sellCount   = 0;
      totalLots   = 0.0;
      totalProfit = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(!m_position.SelectByIndex(i) || !IsMatchingPosition(targetMagic))
            continue;

         if(m_position.PositionType() == POSITION_TYPE_BUY)
            buyCount++;
         else if(m_position.PositionType() == POSITION_TYPE_SELL)
            sellCount++;

         totalLots   += m_position.Volume();
         totalProfit += (m_position.Profit() + m_position.Swap());
      }
   }
};

