//+------------------------------------------------------------------+
//|                                                      ProjectName |
//|                                      Copyright 2018, CompanyName |
//|                                       http://www.companyname.net |
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_buffers 1
#property indicator_plots   1
//--- plot Output
#property indicator_label1  "Average Speed"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrGreen
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_level1 2.0
#property indicator_levelcolor Gray
#property indicator_levelstyle STYLE_DASHDOTDOT

// Define parameters
input int ARRAY_SIZE = 100; // Size of the FIFO array

// Define variables
double bidArray[];
double         OutputBuffer[];
//+------------------------------------------------------------------+
//| Indicator initialization function                              |
//+------------------------------------------------------------------+
int OnInit()
  {
// Set up the indicator buffer
   SetIndexBuffer(0,OutputBuffer,INDICATOR_DATA);
 
// Initialize the ticks array with 0 values
   ArraySetAsSeries(bidArray, true);
   ArrayResize(bidArray, ARRAY_SIZE);
   ArrayInitialize(bidArray, SymbolInfoDouble(_Symbol, SYMBOL_BID));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void addToFIFO()
  {
// Shift elements to make room for the new value
   for(int i = ARRAY_SIZE - 1; i > 0; i--)
     {
      bidArray[i] = bidArray[i - 1];
     }

// Add the current bid at the beginning of the array
   bidArray[0] = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  }

//+------------------------------------------------------------------+
//| Indicator calculation function                                  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   addToFIFO();

// Calculate average speed
   double totalSpeed = 0.0;
   for(int i = 0; i < ARRAY_SIZE; i++)
     {
      totalSpeed += bidArray[i];
     }
   double averageSpeed = totalSpeed / ARRAY_SIZE;

// Set the value for the histogram
   OutputBuffer[0] = averageSpeed;

// Display the current average speed value in a separate label
   Comment("Average Speed: ", DoubleToStr(OutputBuffer[0], Digits));

   return(rates_total);
  }
//+------------------------------------------------------------------+
