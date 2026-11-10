//+------------------------------------------------------------------+
//|                                                TradingSystem.mqh |
//|                     Trading System Unified Controller (Facade)   |
//|               Coordinates Generic Framework & AutoTrade Logic    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "Defines.mqh"
#include "..\..\..\include\Common\SymbolHelper.mqh"
#include "..\..\..\include\Trade\PositionManager.mqh"
#include "HMASignal.mqh"
#include "DashboardPanel.mqh"

class CTradingSystem
{
private:
   SAutoTradeConfig  m_config;
   string            m_symbol;
   bool              m_isAutoTradeOn;

   CHMASignal        m_signals;
   CPositionManager  m_positions;
   CDashboardPanel   m_dashboard;

   bool CheckAlgoTradingAllowed()
   {
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      {
         Print("Warning: MT5 'Algo Trading' button is OFF! Please click 'Algo Trading' in top MT5 toolbar.");
         return false;
      }
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      {
         Print("Warning: 'Allow Algo Trading' is disabled in EA Properties! Press F7 -> Common -> Check 'Allow Algo Trading'.");
         return false;
      }
      return true;
   }

   void ToggleAutoTrade()
   {
      m_isAutoTradeOn = !m_isAutoTradeOn;

      // If turning ON and indicator handle not ready, attempt reload
      if(m_isAutoTradeOn && !m_signals.IsReady())
         m_signals.LoadHandle();

      m_dashboard.SetTradeButtonState(m_isAutoTradeOn);
   }

   void RefreshDashboard(const bool forceRedraw = false)
   {
      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      double calcLot  = CSymbolHelper::CalculateLotFromEquity(m_symbol, m_config.useAutoLotSizing, m_config.fixedLotSize, m_config.equityPer1Lot);
      double bid      = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask      = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      int buyCount = 0, sellCount = 0;
      double totalVol = 0.0, totalProfit = 0.0;
      m_positions.GetSummary(buyCount, sellCount, totalVol, totalProfit, 0);

      double trend = m_signals.GetLastTrend();
      double hmaPrice = m_signals.GetLastPrice();
      bool hasHMA = m_signals.IsReady();
      int barsCalc = m_signals.GetBarsCalculated();

      m_dashboard.UpdateDashboard(m_symbol, equity, calcLot, bid, ask,
                                  buyCount, sellCount, totalVol, totalProfit,
                                  hasHMA, trend, hmaPrice,
                                  m_config.hmaTimeFrame, m_config.hmaPeriod, barsCalc,
                                  m_config.takeProfitPriceDist, m_config.stopLossPriceDist,
                                  m_isAutoTradeOn, forceRedraw);
   }

   //+---------------------------------------------------------------+
   //| Check and manage reversal exits for automated positions       |
   //+---------------------------------------------------------------+
   void CheckReversals()
   {
      CPositionInfo pos;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(pos.SelectByIndex(i))
         {
            if(pos.Symbol() == m_symbol && pos.Magic() == m_config.magicAuto)
            {
               if(m_signals.ShouldReverseExit(pos.PositionType()))
               {
                  PrintFormat("Strategy Reversal Exit: Closing #%I64u on opposite signal", pos.Ticket());
                  m_positions.CloseTicket(pos.Ticket());
               }
            }
         }
      }
   }

public:
   CTradingSystem() : m_symbol(""), m_isAutoTradeOn(false) {}

   int Init(const SAutoTradeConfig &config)
   {
      m_config        = config;
      m_symbol        = _Symbol;
      m_isAutoTradeOn = false;

      // 1. Initialize Trade Position Manager (Generic)
      if(!m_positions.Init(m_symbol, m_config.slippagePoints))
         return INIT_FAILED;

      // 2. Initialize GUI Dashboard (Uses Generic CChartGUI)
      m_dashboard.InitGUI(m_config.buttonX, m_config.buttonY,
                          m_config.buttonWidth, m_config.buttonHeight,
                          m_isAutoTradeOn);

      // 3. Initialize HMA Indicator Strategy (Implements Generic ISignal)
      m_signals.Init(m_symbol, m_config.hmaTimeFrame, m_config.hmaIndicator, m_config.hmaPeriod);

      EventSetTimer(1); // 1-second UI refresh timer
      RefreshDashboard(true);

      PrintFormat("EA AutoTrade initialized successfully. Symbol: %s, Current Equity: $%.2f, Lot: %.2f",
                  m_symbol, AccountInfoDouble(ACCOUNT_EQUITY),
                  CSymbolHelper::CalculateLotFromEquity(m_symbol, m_config.useAutoLotSizing, m_config.fixedLotSize, m_config.equityPer1Lot));
      return INIT_SUCCEEDED;
   }

   void Deinit(const int reason)
   {
      EventKillTimer();
      m_dashboard.DeleteGUI();
      m_signals.Deinit();
      ChartRedraw(0);
   }

   void OnTimer()
   {
      RefreshDashboard(false);
   }

   void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
   {
      if(id != CHARTEVENT_OBJECT_CLICK)
         return;

      if(sparam == BTN_BUY)
      {
         m_dashboard.ResetButtonState(BTN_BUY);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         double lots = CSymbolHelper::CalculateLotFromEquity(m_symbol, m_config.useAutoLotSizing, m_config.fixedLotSize, m_config.equityPer1Lot);
         m_positions.ExecuteBuy(lots, m_config.magicManual, m_config.stopLossPriceDist, m_config.takeProfitPriceDist, "Manual Buy");
         RefreshDashboard(true);
      }
      else if(sparam == BTN_SELL)
      {
         m_dashboard.ResetButtonState(BTN_SELL);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         double lots = CSymbolHelper::CalculateLotFromEquity(m_symbol, m_config.useAutoLotSizing, m_config.fixedLotSize, m_config.equityPer1Lot);
         m_positions.ExecuteSell(lots, m_config.magicManual, m_config.stopLossPriceDist, m_config.takeProfitPriceDist, "Manual Sell");
         RefreshDashboard(true);
      }
      else if(sparam == BTN_CLOSE)
      {
         m_dashboard.ResetButtonState(BTN_CLOSE);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         m_positions.CloseAll(0); // 0 = closes all on symbol
         RefreshDashboard(true);
      }
      else if(sparam == BTN_CLOSE_HALF)
      {
         m_dashboard.ResetButtonState(BTN_CLOSE_HALF);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         m_positions.CloseHalf(0);
         RefreshDashboard(true);
      }
      else if(sparam == BTN_UPDATE_SL)
      {
         m_dashboard.ResetButtonState(BTN_UPDATE_SL);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         m_positions.MoveToBreakeven(0);
         RefreshDashboard(true);
      }
      else if(sparam == BTN_TRADE)
      {
         ToggleAutoTrade();
         RefreshDashboard(true);
      }
   }

   void OnTick()
   {
      bool hasPositions = m_positions.HasPosition(0);

      // Fast-path exit
      if(!m_isAutoTradeOn && (!m_config.closeOnTrendReverse || !hasPositions))
         return;

      // Check reversals for automated trades
      if(hasPositions && m_config.closeOnTrendReverse)
         CheckReversals();

      // Automated trading execution
      if(!m_isAutoTradeOn || !m_signals.IsReady())
         return;

      // Ensure no active automated position is already open
      if(m_positions.HasPosition(m_config.magicAuto))
         return;

      ENUM_STRATEGY_SIGNAL signal = m_signals.EvaluateSignal();

      if(signal == STRATEGY_SIGNAL_BUY)
      {
         double lots = CSymbolHelper::CalculateLotFromEquity(m_symbol, m_config.useAutoLotSizing, m_config.fixedLotSize, m_config.equityPer1Lot);
         if(m_positions.ExecuteBuy(lots, m_config.magicAuto, m_config.stopLossPriceDist, m_config.takeProfitPriceDist, "Auto Buy (HMA)"))
         {
            if(m_config.autoTradeOnce)
            {
               m_isAutoTradeOn = false;
               m_dashboard.SetTradeButtonState(false);
            }
            RefreshDashboard(true);
         }
      }
      else if(signal == STRATEGY_SIGNAL_SELL)
      {
         double lots = CSymbolHelper::CalculateLotFromEquity(m_symbol, m_config.useAutoLotSizing, m_config.fixedLotSize, m_config.equityPer1Lot);
         if(m_positions.ExecuteSell(lots, m_config.magicAuto, m_config.stopLossPriceDist, m_config.takeProfitPriceDist, "Auto Sell (HMA)"))
         {
            if(m_config.autoTradeOnce)
            {
               m_isAutoTradeOn = false;
               m_dashboard.SetTradeButtonState(false);
            }
            RefreshDashboard(true);
         }
      }
   }
};
