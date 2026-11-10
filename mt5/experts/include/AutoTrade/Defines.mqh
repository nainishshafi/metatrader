//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                     AutoTrade System Definitions & Enums         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

//--- Button Identifiers
#define BTN_BUY        "EA_Btn_Buy"
#define BTN_SELL       "EA_Btn_Sell"
#define BTN_CLOSE      "EA_Btn_Close"
#define BTN_CLOSE_HALF "EA_Btn_CloseHalf"
#define BTN_UPDATE_SL  "EA_Btn_UpdateSL"
#define BTN_TRADE      "EA_Btn_Trade"

//--- Dashboard Element Identifiers
#define PNL_BG         "EA_Pnl_BG"
#define LBL_TITLE      "EA_Lbl_Title"
#define LBL_EQUITY     "EA_Lbl_Equity"
#define LBL_PRICE      "EA_Lbl_Price"
#define LBL_POSITIONS  "EA_Lbl_Positions"
#define LBL_HMA        "EA_Lbl_HMA"
#define LBL_TP         "EA_Lbl_TP"
#define LBL_SL         "EA_Lbl_SL"
#define LBL_STATUS     "EA_Lbl_Status"

//--- System Configuration Structure
struct SAutoTradeConfig
{
   // Position Sizing & Equity
   double            equityPer1Lot;
   bool              useAutoLotSizing;
   double            fixedLotSize;

   // Stop Loss & Take Profit ($ Distance)
   double            takeProfitPriceDist;
   double            stopLossPriceDist;

   // Indicator Settings
   string            hmaIndicator;
   ENUM_TIMEFRAMES   hmaTimeFrame;
   int               hmaPeriod;
   bool              closeOnTrendReverse;
   bool              autoTradeOnce;

   // Magic Numbers & Slippage
   ulong             magicAuto;
   ulong             magicManual;
   ulong             slippagePoints;

   // GUI Configuration
   int               buttonX;
   int               buttonY;
   int               buttonWidth;
   int               buttonHeight;
};

