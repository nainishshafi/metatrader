//+------------------------------------------------------------------+
//|                                                     ChartGUI.mqh |
//|                     Generic High-Performance Chart GUI Library   |
//|               Reusable across any MQL5 Dashboard or Panel EA     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

class CChartGUI
{
public:
   //+---------------------------------------------------------------+
   //| Create a Styled Background Panel (Default ZORDER = 0)         |
   //+---------------------------------------------------------------+
   static bool CreatePanel(const string name,
                           const int x,
                           const int y,
                           const int width,
                           const int height,
                           const color bgColor,
                           const color borderColor,
                           const int zOrder = 0)
   {
      ObjectDelete(0, name);
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return false;

      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, borderColor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, zOrder);
      return true;
   }

   //+---------------------------------------------------------------+
   //| Create an Informational Label (Default ZORDER = 10)           |
   //+---------------------------------------------------------------+
   static bool CreateLabel(const string name,
                           const string text,
                           const int x,
                           const int y,
                           const color textColor,
                           const int fontSize = 9,
                           const bool isBold = false,
                           const string fontName = "Segoe UI",
                           const int zOrder = 10)
   {
      ObjectDelete(0, name);
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return false;

      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, isBold ? fontName + " Bold" : fontName);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, zOrder);
      return true;
   }

   //+---------------------------------------------------------------+
   //| Create an Interactive Button (Default ZORDER = 100)           |
   //+---------------------------------------------------------------+
   static bool CreateButton(const string name,
                            const string text,
                            const int x,
                            const int y,
                            const int width,
                            const int height,
                            const color bgColor,
                            const color textColor,
                            const int fontSize = 9,
                            const string fontName = "Segoe UI Semibold",
                            const int zOrder = 100)
   {
      ObjectDelete(0, name);
      if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
         return false;

      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, fontName);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, zOrder);
      return true;
   }

   //+---------------------------------------------------------------+
   //| Delta Cache Updater: Touch chart objects ONLY when changed    |
   //| Prevents Windows GDI font re-rasterization bottlenecks        |
   //+---------------------------------------------------------------+
   static bool SetLabelIfChanged(const string name,
                                 string &cacheText,
                                 color &cacheColor,
                                 const string newText,
                                 const color newColor)
   {
      bool changed = false;
      if(cacheText != newText)
      {
         ObjectSetString(0, name, OBJPROP_TEXT, newText);
         cacheText = newText;
         changed = true;
      }
      if(newColor != clrNONE && cacheColor != newColor)
      {
         ObjectSetInteger(0, name, OBJPROP_COLOR, newColor);
         cacheColor = newColor;
         changed = true;
      }
      return changed;
   }

   //+---------------------------------------------------------------+
   //| Reset interactive button clicked state                        |
   //+---------------------------------------------------------------+
   static void ResetButtonState(const string name)
   {
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
   }

   //+---------------------------------------------------------------+
   //| Update button appearance                                      |
   //+---------------------------------------------------------------+
   static void SetButtonAppearance(const string name, const string text, const color bgColor, const color textColor = clrWhite)
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
   }

   //+---------------------------------------------------------------+
   //| Delete object safely                                          |
   //+---------------------------------------------------------------+
   static void Delete(const string name)
   {
      ObjectDelete(0, name);
   }
};

