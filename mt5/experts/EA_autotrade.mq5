//+------------------------------------------------------------------+
//|                                                 EA_autotrade.mq5 |
//|                                        Converted to MQL5 for MT5 |
//|           Designed for XAU/USD (Gold) with Dynamic Equity Sizing |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026"
#property link        ""
#property version     "3.00"
#property description "EA AutoTrade: Multi-action On-Chart Trading Panel & Automated Trading with HMA NRP for XAU/USD"

//--- Architecture Includes
#include "include/AutoTrade/TradingSystem.mqh"

//--- Input Parameters
input group "=== Position Sizing & Equity Calculation ==="
input double InpEquityPer1Lot        = 50000.0;        // Account Equity required per 1.0 Lot (e.g. $50,000 = 1.0 Lot)
input bool   InpUseAutoLotSizing     = true;           // Auto-calculate lot size based on current equity
input double InpFixedLotSize         = 0.20;           // Fixed lot size (used if auto sizing is false)

input group "=== Stop Loss & Take Profit ($ Price Distance) ==="
input double InpTakeProfitPriceDist  = 5.0;            // Take profit distance in $ (e.g. 5.0 means +$5.00 gold move: Buy at 4100 -> TP 4105)
input double InpStopLossPriceDist    = 0.0;            // Stop loss distance in $ (0.0 = No Stop Loss)

input group "=== HMA NRP Indicator Settings ==="
input string          InpHMAIndicator        = "HMA nrp";    // Indicator name (in MQL5\Indicators\)
input ENUM_TIMEFRAMES InpHMATimeFrame        = PERIOD_M15;   // Indicator Timeframe
input int             InpHMAPeriod           = 21;           // HMA Period
input bool            InpCloseOnTrendReverse = true;         // Auto-close open position on opposite HMA trend reversal
input bool            InpAutoTradeOnce       = true;         // Turn off Trade button after opening a trade

input group "=== Magic Numbers & Execution Settings ==="
input ulong  InpMagicAuto            = 1234;           // Magic Number for Auto Trades
input ulong  InpMagicManual          = 9999;           // Magic Number for Manual Panel Trades
input ulong  InpSlippagePoints       = 30;             // Allowed slippage (points)

input group "=== GUI Panel Configuration ==="
input int    InpButtonX              = 20;             // Panel X coordinate (pixels)
input int    InpButtonY              = 25;             // Panel Y coordinate (pixels)
input int    InpButtonWidth          = 85;             // Button width
input int    InpButtonHeight         = 28;             // Button height

//--- Global Trading System Instance (Facade)
CTradingSystem g_system;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SAutoTradeConfig cfg;
   cfg.equityPer1Lot        = InpEquityPer1Lot;
   cfg.useAutoLotSizing     = InpUseAutoLotSizing;
   cfg.fixedLotSize         = InpFixedLotSize;
   cfg.takeProfitPriceDist  = InpTakeProfitPriceDist;
   cfg.stopLossPriceDist    = InpStopLossPriceDist;
   cfg.hmaIndicator         = InpHMAIndicator;
   cfg.hmaTimeFrame         = InpHMATimeFrame;
   cfg.hmaPeriod            = InpHMAPeriod;
   cfg.closeOnTrendReverse  = InpCloseOnTrendReverse;
   cfg.autoTradeOnce        = InpAutoTradeOnce;
   cfg.magicAuto            = InpMagicAuto;
   cfg.magicManual          = InpMagicManual;
   cfg.slippagePoints       = InpSlippagePoints;
   cfg.buttonX              = InpButtonX;
   cfg.buttonY              = InpButtonY;
   cfg.buttonWidth          = InpButtonWidth;
   cfg.buttonHeight         = InpButtonHeight;

   return g_system.Init(cfg);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_system.Deinit(reason);
}

//+------------------------------------------------------------------+
//| Expert tick function (Executed on every market tick)             |
//+------------------------------------------------------------------+
void OnTick()
{
   g_system.OnTick();
}

//+------------------------------------------------------------------+
//| Timer Event Handler (1-second UI refresh decoupled from OnTick)  |
//+------------------------------------------------------------------+
void OnTimer()
{
   g_system.OnTimer();
}

//+------------------------------------------------------------------+
//| Chart Event Handler (Interactive Button Click Dispatcher)        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   g_system.OnChartEvent(id, lparam, dparam, sparam);
}
//+------------------------------------------------------------------+
