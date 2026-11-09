// Define button IDs
#define BUY_BUTTON 1
#define SELL_BUTTON 2
#define CLOSE_BUTTON 3
#define CLOSE_HALF_BUTTON 4
#define UPDATE_STOPLOSS_BUTTON 5
#define TRADE_BUTTON 6

double lotSize = 0.01;  // Lot size
double lotSizeAutoTrade = 0.01;
input double stopLossPips = 200;  // Stop loss in pips
input double takeProfitPips = 400;  // Take profit in pips
input double riskPercentage = 3.0;
input double riskPercentageAuto = 1.0;

int magicAutotrade = 1234;
int magicManual = 9999;
bool triggerTrade = False;

// Define button coordinates and size
int buttonX = 20; // X-coordinate
int buttonY = 20; // Y-coordinate
int buttonWidth = 80;
int buttonHeight = 30;

input int ARRAY_SIZE = 200; // Size of the FIFO array
double bidArray[];

bool isButtonOn = false; // Initial state

// Create buttons
int OnInit()
  {
//Buy button
   CreateButton(BUY_BUTTON, "Buy", buttonX, buttonY, buttonWidth, buttonHeight);

// Sell button
   CreateButton(SELL_BUTTON, "Sell", buttonX + buttonWidth + 10, buttonY, buttonWidth, buttonHeight);

// Close button
   CreateButton(CLOSE_BUTTON, "Close", buttonX + 2 * (buttonWidth + 10), buttonY, buttonWidth, buttonHeight);

// Close Half button
   CreateButton(CLOSE_HALF_BUTTON, "Close Half", buttonX, buttonY + buttonHeight + 10, buttonWidth, buttonHeight);

// Update Stop Loss button
   CreateButton(UPDATE_STOPLOSS_BUTTON, "Update SL", buttonX + (buttonWidth + 10), buttonY + buttonHeight + 10, buttonWidth, buttonHeight);

   CreateButton(TRADE_BUTTON, "Trade", buttonX + 2 * (buttonWidth + 10), buttonY + buttonHeight + 10, buttonWidth, buttonHeight);

   EventSetMillisecondTimer(500); // Set a timer to periodically check for button clicks

   ArraySetAsSeries(bidArray, true);
   ArrayResize(bidArray, ARRAY_SIZE);
   ArrayInitialize(bidArray, SymbolInfoDouble(_Symbol, SYMBOL_BID));

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseTrade(int trend, double priceUp, double priceDown)
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false)
         break;
      if(OrderSymbol()!=Symbol())
         continue;
      if(OrderMagicNumber() == magicManual || OrderMagicNumber() == 0)
         continue;
      if(OrderType()==OP_BUY && trend == -1 && Ask < priceDown)
        {
         OrderClose(OrderTicket(),OrderLots(),Bid,0,clrNONE);
         continue;
        }
      if(OrderType()==OP_SELL && trend == 1 && Bid > priceUp)
        {
         OrderClose(OrderTicket(),OrderLots(),Ask,0,clrNONE);
         continue;
        }

     }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void addToFIFO()
  {
   for(int i = ARRAY_SIZE - 1; i > 0; i--)
     {
      bidArray[i] = bidArray[i - 1];
     }
   bidArray[0] = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  }


// Deinitialize buttons
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, OBJ_BUTTON);
  }

// Handle button clicks
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == BUY_BUTTON)
        {
         // Handle Buy button click
         BuyButtonClick();
        }
      else
         if(sparam == SELL_BUTTON)
           {
            // Handle Sell button click
            SellButtonClick();
           }
         else
            if(sparam == CLOSE_BUTTON)
              {
               // Handle Close button click
               CloseButtonClick();
              }
            else
               if(sparam == CLOSE_HALF_BUTTON)
                 {
                  // Handle Close Half button click
                  CloseHalfButtonClick();
                 }
               else
                  if(sparam == UPDATE_STOPLOSS_BUTTON)
                    {
                     // Handle Update Stop Loss button click
                     UpdateStoplossButtonClick();
                    }
                  else
                     if(sparam == TRADE_BUTTON)
                       {
                        // Handle Update Stop Loss button click
                        SetTrade();
                       }
     }
  }

void SetTrade()

  {
   isButtonOn = !isButtonOn; // Toggle the button state

// Set text and color based on the button state
   if(isButtonOn)
     {

      ObjectSetString(0, TRADE_BUTTON, OBJPROP_TEXT, "ON");
      ObjectSetInteger(0, TRADE_BUTTON, OBJPROP_BGCOLOR, clrGreen);
     }
   else
     {
      ObjectSetString(0,TRADE_BUTTON, OBJPROP_TEXT, "OFF");
      ObjectSetInteger(0, TRADE_BUTTON, OBJPROP_BGCOLOR, clrRed);
     }

  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckSpeed()
  {
   bool retValue = False;
   addToFIFO();
   double totalSpeed = 0.0;
   for(int i = 0; i < ARRAY_SIZE; i++)
     {
      totalSpeed += bidArray[i];
     }
   double averageSpeed = totalSpeed / ARRAY_SIZE ;
   double speedSpread = Bid - averageSpeed;
   if(Digits ==  3)
     {
      if(speedSpread > 0.05)
         retValue = True;
     }
   if(Digits ==  5)
     {
      if(speedSpread > 0.005)
         retValue = True;
     }
   return(retValue);
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool TradingHoursAllowed()
  {
   bool retVal = true;
   int _sec = TimeSeconds(TimeCurrent());
   int _min = TimeMinute(TimeCurrent());
   int _hour = TimeHour(TimeCurrent());
   double _time = TimeHour(TimeCurrent())*100 + TimeMinute(TimeCurrent());

   return (retVal);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void AddTrade()
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false)
         break;
      if(OrderSymbol()!=Symbol())
         continue;
      if(OrderLots() == 0.01 && triggerTrade)
        {
         if(OrderType() == OP_BUY)
           {
            if(OrderProfit() > 0 && Bid > iOpen(_Symbol, PERIOD_M15, 0) && Bid == iHigh(_Symbol, PERIOD_M15, 0) && GetBidPercentFromOpen()> 0.02)
              {
               lotSizeAutoTrade = CalculateLotSize(riskPercentageAuto);
               OpenBuyOrder(lotSizeAutoTrade, stopLossPips, takeProfitPips, 0);
               triggerTrade = False;
              }
           }

         if(OrderType() == OP_SELL)
           {
            if(OrderProfit() > 0 && Ask < iOpen(_Symbol, PERIOD_M15, 0) && Bid == iLow(_Symbol, PERIOD_M15, 0) && GetAskPercentFromOpen()> 0.02)
              {
               lotSizeAutoTrade = CalculateLotSize(riskPercentageAuto);
               OpenSellOrder(lotSizeAutoTrade, stopLossPips, takeProfitPips, 0);
               triggerTrade = False;
              }
           }
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
  {

   AddStopLossTakeProfitToOpenTrades();
   AddTrade();

//bool speedCheck = CheckSpeed();



   double currentTrend = iCustom(_Symbol, Period(), "!! gaussian filter (mtf + arrows + alerts).ex4",5, 0);
   double currentValueDown = iCustom(_Symbol, Period(), "!! gaussian filter (mtf + arrows + alerts).ex4",1, 0);
   double currentValueUp = iCustom(_Symbol, Period(), "!! gaussian filter (mtf + arrows + alerts).ex4",0, 0);

   CloseTrade(currentTrend, currentValueUp,currentValueDown);

   double _low_15min = iLow(_Symbol, PERIOD_M15, 0);
   double _low_1min = iLow(_Symbol, PERIOD_M1, 0);
   double _high_15min = iHigh(_Symbol, PERIOD_M15, 0);
   double _high_1min = iHigh(_Symbol, PERIOD_M1, 0);
   double _open_15min = iOpen(_Symbol, PERIOD_M15, 0);
   double _open_1min = iOpen(_Symbol, PERIOD_M1, 0);

   Comment(currentTrend + " " + currentValueUp + " " + currentValueDown + " " +isButtonOn + " " + triggerTrade);
   if(isButtonOn && TradingHoursAllowed() && currentTrend == 1 && Bid > currentValueUp
      && Bid > _open_15min && Bid > _open_1min && ! OpenTradeExist()&& CheckPrev15MBuy()
      && GetBidPercentFromOpen()> 0.02 && Bid == iHigh(_Symbol, PERIOD_M15, 0))
     {
      Buy();
      isButtonOn = !isButtonOn;
     }

   if(isButtonOn && TradingHoursAllowed() && currentTrend == -1 && Ask < currentValueDown
      && Ask < _open_15min && Ask < _open_1min  &&  !OpenTradeExist() && CheckPrev15MSell()
      && GetAskPercentFromOpen()> 0.02 && Bid == iLow(_Symbol, PERIOD_M15, 0))
     {
      Sell();
      isButtonOn = !isButtonOn;
     }

  }


// Function to add stop loss and take profit to open trades
void AddStopLossTakeProfitToOpenTrades()
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false)
         break;
      if(OrderSymbol()!=Symbol())
         continue;
      if(OrderStopLoss() == 0)
        {
         // Calculate stop loss and take profit levels
         Print("lloop2");
         double stopLossLevel, takeProfitLevel;
         if(OrderType() == OP_BUY)
           {
            stopLossLevel = OrderOpenPrice() - stopLossPips * Point;
            takeProfitLevel = OrderOpenPrice() + takeProfitPips * Point;
           }
         else
            if(OrderType() == OP_SELL)
              {
               stopLossLevel = OrderOpenPrice() + stopLossPips * Point;
               takeProfitLevel = OrderOpenPrice() - takeProfitPips * Point;
              }

         // Set stop loss and take profit
         OrderModify(OrderTicket(), OrderOpenPrice(), stopLossLevel, takeProfitLevel, 0, clrNONE);
         triggerTrade = True;
        }
     }
  }





//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckPrev15MBuy()
  {
   bool ret = false;
   if(iClose(Symbol(),PERIOD_M15,1) > iOpen(Symbol(),PERIOD_M15,1))
      ret = true;
   else
      if(SymbolInfoDouble(Symbol(),SYMBOL_BID) > iHigh(Symbol(),PERIOD_M15,1))
         ret = true;
   return ret;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetBidPercentFromOpen()
  {
// Calculate percentage change from open to current bid
   double openPrice = iOpen(_Symbol, PERIOD_M15, 0); // Adjust the period as needed
   double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return ((currentBid - openPrice) / openPrice) * 100;
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckPrev15MSell()
  {
   bool ret = false;
   if(iClose(Symbol(),PERIOD_M15,1) < iOpen(Symbol(),PERIOD_M15,1))
      ret = true;
   else
      if(SymbolInfoDouble(Symbol(),SYMBOL_ASK) < iLow(Symbol(),PERIOD_M15,1))
         ret = true;
   return ret;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetAskPercentFromOpen()
  {
// Calculate percentage change from open to current bid
   double openPrice = iOpen(_Symbol, PERIOD_M15, 0); // Adjust the period as needed
   double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return ((openPrice-currentAsk) / openPrice) * 100;
  }


// Button creation function
int CreateButton(string name, string text, int x, int y, int buttonWidth, int buttonHeight)
  {
   int button = ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, "RED");
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
// Set button width and height using OBJPROP_XSIZE and OBJPROP_YSIZE
   ObjectSetInteger(0, name, OBJPROP_XSIZE, buttonWidth);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, buttonHeight);
// Set button description using OBJPROP_TEXT
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, button, OBJPROP_STATE, false);
   return button;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Buy()
  {
   lotSizeAutoTrade = CalculateLotSize(riskPercentageAuto);
   OpenBuyOrder(lotSizeAutoTrade, stopLossPips, takeProfitPips, magicAutotrade);
  }

// Button click functions
void BuyButtonClick()
  {
   lotSize = CalculateLotSize(riskPercentage);
   OpenBuyOrder(lotSize, stopLossPips, takeProfitPips, magicManual);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void Sell()
  {
   lotSizeAutoTrade = CalculateLotSize(riskPercentageAuto);
   OpenSellOrder(lotSizeAutoTrade, stopLossPips, takeProfitPips, magicAutotrade);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SellButtonClick()
  {
   lotSize = CalculateLotSize(riskPercentage);
   OpenSellOrder(lotSize, stopLossPips, takeProfitPips,magicManual);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseButtonClick()
  {
// Get the total number of open positions
   int total = OrdersTotal();
// Loop through all open positions and close them
   for(int i = total - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol())
           {
            // Close the position
            OrderClose(OrderTicket(), OrderLots(), Bid, 10, clrNONE);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseHalfButtonClick()
  {
// Get the total number of open positions
   int total = OrdersTotal();
// Loop through all open positions and close half of them
   for(int i = total - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol())
           {
            // Close half of the position
            double lot_size = OrderLots();
            double new_lot_size = lot_size / 2;
            OrderClose(OrderTicket(), new_lot_size, Bid, 10, clrNONE);
           }
        }
     }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void UpdateStoplossButtonClick()
  {
// Get the total number of open positions
   int total = OrdersTotal();
// Loop through all open positions and modify them
   for(int i = total - 1; i >= 0; i--)
     {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
         if(OrderSymbol() == Symbol())
           {
            // Modify the position to breakeven
            double open_price = OrderOpenPrice();
            double stop_loss = OrderStopLoss();
            if(OrderType() == OP_BUY)
              {
               // Modify the stop loss
               if(stop_loss < open_price)
                 {
                  stop_loss = open_price;
                  OrderModify(OrderTicket(), OrderOpenPrice(), stop_loss, OrderTakeProfit(), 0, clrNONE);
                 }
              }
            else
               if(OrderType() == OP_SELL)
                 {
                  // Modify the stop loss
                  if(stop_loss > open_price)
                    {
                     stop_loss = open_price;
                     OrderModify(OrderTicket(), OrderOpenPrice(), stop_loss, OrderTakeProfit(), 0, clrNONE);
                    }
                 }
           }
        }
     }
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
// Function to open a buy order
int OpenBuyOrder(double lotSize, double stopLossPips, double takeProfitPips, int magic)
  {
// Define order parameters
   double entryPrice = Ask;  // Current ask price (assuming you want to buy at the current market price)

// Calculate stop loss and take profit prices
   double stopLossPrice = entryPrice - stopLossPips * Point;
   double takeProfitPrice = entryPrice + takeProfitPips * Point;

// Open a buy order
   int ticket = OrderSend(
                   Symbol(),           // Trading symbol
                   OP_BUY,             // Order type (buy)
                   lotSize,            // Lot size
                   entryPrice,         // Entry price
                   3,                  // Slippage
                   stopLossPrice,      // Stop loss
                   takeProfitPrice,    // Take profit
                   "Buy Order",        // Comment
                   magic,                  // Magic number
                   0,                  // Expiration
                   clrNONE               // Color
                );

   if(ticket > 0)
     {
      Print("Buy order opened successfully. Ticket: ", ticket);
     }
   else
     {
      Print("Error opening buy order. Error code: ", GetLastError());
     }

   return ticket;  // Return the ticket number
  }

// Function to open a sell order
int OpenSellOrder(double lotSize, double stopLossPips, double takeProfitPips, int magic)
  {
// Define order parameters
   double entryPrice = Bid;  // Current bid price (assuming you want to sell at the current market price)

// Calculate stop loss and take profit prices
   double stopLossPrice = entryPrice + stopLossPips * Point;
   double takeProfitPrice = entryPrice - takeProfitPips * Point;

// Open a sell order
   int ticket = OrderSend(
                   Symbol(),           // Trading symbol
                   OP_SELL,            // Order type (sell)
                   lotSize,            // Lot size
                   entryPrice,         // Entry price
                   3,                  // Slippage
                   stopLossPrice,      // Stop loss
                   takeProfitPrice,    // Take profit
                   "Sell Order",       // Comment
                   magic,                  // Magic number
                   0,                  // Expiration
                   clrNONE                // Color
                );

   if(ticket > 0)
     {
      Print("Sell order opened successfully. Ticket: ", ticket);
     }
   else
     {
      Print("Error opening sell order. Error code: ", GetLastError());
     }

   return ticket;  // Return the ticket number
  }

//+------------------------------------------------------------------+
// Function to calculate lot size based on account equity
double CalculateLotSize(double riskPercentage)
  {
// Get account equity
   double accountEquity = AccountFreeMargin();

// Calculate lot size based on risk percentage
   double lotSize = (accountEquity * riskPercentage) / 10000.0; // Assuming 1 lot per 10,000 of account currency

// Round the lot size to 2 decimal places
   lotSize = NormalizeDouble(lotSize, 2);
   //Print(lotSize);
   return 0.3;
  }
//+------------------------------------------------------------------+
bool OpenTradeExist()
  {
   double totlot = 0;
   bool retvalue = false;
   for(int cc = OrdersTotal() - 1; cc >= 0; cc--)
     {
      if(!OrderSelect(cc, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderSymbol()!=Symbol())
         continue;
      if(OrderSymbol() == Symbol() && OrderCloseTime() == 0)
        {
         retvalue = true;
        }
     }

   return(retvalue);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
