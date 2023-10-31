//+------------------------------------------------------------------+
//|                                                     TradeBot.mq5 |
//|                                                    Daniel Carter |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Daniel Carter"
#property link "https://www.mql5.com"
#property version "1.00"

// Include Functions
#include <Trade\Trade.mqh> //Include MQL trade object functions.
CTrade *Trade;			   // Declaire Trade as pointer to CTrade class

// Setup Variables
input int InpMagicNumber = 2000001;						// Unique identifier for this expert advisor
input string InpTradeComment = __FILE__;				// Optional comment for trades
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; // Applied price for indicators

// Global Variables
string indicatorMetrics = "";
int TicksReceivedCount = 0;	 // Counts the number of ticks from oninit function
int TicksProcessedCount = 0; // Counts the number of ticks processed from oninit function based off candle opens only
static datetime TimeLastTickProcessed;

// Store Position Ticket Number
ulong TicketNumber = 0;

// Risk Metrics
input bool TslCheck = true;			// Use Trailing Stop Loss?
input bool RiskCompounding = false; // Use Compounded Risk Method?
double StartingEquity = 0.0;		// Starting Equity
double CurrentEquityRisk = 0.0;		// Equity that will be risked per trade
double CurrentEquity = 0.0;			// Current Equity
input double MaxLossPrc = 0.02;		// Percent Risk Per Trade
input double AtrProfitMulti = 2.0;	// ATR Profit Multiple
input double AtrLossMulti = 1.0;	// ATR Loss Multiple

// ATR Handle and Variables
int HandleAtr;
int AtrPeriod = 14;

// Macd variables and holder
int HandleMacd;
int MacdFast = 12;
int MacdSlow = 26;
int MacdSignal = 9;

// EMA Handle and Variables
int HandleEma;
int EmaPeriod = 100;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	//---
	// Declare magic number for all trades
	Trade = new CTrade();
	Trade.SetExpertMagicNumber(InpMagicNumber);
	

	// Store starting equity onInit
	StartingEquity = AccountInfoDouble(ACCOUNT_EQUITY);

	// Set up handle for handle for ATR indicator on the init
	HandleAtr = iATR(Symbol(), Period(), AtrPeriod);
	Print("Handle for ATR/", Symbol(), "/", EnumToString(Period()), "succesfully created");

	// Set up handle for macd indicator on the init
	HandleMacd = iMACD(Symbol(), Period(), MacdFast, MacdSlow, MacdSignal, InpAppliedPrice);
	Print("Handle for Macd/", Symbol(), " / ", EnumToString(Period()), "successfully created");

	// Set up handle for EMA indicator on the init
	HandleEma = iMA(Symbol(), Period(), EmaPeriod, 0, MODE_EMA, InpAppliedPrice);
	Print("Handle for EMA/", Symbol(), " / ", EnumToString(Period()), "successfully created");
	//---
	return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
	//---

	// Remove indicator handle from Metatrader Cache
	IndicatorRelease(HandleAtr);
	IndicatorRelease(HandleMacd);
	IndicatorRelease(HandleEma);
	Print("Handle released");
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
	//---
	// Declare Variables.
	TicksReceivedCount++; // Counts the number of ticks received

	bool IsNewCandle = false;

	if (TimeLastTickProcessed != iTime(Symbol(), Period(), 0))
	{
		IsNewCandle = true;
		TimeLastTickProcessed = iTime(Symbol(), Period(), 0);
	}

	if (IsNewCandle == true)
	{
		TicksProcessedCount++; // counts the number of ticks processed

		// Check if position is still open. If not open, return 0.
		if (!PositionSelectByTicket(TicketNumber))
			TicketNumber = 0;

		indicatorMetrics = ""; // Initiate String for indicatorMetrics Variable. This will reset variable each time OnTick function runs.

		StringConcatenate(indicatorMetrics, Symbol(), " | Last Processed: ", TimeLastTickProcessed, " | Open Ticket: ", TicketNumber);

		// Money management - ATR
		double CurrentAtr = GetATRValue(); // Gets ATR value double using custom function - convert double to string as per symbol digits
		StringConcatenate(indicatorMetrics, indicatorMetrics, " | ATR: ", CurrentAtr);

		//---Strategy Trigger MACD---///
		string OpenSignalMacd = GetMacdOpenSignal(); // Variable will return Long or Short Bias only on a trigger/cross event
		// Concatenate indicator values to output comment for user
		StringConcatenate(indicatorMetrics, indicatorMetrics, " | MACD Bias: ", OpenSignalMacd);

		//---Strategy Filter EMA---/
		string OpenSignalEma = GetEmaOpenSignal(); // variable return long or short bias if close is above or below EMA.
		StringConcatenate(indicatorMetrics, indicatorMetrics, " | EMA Bias: ", OpenSignalEma);

		//---Enter Trades---//
		if (OpenSignalMacd == "Long" && OpenSignalEma == "Long")
			TicketNumber = ProcessTradeOpen(ORDER_TYPE_BUY, CurrentAtr);
		else if (OpenSignalMacd == "Short" && OpenSignalEma == "Short")
			TicketNumber = ProcessTradeOpen(ORDER_TYPE_SELL, CurrentAtr);

		// Adjust Open Positions - Trailing Stop Loss
		if (TslCheck == true)
			AdjustTsl(TicketNumber, CurrentAtr, AtrLossMulti);
	}

	Comment("\n\rExpert: ", InpMagicNumber, "\n\r",
			"MT5 Server Time: ", TimeCurrent(), "\n\r",
			"Ticks Received: ", TicksReceivedCount, "\n\r",
			"Ticks Processed: ", TicksProcessedCount, "\n\r", "\n\r",
			"Symbols Traded: \n\r",
			indicatorMetrics);
}
//+------------------------------------------------------------------+
//|                    Custom Function                               |
//+------------------------------------------------------------------+

// Custom function to get ATR value
double GetATRValue()
{
	// Set symbol string and indicator buffer
	string CurrentSymbol = Symbol();
	const int StartCandle = 0;
	const int RequiredCandles = 3; // How many candles are required to be stored in Expert

	// Indicator Variables and Buffers
	const int IndexAtr = 0; // ATR Value
	double BufferAtr[];		// [prior, current confirmed, not confirmed]

	// populate buffers for ATR value; check errors
	bool FillAtr = CopyBuffer(HandleAtr, IndexAtr, StartCandle, RequiredCandles, BufferAtr);
	if (FillAtr == false)
		return (0);

	// Find ATR Value for Candle '1' Only
	double CurrentATR = NormalizeDouble(BufferAtr[1], 5);

	// return ATR value
	return (CurrentATR);
}

// to get MACD signals

string GetMacdOpenSignal()
{
	// Set symbol string and indicator buffers
	string CurrentSymbol = Symbol();
	const int StartCandle = 0;
	const int RequiredCandles = 3; // How many candles are required to be stored in Expert
	// Indicator Variables and Buffers
	const int IndexMacd = 0;   // Macd Line.
	const int IndexSignal = 1; // Signal Line
	double BufferMacd[];	   // [prior, current confirmed, not confirmed]
	double BufferSignal[];	   // [prior, current confirmed, not confirmed]

	// Define Macd and Signal lines, from not confirmed candle 0, for 3 candles, and store results
	bool fillMacd = CopyBuffer(HandleMacd, IndexMacd, StartCandle, RequiredCandles, BufferMacd);
	bool fillSignal = CopyBuffer(HandleMacd, IndexSignal, StartCandle, RequiredCandles, BufferSignal);
	if (fillMacd == false || fillSignal == false)
		return "Buffer not full"; // If buffers are not completely filled, return to end onTick

	// Find required Macd signal lines and normalize to 10 places to prevent rounding errors in crossovers
	double currentMacd = NormalizeDouble(BufferMacd[1], 10);
	double currentSignal = NormalizeDouble(BufferSignal[1], 10);
	double priorMacd = NormalizeDouble(BufferMacd[0], 10);
	double priorSignal = NormalizeDouble(BufferSignal[0], 10);

	// Submit Macd Long and Short Trades
	if (priorMacd <= priorSignal && currentMacd > currentSignal && currentMacd < 0 && currentSignal < 0)
		return "Long";
	else if (priorMacd >= priorSignal && currentMacd < currentSignal && currentMacd > 0 && currentSignal > 0)
		return "Short";
	else
		return "No Trade";
}

//---
// Processes open trades for buy and sell
ulong ProcessTradeOpen(ENUM_ORDER_TYPE orderType, double CurrentAtr)
{
	// Set symbol string and variables
	string CurrentSymbol = Symbol();
	double price = 0;
	double stopLossPrice = 0;
	double takeProfitPrice = 0;

	// Get price,sl,tp for open and close orders
	if (orderType == ORDER_TYPE_BUY)
	{
		price = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
		stopLossPrice = NormalizeDouble(price - CurrentAtr * AtrLossMulti, Digits());
		takeProfitPrice = NormalizeDouble(price + CurrentAtr * AtrProfitMulti, Digits());
	}
	else if (orderType == ORDER_TYPE_SELL)
	{
		price = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
		stopLossPrice = NormalizeDouble(price + CurrentAtr * AtrLossMulti, Digits());
		takeProfitPrice = NormalizeDouble(price - CurrentAtr * AtrProfitMulti, Digits());
	}

	// get lot size
	double lotSize = OptimalLotSize(CurrentSymbol, price, stopLossPrice);

	// execute trades
	Trade.PositionClose(CurrentSymbol);
	Trade.PositionOpen(CurrentSymbol, orderType, lotSize, price, stopLossPrice, takeProfitPrice, InpTradeComment);

	// Get Position Ticket Number
	ulong Ticket = PositionGetTicket(0);

	// Add in any error handling
	Print("Trade Processed For ", CurrentSymbol, " OrderType ", orderType, " Lot Size ", lotSize, " Ticket ", Ticket);

	// Return tje ticket number to onInit
	return (Ticket);
}

// Finds the optimal lot size for the trade - Orghard Forex mod by Dillon Grech
// https://www.youtube.com/watch?v=Zft8X3htrcc&t=724s
double OptimalLotSize(string CurrentSymbol, double EntryPrice, double StopLoss)
{
	// Set symbol string and calculate point value
	double TickSize = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_SIZE);
	double TickValue = SymbolInfoDouble(CurrentSymbol, SYMBOL_TRADE_TICK_VALUE);
	if (SymbolInfoInteger(CurrentSymbol, SYMBOL_DIGITS) <= 3)
		TickValue = TickValue / 100;
	double PointAmount = SymbolInfoDouble(CurrentSymbol, SYMBOL_POINT);
	double TicksPerPoint = TickSize / PointAmount;
	double PointValue = TickValue / TicksPerPoint;

	// calculate risk based off entry and stop loss level by pips
	double RiskPoints = MathAbs((EntryPrice - StopLoss) / TickSize);

	// Set risk model - fixed or compounding
	if (RiskCompounding == true)
	{
		CurrentEquityRisk = AccountInfoDouble(ACCOUNT_EQUITY);
		CurrentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
	}
	else
	{
		CurrentEquityRisk = StartingEquity;
		CurrentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
	}

	// calculate total risk amount in dollars
	double RiskAmount = CurrentEquityRisk * MaxLossPrc;

		// Calculate lot size
	double RiskLots = NormalizeDouble(RiskAmount / (RiskPoints * PointValue), 2);

	// Print values in Journal to check if operating correctly
	PrintFormat("TickSize=%f,TickValue=%f,PointAmount=%f,TicksPerPoint=%f,PointValue=%f,",
				TickSize, TickValue, PointAmount, TicksPerPoint, PointValue);
	PrintFormat("EntryPrice=%f,StopLoss=%f,RiskPoints=%f,RiskAmount=%f,RiskLots=%f,",
				EntryPrice, StopLoss, RiskPoints, RiskAmount, RiskLots);

	// Return optimal lot size
	return RiskLots;
}

// Custom function that returns long and short signals based off EMA and close price
string GetEmaOpenSignal()
{
	// Set symbol string and indicator buffers
	string CurrentSymbol = Symbol();
	const int StartCandle = 0;
	const int RequiredCandles = 2; // How many candles are required to be stored in Expert
	// Indicator Variables and Buffers
	const int IndexEma = 0; // Macd Line.
	double BufferEma[];		// [current confirmed, not confirmed]
	// Define Macd and Signal lines, from not confirmed candle 0, for 2 candles, and store results
	bool fillEma = CopyBuffer(HandleEma, IndexEma, StartCandle, RequiredCandles, BufferEma);
	if (fillEma == false)
		return "Buffer not full Ema"; // If buffers are not completely filled, return to end onTick

	// Gets the current confirmed EMA value
	double currentEma = NormalizeDouble(BufferEma[1], 10);
	double currentClose = NormalizeDouble(iClose(Symbol(), Period(), 0), 10);

	// Submit Ema Long and Short Trades
	if (currentClose > currentEma)
		return "Long";
	else if (currentClose < currentEma)
		return "Short";
	else
		return "No Trade";
}

// Adjust Trailing Stop Loss based off ATR
void AdjustTsl(ulong Ticket, double CurrentAtr, double AtrMulti)
{
	// Set symbol string and variables
	string CurrentSymbol = Symbol();
	double Price = 0.0;
	double OptimalStopLoss = 0.0;

	// Check correct ticket number is selected for further position data to be stored. Return if error.
	if (!PositionSelectByTicket(Ticket))
		return;

	// Store position data variables
	ulong PositionDirection = PositionGetInteger(POSITION_TYPE);
	double CurrentStopLoss = PositionGetDouble(POSITION_SL);
	double CurrentTakeProfit = PositionGetDouble(POSITION_TP);

	// Check if position direction is long
	if (PositionDirection == POSITION_TYPE_BUY)
	{
		// Get optimal stop loss value
		Price = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
		OptimalStopLoss = NormalizeDouble(Price - CurrentAtr * AtrMulti, Digits());

		// Check if optimal stop loss is greater than current stop loss. If TRUE, adjust stop loss
		if (OptimalStopLoss > CurrentStopLoss)
		{
			Trade.PositionModify(Ticket, OptimalStopLoss, CurrentTakeProfit);
			Print("Ticket ", Ticket, " for symbol ", CurrentSymbol, " stop loss adjusted to ", OptimalStopLoss);
		}

		// Return once complete
		return;
	}

	// Check if position direction is short
	if (PositionDirection == POSITION_TYPE_SELL)
	{
		// Get optimal stop loss value
		Price = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
		OptimalStopLoss = NormalizeDouble(Price + CurrentAtr * AtrMulti, Digits());

		// Check if optimal stop loss is less than current stop loss. If TRUE, adjust stop loss
		if (OptimalStopLoss < CurrentStopLoss)
		{
			Trade.PositionModify(Ticket, OptimalStopLoss, CurrentTakeProfit);
			Print("Ticket ", Ticket, " for symbol ", CurrentSymbol, " stop loss adjusted to ", OptimalStopLoss);
		}

		// Return once complete
		return;
	}
}
