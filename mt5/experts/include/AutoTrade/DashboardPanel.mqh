//+------------------------------------------------------------------+
//|                                               DashboardPanel.mqh |
//|                     AutoTrade Specific Dashboard Layout          |
//|                     Uses Generic CChartGUI Framework             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "Defines.mqh"
#include "..\..\..\include\GUI\ChartGUI.mqh"

class CDashboardPanel
{
private:
   // Cached state to throttle Windows GDI font re-rasterization
   string   m_cacheTitle;
   string   m_cacheEquity;
   string   m_cachePrice;
   string   m_cachePositions;
   color    m_cachePosColor;
   string   m_cacheHMA;
   color    m_cacheHMAColor;
   string   m_cacheTP;
   string   m_cacheSL;
   string   m_cacheStatus;
   color    m_cacheStatusClr;

public:
   CDashboardPanel()
   {
      ResetCache();
   }

   void ResetCache()
   {
      m_cacheTitle     = "";
      m_cacheEquity    = "";
      m_cachePrice     = "";
      m_cachePositions = "";
      m_cachePosColor  = clrNONE;
      m_cacheHMA       = "";
      m_cacheHMAColor  = clrNONE;
      m_cacheTP        = "";
      m_cacheSL        = "";
      m_cacheStatus    = "";
      m_cacheStatusClr = clrNONE;
   }

   //+---------------------------------------------------------------+
   //| Initialize All GUI Elements in Strict Chronological Order     |
   //| Uses Generic CChartGUI Helper                                 |
   //+---------------------------------------------------------------+
   void InitGUI(const int x, const int y, const int w, const int h, const bool isAutoTradeOn)
   {
      ResetCache();

      int gap = 8;
      int total_width = 3 * w + 2 * gap;
      int y_row2      = y + h + gap;
      int panel_y     = y_row2 + h + 10;
      int panel_h     = 168;

      // 1. Create Dashboard Background Panel FIRST (ZORDER = 0)
      CChartGUI::CreatePanel(PNL_BG, x, panel_y, total_width, panel_h, C'20,24,30', clrDimGray, 0);

      // 2. Create Informational Labels SECOND (ZORDER = 10)
      int lbl_x = x + 10;
      CChartGUI::CreateLabel(LBL_TITLE,     "XAU/USD AutoTrade",              lbl_x, panel_y + 8,   clrGold,        9, true,  "Segoe UI", 10);
      CChartGUI::CreateLabel(LBL_EQUITY,    "Equity: $0.00 | Lot: 0.00",      lbl_x, panel_y + 27,  clrPaleGreen,   9, false, "Segoe UI", 10);
      CChartGUI::CreateLabel(LBL_PRICE,     "Bid: 0.00 | Ask: 0.00",          lbl_x, panel_y + 46,  clrWhite,       9, false, "Segoe UI", 10);
      CChartGUI::CreateLabel(LBL_POSITIONS, "Trades: None Open | P/L: $0.00", lbl_x, panel_y + 65,  clrSilver,      9, false, "Segoe UI", 10);
      CChartGUI::CreateLabel(LBL_HMA,       "HMA Trend: Connecting...",       lbl_x, panel_y + 84,  clrLightGray,   9, false, "Segoe UI", 10);
      CChartGUI::CreateLabel(LBL_TP,        "Target TP: +$0.00 distance",     lbl_x, panel_y + 103, clrDeepSkyBlue, 9, false, "Segoe UI", 10);
      CChartGUI::CreateLabel(LBL_SL,        "Stop Loss: NONE",                lbl_x, panel_y + 122, clrLightGray,   9, false, "Segoe UI", 10);
      CChartGUI::CreateLabel(LBL_STATUS,    "Auto Trade: [ OFF - Standby ]",  lbl_x, panel_y + 141, clrOrangeRed,   9, true,  "Segoe UI", 10);

      // 3. Create Interactive Buttons LAST (ZORDER = 100)
      CChartGUI::CreateButton(BTN_BUY,   "BUY",       x,                 y, w, h, clrForestGreen,   clrWhite, 9, "Segoe UI Semibold", 100);
      CChartGUI::CreateButton(BTN_SELL,  "SELL",      x + (w + gap),     y, w, h, clrCrimson,       clrWhite, 9, "Segoe UI Semibold", 100);
      CChartGUI::CreateButton(BTN_CLOSE, "Close All", x + 2 * (w + gap), y, w, h, clrDarkSlateGray, clrWhite, 9, "Segoe UI Semibold", 100);

      CChartGUI::CreateButton(BTN_CLOSE_HALF, "Close Half", x,                 y_row2, w, h, clrSteelBlue,  clrWhite, 9, "Segoe UI Semibold", 100);
      CChartGUI::CreateButton(BTN_UPDATE_SL,  "Update SL",  x + (w + gap),     y_row2, w, h, clrDarkOrange, clrWhite, 9, "Segoe UI Semibold", 100);
      CChartGUI::CreateButton(BTN_TRADE,      (isAutoTradeOn ? "Trade: ON" : "Trade: OFF"),
                                              x + 2 * (w + gap), y_row2, w, h,
                                              (isAutoTradeOn ? clrGreen : clrRed), clrWhite, 9, "Segoe UI Semibold", 100);

      Comment("");
   }

   void DeleteGUI()
   {
      CChartGUI::Delete(BTN_BUY);
      CChartGUI::Delete(BTN_SELL);
      CChartGUI::Delete(BTN_CLOSE);
      CChartGUI::Delete(BTN_CLOSE_HALF);
      CChartGUI::Delete(BTN_UPDATE_SL);
      CChartGUI::Delete(BTN_TRADE);

      CChartGUI::Delete(PNL_BG);
      CChartGUI::Delete(LBL_TITLE);
      CChartGUI::Delete(LBL_EQUITY);
      CChartGUI::Delete(LBL_PRICE);
      CChartGUI::Delete(LBL_POSITIONS);
      CChartGUI::Delete(LBL_HMA);
      CChartGUI::Delete(LBL_TP);
      CChartGUI::Delete(LBL_SL);
      CChartGUI::Delete(LBL_STATUS);

      Comment("");
   }

   void SetTradeButtonState(const bool isAutoTradeOn)
   {
      if(isAutoTradeOn)
         CChartGUI::SetButtonAppearance(BTN_TRADE, "Trade: ON", clrGreen, clrWhite);
      else
         CChartGUI::SetButtonAppearance(BTN_TRADE, "Trade: OFF", clrRed, clrWhite);
   }

   void ResetButtonState(const string name)
   {
      CChartGUI::ResetButtonState(name);
   }

   //+---------------------------------------------------------------+
   //| Delta-Only Dashboard Refresh via Generic CChartGUI Cache     |
   //+---------------------------------------------------------------+
   void UpdateDashboard(const string symbol,
                        const double equity,
                        const double calcLot,
                        const double bid,
                        const double ask,
                        const int buyCount,
                        const int sellCount,
                        const double totalVol,
                        const double totalProfit,
                        const bool hasHMA,
                        const double trend,
                        const double hmaPrice,
                        const ENUM_TIMEFRAMES hmaTF,
                        const int hmaPeriod,
                        const int barsCalculated,
                        const double tpDistance,
                        const double slDistance,
                        const bool isAutoTradeOn,
                        const bool forceRedraw = false)
   {
      bool anyChanged = forceRedraw;
      color dummyClr  = clrNONE;
      int digits      = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      // 1. Title
      if(CChartGUI::SetLabelIfChanged(LBL_TITLE, m_cacheTitle, dummyClr,
                                      StringFormat("XAU/USD AutoTrade (%s)", symbol), clrNONE))
         anyChanged = true;

      // 2. Equity & Lot
      if(CChartGUI::SetLabelIfChanged(LBL_EQUITY, m_cacheEquity, dummyClr,
                                      StringFormat("Equity: $%.2f | Lot: %.2f", equity, calcLot), clrNONE))
         anyChanged = true;

      // 3. Bid / Ask
      if(CChartGUI::SetLabelIfChanged(LBL_PRICE, m_cachePrice, dummyClr,
                                      StringFormat("Bid: %.*f | Ask: %.*f", digits, bid, digits, ask), clrNONE))
         anyChanged = true;

      // 4. Open Positions
      string posText;
      color  posColor;
      if(buyCount > 0 || sellCount > 0)
      {
         string posType = (buyCount > 0 && sellCount > 0) ? "HEDGE" : (buyCount > 0 ? "BUY" : "SELL");
         posColor = (totalProfit > 0.0) ? clrLime : (totalProfit < 0.0 ? clrOrangeRed : clrWhite);
         posText  = StringFormat("Trades: %s (%.2f lot) | P/L: %s$%.2f",
                                 posType, totalVol, (totalProfit >= 0.0 ? "+" : ""), totalProfit);
      }
      else
      {
         posText  = "Trades: None Open | P/L: $0.00";
         posColor = clrSilver;
      }
      if(CChartGUI::SetLabelIfChanged(LBL_POSITIONS, m_cachePositions, m_cachePosColor, posText, posColor))
         anyChanged = true;

      // 5. HMA Trend
      string hmaText;
      color  hmaColor;
      if(hasHMA)
      {
         if(trend == 1.0)
         {
            hmaText  = StringFormat("HMA (%s,%d): UP / Bullish (%.*f)",
                                    EnumToString(hmaTF), hmaPeriod, digits, hmaPrice);
            hmaColor = clrLimeGreen;
         }
         else if(trend == -1.0)
         {
            hmaText  = StringFormat("HMA (%s,%d): DOWN / Bearish (%.*f)",
                                    EnumToString(hmaTF), hmaPeriod, digits, hmaPrice);
            hmaColor = clrOrange;
         }
         else
         {
            hmaText  = StringFormat("HMA (%s,%d): Neutral (%.*f)",
                                    EnumToString(hmaTF), hmaPeriod, digits, hmaPrice);
            hmaColor = clrLightGray;
         }
      }
      else
      {
         hmaText  = (barsCalculated < 0) ? "HMA NRP: Initializing Indicator..."
                                         : StringFormat("HMA NRP: Loading Bars (%d)...", barsCalculated);
         hmaColor = clrDarkGray;
      }
      if(CChartGUI::SetLabelIfChanged(LBL_HMA, m_cacheHMA, m_cacheHMAColor, hmaText, hmaColor))
         anyChanged = true;

      // 6. TP Distance
      string tpText = (tpDistance > 0.0) ? StringFormat("Target TP: +$%.2f dist (TP: %.*f)", tpDistance, digits, (ask > 0 ? ask + tpDistance : 0.0))
                                         : "Target TP: NONE";
      if(CChartGUI::SetLabelIfChanged(LBL_TP, m_cacheTP, dummyClr, tpText, clrNONE))
         anyChanged = true;

      // 7. SL Distance
      string slText = (slDistance > 0.0) ? StringFormat("Target SL: -$%.2f dist (SL: %.*f)", slDistance, digits, (ask > 0 ? ask - slDistance : 0.0))
                                         : "Stop Loss: NONE (Disabled)";
      if(CChartGUI::SetLabelIfChanged(LBL_SL, m_cacheSL, dummyClr, slText, clrNONE))
         anyChanged = true;

      // 8. AutoTrade Status
      string statusText = isAutoTradeOn ? "Auto Trade: [ ON - Active ]" : "Auto Trade: [ OFF - Standby ]";
      color  statusColor = isAutoTradeOn ? clrLime : clrOrangeRed;
      if(CChartGUI::SetLabelIfChanged(LBL_STATUS, m_cacheStatus, m_cacheStatusClr, statusText, statusColor))
         anyChanged = true;

      if(anyChanged)
         ChartRedraw(0);
   }
};
