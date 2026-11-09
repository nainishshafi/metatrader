//+------------------------------------------------------------------+
//|                                                 EA_autotrade.mq5 |
//|                                        Converted to MQL5 for MT5 |
//|           Designed for XAU/USD (Gold) with Dynamic Equity Sizing |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026"
#property link        ""
#property version     "2.30"
#property description "EA AutoTrade: Multi-action On-Chart Trading Panel & Automated Trading with HMA NRP for XAU/USD"

//--- Standard Library Includes
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input group "=== Position Sizing & Equity Calculation ==="
input double InpLotsPer10kEquity     = 1.0;            // Lots per $10,000 Equity (e.g. $10k Equity = 1.0 Lot)
input bool   InpUseAutoLotSizing     = true;           // Auto-calculate lot size based on current equity
input double InpFixedLotSize         = 1.0;            // Fixed lot size (used if auto sizing is false)

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

//--- Button Names
const string BTN_BUY        = "EA_Btn_Buy";
const string BTN_SELL       = "EA_Btn_Sell";
const string BTN_CLOSE      = "EA_Btn_Close";
const string BTN_CLOSE_HALF = "EA_Btn_CloseHalf";
const string BTN_UPDATE_SL  = "EA_Btn_UpdateSL";
const string BTN_TRADE      = "EA_Btn_Trade";

//--- Dashboard Element Names
const string PNL_BG         = "EA_Pnl_BG";
const string LBL_TITLE      = "EA_Lbl_Title";
const string LBL_EQUITY     = "EA_Lbl_Equity";
const string LBL_PRICE      = "EA_Lbl_Price";
const string LBL_POSITIONS  = "EA_Lbl_Positions";
const string LBL_HMA        = "EA_Lbl_HMA";
const string LBL_TP         = "EA_Lbl_TP";
const string LBL_SL         = "EA_Lbl_SL";
const string LBL_STATUS     = "EA_Lbl_Status";

//--- Global Variables
CTrade         g_trade;
CPositionInfo  g_position;
bool           g_isAutoTradeOn   = false;
int            g_hHMA            = INVALID_HANDLE;
bool           g_hmaLogged       = false;

// Cached HMA State
bool           g_hasHMA          = false;
double         g_hmaTrend        = 0.0;
double         g_hmaPrice        = 0.0;

// Cached Dashboard Label State (prevents redundant GDI font re-rasterization)
string         g_cacheTitle      = "";
string         g_cacheEquity     = "";
string         g_cachePrice      = "";
string         g_cachePositions  = "";
color          g_cachePosColor   = clrNONE;
string         g_cacheHMA        = "";
color          g_cacheHMAColor   = clrNONE;
string         g_cacheTP         = "";
string         g_cacheSL         = "";
string         g_cacheStatus     = "";
color          g_cacheStatusClr  = clrNONE;

//+------------------------------------------------------------------+
//| Fast Label Updater: Only touches chart object if value changed   |
//+------------------------------------------------------------------+
bool SetLabelIfChanged(const string name, string &cache_text, color &cache_clr, const string new_text, const color new_clr)
  {
   bool changed = false;
   if(cache_text != new_text)
     {
      ObjectSetString(0, name, OBJPROP_TEXT, new_text);
      cache_text = new_text;
      changed = true;
     }
   if(new_clr != clrNONE && cache_clr != new_clr)
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR, new_clr);
      cache_clr = new_clr;
      changed = true;
     }
   return(changed);
  }

//+------------------------------------------------------------------+
//| Normalize lots according to broker specification                 |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0.0)    step = 0.01;
   if(min_lot <= 0.0) min_lot = 0.01;
   if(max_lot <= 0.0) max_lot = 100.0;

   lot = MathFloor(lot / step) * step;
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;

   int digits = (step >= 0.1) ? 1 : 2;
   return(NormalizeDouble(lot, digits));
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Account Equity                       |
//| Rule: $10,000 Equity = 1.0 Lot (scalable proportionally)         |
//+------------------------------------------------------------------+
double CalculateLotSize()
  {
   if(!InpUseAutoLotSizing)
      return(NormalizeLot(InpFixedLotSize));

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      equity = AccountInfoDouble(ACCOUNT_BALANCE);

   if(equity <= 0.0)
      return(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

   // Calculate: (Equity / 10000.0) * InpLotsPer10kEquity
   double lots = (equity / 10000.0) * InpLotsPer10kEquity;
   return(NormalizeLot(lots));
  }

//+------------------------------------------------------------------+
//| Create a Styled GUI Button with Top Z-Order                      |
//+------------------------------------------------------------------+
void CreateButton(string name, string text, int x, int y, int width, int height, color bg_color, color text_color)
  {
   ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_COLOR, text_color);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 100); // Ensures top click priority over all chart elements
  }

//+------------------------------------------------------------------+
//| Create a Label inside the Dashboard                              |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int font_size = 9, bool is_bold = false)
  {
   ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, is_bold ? "Segoe UI Bold" : "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 10);
  }

//+------------------------------------------------------------------+
//| Create Dashboard Background Panel                                |
//+------------------------------------------------------------------+
void CreatePanelBg(string name, int x, int y, int width, int height, color bg_color, color border_color)
  {
   ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border_color);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
  }

//+------------------------------------------------------------------+
//| Initialize All GUI Elements (Buttons & Dashboard Panel)          |
//+------------------------------------------------------------------+
void InitGUI()
  {
   // Reset label caches on GUI creation
   g_cacheTitle     = "";
   g_cacheEquity    = "";
   g_cachePrice     = "";
   g_cachePositions = "";
   g_cachePosColor  = clrNONE;
   g_cacheHMA       = "";
   g_cacheHMAColor  = clrNONE;
   g_cacheTP        = "";
   g_cacheSL        = "";
   g_cacheStatus    = "";
   g_cacheStatusClr = clrNONE;

   int x = InpButtonX;
   int y = InpButtonY;
   int w = InpButtonWidth;
   int h = InpButtonHeight;
   int gap = 8;
   int total_width = 3 * w + 2 * gap; // Width across 3 buttons
   int y_row2 = y + h + gap;

   // 1. Create Dashboard Background Panel FIRST (chronologically behind labels and buttons)
   int panel_y = y_row2 + h + 10;
   int panel_h = 168;
   CreatePanelBg(PNL_BG, x, panel_y, total_width, panel_h, C'20,24,30', clrDimGray);

   // 2. Create Dashboard Information Labels
   int lbl_x = x + 10;
   CreateLabel(LBL_TITLE,     "XAU/USD AutoTrade",                   lbl_x, panel_y + 8,   clrGold,        9, true);
   CreateLabel(LBL_EQUITY,    "Equity: $0.00 | Lot: 0.00",           lbl_x, panel_y + 27,  clrPaleGreen,   9, false);
   CreateLabel(LBL_PRICE,     "Bid: 0.00 | Ask: 0.00",               lbl_x, panel_y + 46,  clrWhite,       9, false);
   CreateLabel(LBL_POSITIONS, "Trades: None Open | P/L: $0.00",      lbl_x, panel_y + 65,  clrSilver,      9, false);
   CreateLabel(LBL_HMA,       "HMA Trend: Connecting...",            lbl_x, panel_y + 84,  clrLightGray,   9, false);
   CreateLabel(LBL_TP,        "Target TP: +$0.00 distance",          lbl_x, panel_y + 103, clrDeepSkyBlue, 9, false);
   CreateLabel(LBL_SL,        "Stop Loss: NONE",                     lbl_x, panel_y + 122, clrLightGray,   9, false);
   CreateLabel(LBL_STATUS,    "Auto Trade: [ OFF - Standby ]",       lbl_x, panel_y + 141, clrOrangeRed,   9, true);

   // 3. Create Interactive Buttons LAST so they are on top of the visual and input hierarchy
   CreateButton(BTN_BUY,   "BUY",       x,                 y, w, h, clrForestGreen,   clrWhite);
   CreateButton(BTN_SELL,  "SELL",      x + (w + gap),     y, w, h, clrCrimson,       clrWhite);
   CreateButton(BTN_CLOSE, "Close All", x + 2 * (w + gap), y, w, h, clrDarkSlateGray, clrWhite);

   CreateButton(BTN_CLOSE_HALF, "Close Half", x,                 y_row2, w, h, clrSteelBlue,  clrWhite);
   CreateButton(BTN_UPDATE_SL,  "Update SL",  x + (w + gap),     y_row2, w, h, clrDarkOrange, clrWhite);
   CreateButton(BTN_TRADE,      (g_isAutoTradeOn ? "Trade: ON" : "Trade: OFF"),
                                              x + 2 * (w + gap), y_row2, w, h,
                                              (g_isAutoTradeOn ? clrGreen : clrRed), clrWhite);

   Comment(""); // Clear chart comment to prevent any background text collision
  }

//+------------------------------------------------------------------+
//| Delete All GUI Elements                                          |
//+------------------------------------------------------------------+
void DeleteGUI()
  {
   ObjectDelete(0, BTN_BUY);
   ObjectDelete(0, BTN_SELL);
   ObjectDelete(0, BTN_CLOSE);
   ObjectDelete(0, BTN_CLOSE_HALF);
   ObjectDelete(0, BTN_UPDATE_SL);
   ObjectDelete(0, BTN_TRADE);

   ObjectDelete(0, PNL_BG);
   ObjectDelete(0, LBL_TITLE);
   ObjectDelete(0, LBL_EQUITY);
   ObjectDelete(0, LBL_PRICE);
   ObjectDelete(0, LBL_POSITIONS);
   ObjectDelete(0, LBL_HMA);
   ObjectDelete(0, LBL_TP);
   ObjectDelete(0, LBL_SL);
   ObjectDelete(0, LBL_STATUS);

   Comment("");
  }

//+------------------------------------------------------------------+
//| Attempt to create handle for HMA NRP indicator                   |
//+------------------------------------------------------------------+
int LoadHMAHandle()
  {
   int handle = INVALID_HANDLE;

   // 1. Try direct indicator name with TimeFrame and Period
   handle = iCustom(_Symbol, InpHMATimeFrame, InpHMAIndicator, InpHMATimeFrame, InpHMAPeriod);
   if(handle != INVALID_HANDLE)
      return(handle);

   // 2. Try direct indicator name with default parameters
   handle = iCustom(_Symbol, InpHMATimeFrame, InpHMAIndicator);
   if(handle != INVALID_HANDLE)
      return(handle);

   // 3. Try with Indicators\\ path and parameters
   handle = iCustom(_Symbol, InpHMATimeFrame, "Indicators\\" + InpHMAIndicator, InpHMATimeFrame, InpHMAPeriod);
   if(handle != INVALID_HANDLE)
      return(handle);

   // 4. Try with Indicators\\ path and default parameters
   handle = iCustom(_Symbol, InpHMATimeFrame, "Indicators\\" + InpHMAIndicator);
   if(handle != INVALID_HANDLE)
      return(handle);

   return(INVALID_HANDLE);
  }

//+------------------------------------------------------------------+
//| Fetch latest HMA trend direction and price value                 |
//| Trend: +1.0 = Uptrend (Green), -1.0 = Downtrend (Orange)         |
//+------------------------------------------------------------------+
bool GetHMAData(double &trend, double &price)
  {
   if(g_hHMA == INVALID_HANDLE)
      return(false);

   // Never call CopyBuffer before BarsCalculated >= 2, otherwise MT5 blocks for 46s timeout!
   if(BarsCalculated(g_hHMA) < 2)
      return(false);

   double price_arr[];
   ArraySetAsSeries(price_arr, true);

   ResetLastError();
   int copied_price = CopyBuffer(g_hHMA, 0, 0, 2, price_arr);
   if(copied_price < 2 || price_arr[0] == EMPTY_VALUE || price_arr[0] <= 0.0)
      return(false);

   price = price_arr[0];

   // Determine trend:
   // 1. Try reading Buffer 4 (TrendBuffer: +1.0 = Uptrend, -1.0 = Downtrend)
   double trend_arr[];
   ArraySetAsSeries(trend_arr, true);
   int copied_trend = CopyBuffer(g_hHMA, 4, 0, 1, trend_arr);
   if(copied_trend > 0 && trend_arr[0] != EMPTY_VALUE && trend_arr[0] != 0.0)
     {
      trend = trend_arr[0];
      return(true);
     }

   // 2. Try reading Buffer 1 (HmaColorBuffer: 0.0 = Uptrend, 1.0 = Downtrend)
   double color_arr[];
   ArraySetAsSeries(color_arr, true);
   int copied_color = CopyBuffer(g_hHMA, 1, 0, 1, color_arr);
   if(copied_color > 0 && color_arr[0] != EMPTY_VALUE)
     {
      trend = (color_arr[0] == 0.0) ? 1.0 : -1.0;
      return(true);
     }

   // 3. Mathematical Slope of HMA Line: price[0] vs price[1]
   if(price_arr[0] > price_arr[1])
      trend = 1.0;
   else if(price_arr[0] < price_arr[1])
      trend = -1.0;
   else
      trend = 0.0;

   return(true);
  }

//+------------------------------------------------------------------+
//| Get Summary of Open Positions on Current Symbol                  |
//+------------------------------------------------------------------+
void GetOpenPositionsSummary(int &buy_count, int &sell_count, double &total_lots, double &total_profit)
  {
   buy_count    = 0;
   sell_count   = 0;
   total_lots   = 0.0;
   total_profit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_position.SelectByIndex(i))
        {
         if(g_position.Symbol() == _Symbol)
           {
            if(g_position.PositionType() == POSITION_TYPE_BUY)
               buy_count++;
            else if(g_position.PositionType() == POSITION_TYPE_SELL)
               sell_count++;

            total_lots   += g_position.Volume();
            total_profit += (g_position.Profit() + g_position.Swap());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if Algo Trading is Allowed                                 |
//+------------------------------------------------------------------+
bool CheckAlgoTradingAllowed()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("Warning: MT5 'Algo Trading' button is OFF! Please click 'Algo Trading' in top MT5 toolbar.");
      return(false);
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      Print("Warning: 'Allow Algo Trading' is disabled in EA Properties! Press F7 -> Common -> Check 'Allow Algo Trading'.");
      return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Toggle Auto Trade Button State                                   |
//+------------------------------------------------------------------+
void ToggleAutoTradeButton()
  {
   g_isAutoTradeOn = !g_isAutoTradeOn;

   // If turning ON and handle is not yet acquired, retry loading
   if(g_isAutoTradeOn && g_hHMA == INVALID_HANDLE)
     {
      g_hHMA = LoadHMAHandle();
      if(g_hHMA != INVALID_HANDLE)
         PrintFormat("EA AutoTrade: Attached to HMA indicator '%s' on activation.", InpHMAIndicator);
     }

   if(g_isAutoTradeOn)
     {
      ObjectSetString(0, BTN_TRADE, OBJPROP_TEXT, "Trade: ON");
      ObjectSetInteger(0, BTN_TRADE, OBJPROP_BGCOLOR, clrGreen);
     }
   else
     {
      ObjectSetString(0, BTN_TRADE, OBJPROP_TEXT, "Trade: OFF");
      ObjectSetInteger(0, BTN_TRADE, OBJPROP_BGCOLOR, clrRed);
     }
   ObjectSetInteger(0, BTN_TRADE, OBJPROP_STATE, false);
  }

//+------------------------------------------------------------------+
//| Check if open trade already exists for this symbol               |
//+------------------------------------------------------------------+
bool OpenTradeExist()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_position.SelectByIndex(i))
        {
         if(g_position.Symbol() == _Symbol)
            return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Execute BUY Order with Dollar-Based TP & SL                      |
//+------------------------------------------------------------------+
bool ExecuteBuy(double lots, ulong magic, string comment = "Buy Order")
  {
   g_trade.SetExpertMagicNumber(magic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0.0)
     {
      Print("ExecuteBuy failed: Ask price is invalid.");
      return(false);
     }

   double tp = (InpTakeProfitPriceDist > 0.0) ? NormalizeDouble(ask + InpTakeProfitPriceDist, _Digits) : 0.0;
   double sl = (InpStopLossPriceDist > 0.0)   ? NormalizeDouble(ask - InpStopLossPriceDist, _Digits)   : 0.0;

   bool res = g_trade.Buy(lots, _Symbol, ask, sl, tp, comment);
   if(res)
      PrintFormat("BUY order executed: Lots=%.2f, Price=%.*f, SL=%.*f, TP=%.*f, Magic=%I64u",
                  lots, _Digits, ask, _Digits, sl, _Digits, tp, magic);
   else
      PrintFormat("BUY order error: %s (Code: %u)", g_trade.ResultComment(), g_trade.ResultRetcode());

   return(res);
  }

//+------------------------------------------------------------------+
//| Execute SELL Order with Dollar-Based TP & SL                     |
//+------------------------------------------------------------------+
bool ExecuteSell(double lots, ulong magic, string comment = "Sell Order")
  {
   g_trade.SetExpertMagicNumber(magic);
   g_trade.SetDeviationInPoints(InpSlippagePoints);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0)
     {
      Print("ExecuteSell failed: Bid price is invalid.");
      return(false);
     }

   double tp = (InpTakeProfitPriceDist > 0.0) ? NormalizeDouble(bid - InpTakeProfitPriceDist, _Digits) : 0.0;
   double sl = (InpStopLossPriceDist > 0.0)   ? NormalizeDouble(bid + InpStopLossPriceDist, _Digits)   : 0.0;

   bool res = g_trade.Sell(lots, _Symbol, bid, sl, tp, comment);
   if(res)
      PrintFormat("SELL order executed: Lots=%.2f, Price=%.*f, SL=%.*f, TP=%.*f, Magic=%I64u",
                  lots, _Digits, bid, _Digits, sl, _Digits, tp, magic);
   else
      PrintFormat("SELL order error: %s (Code: %u)", g_trade.ResultComment(), g_trade.ResultRetcode());

   return(res);
  }

//+------------------------------------------------------------------+
//| Close all positions on current symbol                            |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   int closed_count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_position.SelectByIndex(i))
        {
         if(g_position.Symbol() == _Symbol)
           {
            if(g_trade.PositionClose(g_position.Ticket()))
               closed_count++;
           }
        }
     }
   PrintFormat("CloseAllPositions: Closed %d position(s) on %s", closed_count, _Symbol);
  }

//+------------------------------------------------------------------+
//| Close half of each position on current symbol                    |
//+------------------------------------------------------------------+
void CloseHalfPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_position.SelectByIndex(i))
        {
         if(g_position.Symbol() == _Symbol)
           {
            double volume = g_position.Volume();
            double half_vol = NormalizeLot(volume * 0.5);
            double min_vol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

            if(half_vol >= min_vol && half_vol < volume)
              {
               if(g_trade.PositionClosePartial(g_position.Ticket(), half_vol))
                  PrintFormat("Closed half volume %.2f of position #%I64u", half_vol, g_position.Ticket());
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Move Stop Loss to Breakeven (entry price) for profitable trades  |
//+------------------------------------------------------------------+
void UpdateStoplossToBreakeven()
  {
   int updated = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_position.SelectByIndex(i))
        {
         if(g_position.Symbol() == _Symbol)
           {
            double open_price = g_position.PriceOpen();
            double current_sl = g_position.StopLoss();
            double current_tp = g_position.TakeProfit();
            double current_price = g_position.PriceCurrent();

            if(g_position.PositionType() == POSITION_TYPE_BUY)
              {
               if(current_price > open_price && (current_sl < open_price || current_sl == 0.0))
                 {
                  if(g_trade.PositionModify(g_position.Ticket(), open_price, current_tp))
                     updated++;
                 }
              }
            else if(g_position.PositionType() == POSITION_TYPE_SELL)
              {
               if(current_price < open_price && (current_sl > open_price || current_sl == 0.0))
                 {
                  if(g_trade.PositionModify(g_position.Ticket(), open_price, current_tp))
                     updated++;
                 }
              }
           }
        }
     }
   PrintFormat("UpdateStoplossToBreakeven: Updated %d position(s) to breakeven", updated);
  }

//+------------------------------------------------------------------+
//| Close trade on opposite HMA trend reversal                       |
//+------------------------------------------------------------------+
void CloseTradeOnReversal(double currentTrend, double hmaPrice)
  {
   if(!InpCloseOnTrendReverse)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_position.SelectByIndex(i))
        {
         if(g_position.Symbol() == _Symbol && g_position.Magic() == InpMagicAuto)
           {
            // If BUY trade open, and HMA trend flipped to Bearish (-1.0) and Ask < HMA line
            if(g_position.PositionType() == POSITION_TYPE_BUY)
              {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               if(currentTrend == -1.0 && ask < hmaPrice)
                 {
                  PrintFormat("HMA Reversal Exit: Closing BUY #%I64u (Trend: -1.0, Ask: %.*f < HMA: %.*f)",
                              g_position.Ticket(), _Digits, ask, _Digits, hmaPrice);
                  g_trade.PositionClose(g_position.Ticket());
                 }
              }
            // If SELL trade open, and HMA trend flipped to Bullish (+1.0) and Bid > HMA line
            else if(g_position.PositionType() == POSITION_TYPE_SELL)
              {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               if(currentTrend == 1.0 && bid > hmaPrice)
                 {
                  PrintFormat("HMA Reversal Exit: Closing SELL #%I64u (Trend: +1.0, Bid: %.*f > HMA: %.*f)",
                              g_position.Ticket(), _Digits, bid, _Digits, hmaPrice);
                  g_trade.PositionClose(g_position.Ticket());
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: Check M15 Buy breakout continuation                      |
//+------------------------------------------------------------------+
bool CheckPrev15MBuy()
  {
   double c1 = iClose(_Symbol, PERIOD_M15, 1);
   double o1 = iOpen(_Symbol, PERIOD_M15, 1);
   double h1 = iHigh(_Symbol, PERIOD_M15, 1);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   return(c1 > o1 || bid > h1);
  }

//+------------------------------------------------------------------+
//| Helper: Check M15 Sell breakout continuation                     |
//+------------------------------------------------------------------+
bool CheckPrev15MSell()
  {
   double c1 = iClose(_Symbol, PERIOD_M15, 1);
   double o1 = iOpen(_Symbol, PERIOD_M15, 1);
   double l1 = iLow(_Symbol, PERIOD_M15, 1);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   return(c1 < o1 || ask < l1);
  }

//+------------------------------------------------------------------+
//| Helper: Percentage change of Bid from current M15 open           |
//+------------------------------------------------------------------+
double GetBidPercentFromOpen()
  {
   double open_price = iOpen(_Symbol, PERIOD_M15, 0);
   if(open_price <= 0.0) return(0.0);
   double current_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return(((current_bid - open_price) / open_price) * 100.0);
  }

//+------------------------------------------------------------------+
//| Helper: Percentage change of Ask from current M15 open           |
//+------------------------------------------------------------------+
double GetAskPercentFromOpen()
  {
   double open_price = iOpen(_Symbol, PERIOD_M15, 0);
   if(open_price <= 0.0) return(0.0);
   double current_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return(((open_price - current_ask) / open_price) * 100.0);
  }

//+------------------------------------------------------------------+
//| Update On-Chart Dashboard Information (Delta-only updates)       |
//+------------------------------------------------------------------+
void UpdateDashboard(bool force_redraw = false)
  {
   bool any_changed = force_redraw;
   color dummy_clr  = clrNONE;

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double calc_lot = CalculateLotSize();
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // 1. Title line
   if(SetLabelIfChanged(LBL_TITLE, g_cacheTitle, dummy_clr,
                        StringFormat("XAU/USD AutoTrade (%s)", _Symbol), clrNONE))
      any_changed = true;

   // 2. Equity & Lots
   if(SetLabelIfChanged(LBL_EQUITY, g_cacheEquity, dummy_clr,
                        StringFormat("Equity: $%.2f | Lot: %.2f", equity, calc_lot), clrNONE))
      any_changed = true;

   // 3. Live Bid / Ask
   if(SetLabelIfChanged(LBL_PRICE, g_cachePrice, dummy_clr,
                        StringFormat("Bid: %.*f | Ask: %.*f", _Digits, bid, _Digits, ask), clrNONE))
      any_changed = true;

   // 4. Live Open Position & Current Profit
   int buy_count = 0, sell_count = 0;
   double total_vol = 0.0, total_profit = 0.0;
   GetOpenPositionsSummary(buy_count, sell_count, total_vol, total_profit);

   string pos_text;
   color  pos_color;
   if(buy_count > 0 || sell_count > 0)
     {
      string pos_type = (buy_count > 0 && sell_count > 0) ? "HEDGE" : (buy_count > 0 ? "BUY" : "SELL");
      pos_color = (total_profit > 0.0) ? clrLime : (total_profit < 0.0 ? clrOrangeRed : clrWhite);
      pos_text  = StringFormat("Trades: %s (%.2f lot) | P/L: %s$%.2f",
                               pos_type, total_vol, (total_profit >= 0.0 ? "+" : ""), total_profit);
     }
   else
     {
      pos_text  = "Trades: None Open | P/L: $0.00";
      pos_color = clrSilver;
     }
   if(SetLabelIfChanged(LBL_POSITIONS, g_cachePositions, g_cachePosColor, pos_text, pos_color))
      any_changed = true;

   // 5. Live HMA NRP Trend Direction
   double trend = 0.0, hma_p = 0.0;
   string hma_text;
   color  hma_color;
   if(GetHMAData(trend, hma_p))
     {
      g_hasHMA   = true;
      g_hmaTrend = trend;
      g_hmaPrice = hma_p;

      if(trend == 1.0)
        {
         hma_text  = StringFormat("HMA (%s,%d): UP / Bullish (%.*f)",
                                  EnumToString(InpHMATimeFrame), InpHMAPeriod, _Digits, hma_p);
         hma_color = clrLimeGreen;
        }
      else if(trend == -1.0)
        {
         hma_text  = StringFormat("HMA (%s,%d): DOWN / Bearish (%.*f)",
                                  EnumToString(InpHMATimeFrame), InpHMAPeriod, _Digits, hma_p);
         hma_color = clrOrange;
        }
      else
        {
         hma_text  = StringFormat("HMA (%s,%d): Neutral (%.*f)",
                                  EnumToString(InpHMATimeFrame), InpHMAPeriod, _Digits, hma_p);
         hma_color = clrLightGray;
        }
     }
   else
     {
      int calc = (g_hHMA != INVALID_HANDLE) ? BarsCalculated(g_hHMA) : -1;
      hma_text  = (calc < 0) ? "HMA NRP: Initializing Indicator..."
                             : StringFormat("HMA NRP: Loading Bars (%d)...", calc);
      hma_color = clrDarkGray;
     }
   if(SetLabelIfChanged(LBL_HMA, g_cacheHMA, g_cacheHMAColor, hma_text, hma_color))
      any_changed = true;

   // 6. Target Take Profit distance display
   string tp_text;
   if(InpTakeProfitPriceDist > 0.0)
     {
      double example_tp = (ask > 0.0) ? (ask + InpTakeProfitPriceDist) : 0.0;
      tp_text = StringFormat("Target TP: +$%.2f dist (TP: %.*f)", InpTakeProfitPriceDist, _Digits, example_tp);
     }
   else
     {
      tp_text = "Target TP: NONE";
     }
   if(SetLabelIfChanged(LBL_TP, g_cacheTP, dummy_clr, tp_text, clrNONE))
      any_changed = true;

   // 7. Target Stop Loss distance display
   string sl_text;
   if(InpStopLossPriceDist > 0.0)
     {
      double example_sl = (ask > 0.0) ? (ask - InpStopLossPriceDist) : 0.0;
      sl_text = StringFormat("Target SL: -$%.2f dist (SL: %.*f)", InpStopLossPriceDist, _Digits, example_sl);
     }
   else
     {
      sl_text = "Stop Loss: NONE (Disabled)";
     }
   if(SetLabelIfChanged(LBL_SL, g_cacheSL, dummy_clr, sl_text, clrNONE))
      any_changed = true;

   // 8. AutoTrade Status Indicator
   string status_text = g_isAutoTradeOn ? "Auto Trade: [ ON - Active ]" : "Auto Trade: [ OFF - Standby ]";
   color  status_clr  = g_isAutoTradeOn ? clrLime : clrOrangeRed;
   if(SetLabelIfChanged(LBL_STATUS, g_cacheStatus, g_cacheStatusClr, status_text, status_clr))
      any_changed = true;

   if(any_changed)
      ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Configure trade client
   g_trade.SetExpertMagicNumber(InpMagicManual);
   g_trade.SetDeviationInPoints(InpSlippagePoints);

   // Initialize GUI buttons and Dashboard Panel
   InitGUI();

   // Load HMA indicator handle
   g_hHMA = LoadHMAHandle();
   if(g_hHMA == INVALID_HANDLE && !g_hmaLogged)
     {
      PrintFormat("Note: HMA indicator '%s' not loaded yet. Manual panel is 100%% functional; auto-trade signals will wait for indicator.", InpHMAIndicator);
      g_hmaLogged = true;
     }
   else if(g_hHMA != INVALID_HANDLE)
     {
      PrintFormat("EA AutoTrade: Successfully attached to HMA indicator '%s' (Handle: %d, TF: %s, Period: %d)",
                  InpHMAIndicator, g_hHMA, EnumToString(InpHMATimeFrame), InpHMAPeriod);
     }

   EventSetTimer(1); // 1-second timer for dashboard update
   UpdateDashboard(true);

   PrintFormat("EA AutoTrade initialized successfully. Symbol: %s, Current Equity: $%.2f, Calculated Lot: %.2f",
               _Symbol, AccountInfoDouble(ACCOUNT_EQUITY), CalculateLotSize());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteGUI();

   if(g_hHMA != INVALID_HANDLE)
     {
      IndicatorRelease(g_hHMA);
      g_hHMA = INVALID_HANDLE;
     }

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Chart Event Handler for Button Clicks                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == BTN_BUY)
        {
         ObjectSetInteger(0, BTN_BUY, OBJPROP_STATE, false);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         double lots = CalculateLotSize();
         ExecuteBuy(lots, InpMagicManual, "Manual Buy");
         UpdateDashboard(true);
        }
      else if(sparam == BTN_SELL)
        {
         ObjectSetInteger(0, BTN_SELL, OBJPROP_STATE, false);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         double lots = CalculateLotSize();
         ExecuteSell(lots, InpMagicManual, "Manual Sell");
         UpdateDashboard(true);
        }
      else if(sparam == BTN_CLOSE)
        {
         ObjectSetInteger(0, BTN_CLOSE, OBJPROP_STATE, false);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         CloseAllPositions();
         UpdateDashboard(true);
        }
      else if(sparam == BTN_CLOSE_HALF)
        {
         ObjectSetInteger(0, BTN_CLOSE_HALF, OBJPROP_STATE, false);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         CloseHalfPositions();
         UpdateDashboard(true);
        }
      else if(sparam == BTN_UPDATE_SL)
        {
         ObjectSetInteger(0, BTN_UPDATE_SL, OBJPROP_STATE, false);
         ChartRedraw(0);
         if(!CheckAlgoTradingAllowed()) return;
         UpdateStoplossToBreakeven();
         UpdateDashboard(true);
        }
      else if(sparam == BTN_TRADE)
        {
         ToggleAutoTradeButton();
         UpdateDashboard(true);
        }
     }
  }

//+------------------------------------------------------------------+
//| Timer Event Handler                                              |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateDashboard(false);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   bool has_open_positions = (PositionsTotal() > 0);

   // Fast-path exit: if Auto Trade is OFF and no open positions need reversal monitoring, do zero work on tick
   if(!g_isAutoTradeOn && (!InpCloseOnTrendReverse || !has_open_positions))
      return;

   double currentTrend = 0.0;
   double hmaPrice     = 0.0;
   bool   hasHMA       = GetHMAData(currentTrend, hmaPrice);

   if(hasHMA)
     {
      g_hasHMA   = true;
      g_hmaTrend = currentTrend;
      g_hmaPrice = hmaPrice;

      // Check and manage reversal exits if auto trades are active
      if(has_open_positions)
         CloseTradeOnReversal(currentTrend, hmaPrice);
     }

   // Automated trading logic (only when Trade button is ON)
   if(!g_isAutoTradeOn || !hasHMA)
      return;

   // Ensure no existing trade is open for this symbol
   if(OpenTradeExist())
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0)
      return;

   double o15 = iOpen(_Symbol, PERIOD_M15, 0);
   double o1  = iOpen(_Symbol, PERIOD_M1, 0);
   double h15 = iHigh(_Symbol, PERIOD_M15, 0);
   double l15 = iLow(_Symbol, PERIOD_M15, 0);

   //+---------------------------------------------------------------+
   //| Auto BUY Condition:                                           |
   //| 1. HMA Trend Bullish (+1.0) & Bid > HMA curve                 |
   //| 2. Bid > M15 Bar Open & Bid > M1 Bar Open                     |
   //| 3. Previous M15 was bullish OR Bid broke above previous high  |
   //| 4. Bid expanded >= 0.02% from M15 Open                        |
   //| 5. Bid is at or pressing the M15 candle High                  |
   //+---------------------------------------------------------------+
   if(currentTrend == 1.0 && bid > hmaPrice &&
      bid > o15 && bid > o1 &&
      CheckPrev15MBuy() &&
      GetBidPercentFromOpen() > 0.02 &&
      bid >= (h15 - _Point))
     {
      double lots = CalculateLotSize();
      if(ExecuteBuy(lots, InpMagicAuto, "Auto Buy (HMA)"))
        {
         if(InpAutoTradeOnce)
           {
            g_isAutoTradeOn = false;
            ObjectSetString(0, BTN_TRADE, OBJPROP_TEXT, "Trade: OFF");
            ObjectSetInteger(0, BTN_TRADE, OBJPROP_BGCOLOR, clrRed);
           }
         UpdateDashboard();
        }
      return;
     }

   //+---------------------------------------------------------------+
   //| Auto SELL Condition:                                          |
   //| 1. HMA Trend Bearish (-1.0) & Ask < HMA curve                 |
   //| 2. Ask < M15 Bar Open & Ask < M1 Bar Open                     |
   //| 3. Previous M15 was bearish OR Ask broke below previous low   |
   //| 4. Ask dropped >= 0.02% from M15 Open                         |
   //| 5. Bid is at or pressing the M15 candle Low                   |
   //+---------------------------------------------------------------+
   if(currentTrend == -1.0 && ask < hmaPrice &&
      ask < o15 && ask < o1 &&
      CheckPrev15MSell() &&
      GetAskPercentFromOpen() > 0.02 &&
      bid <= (l15 + _Point))
     {
      double lots = CalculateLotSize();
      if(ExecuteSell(lots, InpMagicAuto, "Auto Sell (HMA)"))
        {
         if(InpAutoTradeOnce)
           {
            g_isAutoTradeOn = false;
            ObjectSetString(0, BTN_TRADE, OBJPROP_TEXT, "Trade: OFF");
            ObjectSetInteger(0, BTN_TRADE, OBJPROP_BGCOLOR, clrRed);
           }
         UpdateDashboard();
        }
      return;
     }
  }
//+------------------------------------------------------------------+
