//+------------------------------------------------------------------+
//|                                                      GlenRoy.mq5 |
//|                                                    Daniel Carter |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Daniel Carter"
#property link "https://www.mql5.com"
#property version "1.00"

// Define the input parameters
input int H1_Period = 60; // H1 period (in minuten)

// Globale Variabelen
double lowestLow;	// Laagste laag in een opwaartse trend
double highestHigh; // Hoogste hoog in een neerwaartse trend

datetime lastCalculationTime = 0;
int recalibrationInterval = 3600; // 1 uur in seconden
int TicksReceivedCount = 0;

bool isUptrend = false;				 // Checken of de huidige trend opwaarts gaat
bool isDowntrend = false;			 // Checken of de huidige trend neerwaarts gaat

double retracementThreshold = 0.001; // Definieer uw retracement threshold
bool retracementTested = false;		 // Flag to track if retracement has been tested

double M5_lowestLow; // Laagste laag in een opwaartse trend in M5 Timeframe
double M5_highestHigh; // Hoogste hoog in een neerwaartse trend in de M5 Timeframew

bool isWPattern = false;
bool isMPattern = false;

double stopLoss = 0.0;
double takeProfit = 0.0;  // Risk Management

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	// Bereken het initiële laagste laagste en hoogste hoogste punt op basis van historische gegevens
	lowestLow = iLowest(_Symbol, PERIOD_H1, MODE_LOW, H1_Period, 0);
	highestHigh = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, H1_Period, 0);

	DrawTrendLines();

	EventSetMillisecondTimer(recalibrationInterval * 1000); //stelt timer voor herkalibratie

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
	Print("lowestLow: ", DoubleToString(lowestLow) + " ////");

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

		// Implement your order execution logic here
		// Example: OrderSend(_Symbol, OP_BUY, lotSize, currentPrice, 3, stopLoss, takeProfit, "Buy Order", magicNumber, 0, clrGreen);
	}

	// Zet Take Profit en Stop Loss voor een neerwaartse trend
	if (isDowntrend && isMPattern)
	{
		takeProfit = lowestLow;
		stopLoss = M5_highestHigh;

		// Implement your order execution logic here
		// Example: OrderSend(_Symbol, OP_SELL, lotSize, currentPrice, 3, stopLoss, takeProfit, "Sell Order", magicNumber, 0, clrRed);
	}

	Comment("Ticks received: " + DoubleToString(TicksReceivedCount));
}
