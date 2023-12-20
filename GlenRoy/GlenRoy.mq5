//+------------------------------------------------------------------+
//|                                                      GlenRoy.mq5 |
//|                                                    Daniel Carter |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Daniel Carter"
#property link "https://www.mql5.com"
#property version "1.00"

// Include Functions
#include <Trade\Trade.mqh> //Include MQL trade object functions.
CTrade *Trade;			   // Declaire Trade as pointer to CTrade class

// Define the input parameters
input int H1_Period = 60; // H1 period (in minuten)

// Risk Management
input bool RiskCompounding = false;	 // Set to true for compounding risk
input double StartingEquity = 10000; // Starting equity for fixed risk
input double MaxLossPrc = 0.01;		 // Max loss as a percentage of equity (1% in this case)
double CurrentEquityRisk = 0.0;		 // Equity that will be risked per trade
double CurrentEquity = 0.0;			 // Current Equity

// Globale Variabelen
double lowestLow;					// Laagste laag in een opwaartse trend
double highestHigh;					// Hoogste hoog in een neerwaartse trend
input int InpMagicNumber = 2000001; // Magic Number voor de orders

datetime lastCalculationTime = 0;
int recalibrationInterval = 3600; // 1 uur in seconden
int TicksReceivedCount = 0;

bool isUptrend = false;	  // Checken of de huidige trend opwaarts gaat
bool isDowntrend = false; // Checken of de huidige trend neerwaarts gaat

double retracementThreshold = 0.001; // Definieer uw retracement threshold
bool retracementTested = false;		 // Flag to track if retracement has been tested

double M5_lowestLow;   // Laagste laag in een opwaartse trend in M5 Timeframe
double M5_highestHigh; // Hoogste hoog in een neerwaartse trend in de M5 Timeframew

bool isWPattern = false;
bool isMPattern = false;

double stopLoss = 0.0;
double takeProfit = 0.0; // Risk Management

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	Trade = new CTrade();
	Trade.SetExpertMagicNumber(InpMagicNumber);
	// Bereken het initiële laagste laagste en hoogste hoogste punt op basis van historische gegevens
	lowestLow = iLowest(_Symbol, PERIOD_H1, MODE_LOW, H1_Period, 0);
	highestHigh = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, H1_Period, 0);

	DrawTrendLines();

	EventSetMillisecondTimer(recalibrationInterval * 1000); // stelt timer voor herkalibratie

	return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                    Custom Function                               |
//+------------------------------------------------------------------+

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

void DrawTrendLines()
{
	// Teken de trendlijn vanaf het laagste punt in een opwaartse trend
	ObjectCreate(0, "Trendline_Up", OBJ_TREND, 0, 0, 0, 0);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_COLOR, clrGreen);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_RAY_RIGHT, true);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_STYLE, STYLE_SOLID);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_WIDTH, 2);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_TIME, iTime(_Symbol, PERIOD_H1, (int)lowestLow));
	ObjectSetDouble(0, "Trendline_Up", OBJPROP_PRICE, lowestLow);

	// Teken de trendlijn vanaf het hoogste punt in een neerwaartse trend
	ObjectCreate(0, "Trendline_Down", OBJ_TREND, 0, 0, 0, 0);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_COLOR, clrRed);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_RAY_RIGHT, true);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_STYLE, STYLE_SOLID);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_WIDTH, 2);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_TIME, iTime(_Symbol, PERIOD_H1, (int)highestHigh));
	ObjectSetDouble(0, "Trendline_Down", OBJPROP_PRICE, highestHigh);
}

void OnTimer()
{
	// Herrekent periodiek de hoogste en laagste waarden elke uur
	int indexLowest = iLowest(_Symbol, PERIOD_H1, MODE_LOW, H1_Period, 0);
	int indexHighest = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, H1_Period, 0);

	lowestLow = iLow(_Symbol, PERIOD_H1, indexLowest);
	highestHigh = iHigh(_Symbol, PERIOD_H1, indexHighest);

	// Update de laatste berekeningstijd
	lastCalculationTime = TimeCurrent();
}

bool DetectWPattern()
{
	Print("Detecting W Pattern...");
	// Definieer het aantal candles dat moet worden gecontroleerd
	int lookbackCandles = 10;

	// Variabelen om de eerste en tweede dieptepunten op te slaan
	double firstLow = DBL_MAX;	// Initialiseer op een zeer hoge double waarde
	double secondLow = DBL_MAX; // Initialiseer op een zeer hoge double waarde
	datetime firstLowTime = 0;
	datetime secondLowTime = 0;

	// Loop door de candles en zoek naar de eerste en tweede dieptepunten
	for (int i = 0; i < lookbackCandles; i++)
	{
		double currentLow = iLow(_Symbol, PERIOD_M5, i);
		if (currentLow < firstLow)
		{
			secondLow = firstLow;
			secondLowTime = firstLowTime;

			firstLow = currentLow;
			firstLowTime = iTime(_Symbol, PERIOD_M5, i);
		}
		else if (currentLow < secondLow && iTime(_Symbol, PERIOD_M5, i) > firstLowTime)
		{
			secondLow = currentLow;
			secondLowTime = iTime(_Symbol, PERIOD_M5, i);
		}
	}

	// Check of het tweede dieptepunt hoger is dan het eerste dieptepunt
	if (firstLow < secondLow && firstLowTime < secondLowTime)
	{
		return true;
	}

	return false;
}

bool DetectMPattern()
{
	Print("Detecting M Pattern...");
	// Definieer het aantal candles dat moet worden gecontroleerd
	int lookbackCandles = 10;

	// Variabelen om de eerste en tweede hoogtepunten op te slaan
	double firstHigh = -DBL_MAX;  // Initialiseer op een zeer hoge double waarde
	double secondHigh = -DBL_MAX; // Initialiseer op een zeer hoge double waarde
	datetime firstHighTime = 0;
	datetime secondHighTime = 0;

	for (int i = 0; i < lookbackCandles; i++)
	{
		double currentHigh = iHigh(_Symbol, PERIOD_M5, i);
		if (currentHigh > firstHigh)
		{
			secondHigh = firstHigh;
			secondHighTime = firstHighTime;

			firstHigh = currentHigh;
			firstHighTime = iTime(_Symbol, PERIOD_M5, i);
		}
		else if (currentHigh > secondHigh && iTime(_Symbol, PERIOD_M5, i) > firstHighTime)
		{
			secondHigh = currentHigh;
			secondHighTime = iTime(_Symbol, PERIOD_M5, i);
		}
	}

	// Check of de tweede hoogte hoger is dan de eerste hoogte
	if (firstHigh > secondHigh && firstHighTime < secondHighTime)
	{
		return true;
	}

	return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
	TicksReceivedCount++;

	// Update de trend directie op basis van de huidige prijs
	double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Huidige biedprijs
	isUptrend = currentPrice > highestHigh;
	isDowntrend = currentPrice < lowestLow;

	// check of het tijd is om te herberekenen
	if (TimeCurrent() - lastCalculationTime >= recalibrationInterval)
	{
		// Herberekent de hoogste en laagste waarden
		int indexLowest = iLowest(_Symbol, PERIOD_H1, MODE_LOW, H1_Period, 0);
		int indexHighest = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, H1_Period, 0);

		lowestLow = iLow(_Symbol, PERIOD_H1, indexLowest);
		highestHigh = iHigh(_Symbol, PERIOD_H1, indexHighest);

		// Update de laatste berekeningstijd in de huideige tijd
		lastCalculationTime = TimeCurrent();

		// Update de trendlijnen
		ObjectSetInteger(0, "Trendline_Up", OBJPROP_TIME, iTime(_Symbol, PERIOD_H1, (int)lowestLow));
		ObjectSetDouble(0, "Trendline_Up", OBJPROP_PRICE, NormalizeDouble(lowestLow, Digits()));

		ObjectSetInteger(0, "Trendline_Down", OBJPROP_TIME, iTime(_Symbol, PERIOD_H1, (int)highestHigh));
		ObjectSetDouble(0, "Trendline_Down", OBJPROP_PRICE, NormalizeDouble(highestHigh, Digits()));
	}

	static datetime lastM5UpdateTime = 0;
	if (TimeCurrent() - lastM5UpdateTime > 300) // Update elke 5 minuten
	{
		M5_lowestLow = iLowest(_Symbol, PERIOD_M5, MODE_LOW, H1_Period, 0);
		M5_highestHigh = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, H1_Period, 0);
		lastM5UpdateTime = TimeCurrent();
	}

	// Check voor een retracement in een opwaartse trend op M5 Timeframe
	if (isUptrend && currentPrice < M5_highestHigh && currentPrice > M5_lowestLow)
	{
		// Logica voor retracement in een opwaartse trend op M5 Timeframe
		if (!retracementTested && currentPrice >= highestHigh - retracementThreshold)
		{
			retracementTested = true;
			Print("Retracement towards the high in an uptrend on M5 detected");
		}
	}
	else if (isDowntrend && currentPrice > M5_lowestLow && currentPrice < M5_highestHigh)
	{
		// Logica voor retracement in een neerwaartse trend op M5 Timeframe
		if (!retracementTested && currentPrice <= lowestLow + retracementThreshold)
		{
			retracementTested = true;
			Print("Retracement towards the low in a downtrend on M5 detected");
		}
	}

	// Huidige hoogte (hoogste punt) in een opwaartse trend
	double currentHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);

	// Huidige laagte (laagste punt) in een neerwaartse trend
	double currentLow = iLow(_Symbol, PERIOD_CURRENT, 0);

	Print("currentHigh: ", currentHigh);
	Print("highestHigh: ", highestHigh);
	Print("currentLow: ", currentLow);
	Print("lowestLow: ", DoubleToString(lowestLow, 5) + " ////");

	// Controleer of de markt de trendlijn doorbreekt in een opwaartse trend
	if (currentHigh > highestHigh)
	{
		Print("Markt doorbreekt trendlijn in een opwaartse trend");
	}

	// Controleer of de markt de trendlijn doorbreekt in een neerwaartse trend
	if (currentLow < lowestLow)
	{
		Print("Markt doorbreekt trendlijn in een neerwaartse trend");
	}

	if (isUptrend && retracementTested)
	{
		isWPattern = DetectWPattern();
	}

	if (isDowntrend && retracementTested)
	{
		isMPattern = DetectMPattern();
	}

	// Zet Take Profit en Stop Loss voor een opwaartse trend
	if (isUptrend && isWPattern)
	{
		takeProfit = highestHigh;
		stopLoss = M5_lowestLow;
		Print("Buy Trade!//////////////////////////////////////////////////////////////////////////////////////");
		double lotSize = OptimalLotSize(_Symbol, currentPrice, stopLoss);
		// MQL5 trade request structure
		MqlTradeRequest request;	 // We maken een MqlTradeRequest object aan
		ZeroMemory(request);		 // We zetten alle waarden op 0
		MqlTradeResult result = {0}; // hier slaan we het resultaat van de order in op
		// We vullen de MqlTradeRequest object met de juiste waarden
		request.action = TRADE_ACTION_DEAL;
		request.symbol = _Symbol;
		request.volume = lotSize;
		request.type = ORDER_TYPE_BUY;
		request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
		request.sl = stopLoss;
		request.tp = takeProfit;
		request.deviation = 3;
		request.magic = InpMagicNumber;
		request.comment = "Buy Order";

		bool result_flag = OrderSend(request, result);

		if (!result_flag)
			Print("Order Send failed: ", GetLastError());
	}

	// Zet Take Profit en Stop Loss voor een neerwaartse trend
	if (isDowntrend && isMPattern)
	{
		takeProfit = lowestLow;
		stopLoss = M5_highestHigh;
		Print("Sell Trade!//////////////////////////////////////////////////////////////////////////////////////");

		// Calculate the optimal lot size
		double lotSize = OptimalLotSize(_Symbol, currentPrice, stopLoss);

		// MQL5 trade request structure
		MqlTradeRequest request;
		ZeroMemory(request);
		MqlTradeResult result = {0};

		request.action = TRADE_ACTION_DEAL;
		request.symbol = _Symbol;
		request.volume = lotSize;
		request.type = ORDER_TYPE_SELL;						   // Order type for a sell order
		request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Use bid price for sell
		request.sl = stopLoss;
		request.tp = takeProfit;
		request.deviation = 3;
		request.magic = InpMagicNumber;
		request.comment = "Sell Order";

		// Send the order
		bool result_flag = OrderSend(request, result);

		// Check for errors
		if (!result_flag)
			Print("Order Send failed: ", GetLastError());
	}

	Comment("Ticks received: " + DoubleToString(TicksReceivedCount, 0));
}
