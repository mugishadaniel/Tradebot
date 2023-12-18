//+------------------------------------------------------------------+
//|                                                      GlenRoy.mq5 |
//|                                                    Daniel Carter |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Daniel Carter"
#property link "https://www.mql5.com"
#property version "1.00"

// Define the input parameters
input int H1_Period = 60; // H1 period (in minutes)

// Define global variables
double lowestLow;	// Laagste laag in een opwaartse trend
double highestHigh; // Hoogste hoog in een neerwaartse trend
datetime lastCalculationTime = 0;
int recalibrationInterval = 3600; // 1 hour in seconds
int TicksReceivedCount = 0;

bool isUptrend = false;				 // Flag to track if the current trend is upward
bool isDowntrend = false;			 // Flag to track if the current trend is downward
double retracementThreshold = 0.001; // Define your retracement threshold
bool retracementTested = false;		 // Flag to track if retracement has been tested

// Global variables for M5 timeframe
double M5_lowestLow;
double M5_highestHigh;

bool isWPattern = false;
bool isMPattern = false;

double stopLoss = 0.0;
double takeProfit = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	// Calculate the initial lowest low and highest high based on historical data
	lowestLow = iLowest(_Symbol, PERIOD_H1, MODE_LOW, H1_Period, 0);
	highestHigh = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, H1_Period, 0);

	DrawTrendLines();

	EventSetMillisecondTimer(recalibrationInterval * 1000);

	return (INIT_SUCCEEDED);
}

void DrawTrendLines()
{
	// Teken de trendlijn vanaf het laagste punt in een opwaartse trend
	ObjectCreate(0, "Trendline_Up", OBJ_TREND, 0, 0, 0, 0);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_COLOR, clrGreen);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_RAY_RIGHT, true);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_STYLE, STYLE_SOLID);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_WIDTH, 2);
	ObjectSetInteger(0, "Trendline_Up", OBJPROP_TIME, iTime(_Symbol, PERIOD_H1, lowestLow));
	ObjectSetDouble(0, "Trendline_Up", OBJPROP_PRICE, lowestLow);

	// Teken de trendlijn vanaf het hoogste punt in een neerwaartse trend
	ObjectCreate(0, "Trendline_Down", OBJ_TREND, 0, 0, 0, 0);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_COLOR, clrRed);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_RAY_RIGHT, true);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_STYLE, STYLE_SOLID);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_WIDTH, 2);
	ObjectSetInteger(0, "Trendline_Down", OBJPROP_TIME, iTime(_Symbol, PERIOD_H1, highestHigh));
	ObjectSetDouble(0, "Trendline_Down", OBJPROP_PRICE, highestHigh);
}

void OnTimer()
{
	// Recalculate the highest high and lowest low
	int indexLowest = iLowest(_Symbol, PERIOD_H1, MODE_LOW, H1_Period, 0);
	int indexHighest = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, H1_Period, 0);

	lowestLow = iLow(_Symbol, PERIOD_H1, indexLowest);
	highestHigh = iHigh(_Symbol, PERIOD_H1, indexHighest);

	// Update the last calculation time
	lastCalculationTime = TimeCurrent();
}

bool DetectWPattern()
{
	// Define the number of candles to check
	int lookbackCandles = 10; // Adjust as needed

	// Variables to store the first and second lows
	double firstLow = DBL_MAX;	// Initialize to a very high value
	double secondLow = DBL_MAX; // Initialize to a very high value
	datetime firstLowTime = 0;
	datetime secondLowTime = 0;

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

	// Check if the second low is higher than the first low
	if (firstLow < secondLow && firstLowTime < secondLowTime)
	{
		return true;
	}

	return false;
}

bool DetectMPattern()
{
	// Define the number of candles to check
	int lookbackCandles = 10; // Adjust as needed

	// Variables to store the first and second highs
	double firstHigh = -DBL_MAX;  // Initialize to a very low value
	double secondHigh = -DBL_MAX; // Initialize to a very low value
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

	// Check if the second high is lower than the first high
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
	// Bepaal of de markt de trendlijn doorbreekt

	// Update the trend direction flags based on current price
	double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID); // Assuming a buy strategy
	isUptrend = currentPrice > highestHigh;
	isDowntrend = currentPrice < lowestLow;

	// check of het tijd is om te herberekenen
	if (TimeCurrent() - lastCalculationTime >= recalibrationInterval)
	{
		// Recalculate the highest high and lowest low
		int indexLowest = iLowest(_Symbol, PERIOD_H1, MODE_LOW, H1_Period, 0);
		int indexHighest = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, H1_Period, 0);

		lowestLow = iLow(_Symbol, PERIOD_H1, indexLowest);
		highestHigh = iHigh(_Symbol, PERIOD_H1, indexHighest);

		// Update the last calculation time
		lastCalculationTime = TimeCurrent();

		// Update the trendlines
		ObjectSetInteger(0, "Trendline_Up", OBJPROP_TIME, iTime(_Symbol, PERIOD_H1, lowestLow));
		ObjectSetDouble(0, "Trendline_Up", OBJPROP_PRICE, NormalizeDouble(lowestLow, Digits()));

		ObjectSetInteger(0, "Trendline_Down", OBJPROP_TIME, iTime(_Symbol, PERIOD_H1, highestHigh));
		ObjectSetDouble(0, "Trendline_Down", OBJPROP_PRICE, NormalizeDouble(highestHigh, Digits()));
	}

	static datetime lastM5UpdateTime = 0;
	if (TimeCurrent() - lastM5UpdateTime > 300) // Update every 5 minutes
	{
		M5_lowestLow = iLowest(_Symbol, PERIOD_M5, MODE_LOW, H1_Period, 0);
		M5_highestHigh = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, H1_Period, 0);
		lastM5UpdateTime = TimeCurrent();
	}

	// Check for retracement on M5 timeframe
	if (isUptrend && currentPrice < M5_highestHigh && currentPrice > M5_lowestLow)
	{
		// Logic for retracement in an uptrend on M5 timeframe
		if (!retracementTested && currentPrice >= highestHigh - retracementThreshold)
		{
			retracementTested = true;
			Print("Retracement towards the high in an uptrend on M5 detected");
			// Implement your logic for handling the retracement
		}
	}
	else if (isDowntrend && currentPrice > M5_lowestLow && currentPrice < M5_highestHigh)
	{
		// Logic for retracement in a downtrend on M5 timeframe
		if (!retracementTested && currentPrice <= lowestLow + retracementThreshold)
		{
			retracementTested = true;
			Print("Retracement towards the low in a downtrend on M5 detected");
			// Implement your logic for handling the retracement
		}
	}

	// Huidige hoogte (hoogste punt) in een opwaartse trend
	double currentHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);

	// Huidige laagte (laagste punt) in een neerwaartse trend
	double currentLow = iLow(_Symbol, PERIOD_CURRENT, 0);

	Print("currentHigh: ", currentHigh);
	Print("highestHigh: ", highestHigh);
	Print("currentLow: ", currentLow);
	Print("lowestLow: ", lowestLow + " ////");

	// Controleer of de markt de trendlijn doorbreekt in een opwaartse trend
	if (currentHigh > highestHigh)
	{
		Print("Markt doorbreekt trendlijn in een opwaartse trend");
		// Voer hier je handelslogica uit
	}

	// Controleer of de markt de trendlijn doorbreekt in een neerwaartse trend
	if (currentLow < lowestLow)
	{
		Print("Markt doorbreekt trendlijn in een neerwaartse trend");
		// Voer hier je handelslogica uit
	}

	// Logic to detect 'W' pattern in an uptrend
	if (isUptrend && retracementTested)
	{
		// Implement your logic for detecting a 'W' pattern
		isWPattern = DetectWPattern();
	}

	// Logic to detect 'M' pattern in a downtrend
	if (isDowntrend && retracementTested)
	{
		// Implement your logic for detecting an 'M' pattern
		isMPattern = DetectMPattern();
	}

	// Set Take Profit and Stop Loss for an Uptrend
	if (isUptrend && isWPattern)
	{
		takeProfit = highestHigh;
		stopLoss = M5_lowestLow; // Assuming this is the lowest point of the 'W' pattern

		// Implement your order execution logic here
		// Example: OrderSend(_Symbol, OP_BUY, lotSize, currentPrice, 3, stopLoss, takeProfit, "Buy Order", magicNumber, 0, clrGreen);
	}

	// Set Take Profit and Stop Loss for a Downtrend
	if (isDowntrend && isMPattern)
	{
		takeProfit = lowestLow;
		stopLoss = M5_highestHigh; // Assuming this is the highest point of the 'M' pattern

		// Implement your order execution logic here
		// Example: OrderSend(_Symbol, OP_SELL, lotSize, currentPrice, 3, stopLoss, takeProfit, "Sell Order", magicNumber, 0, clrRed);
	}

	Comment("Ticks received: " + TicksReceivedCount);
}
