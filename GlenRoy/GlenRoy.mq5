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
double lowestLow;  // Laagste laag in een opwaartse trend
double highestHigh; // Hoogste hoog in een neerwaartse trend
datetime lastCalculationTime = 0;
int recalibrationInterval = 3600;  // 1 hour in seconds

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

   
   return(INIT_SUCCEEDED);
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

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Bepaal of de markt de trendlijn doorbreekt
   
   	//check of het tijd is om te herberekenen
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
   // Huidige hoogte (hoogste punt) in een opwaartse trend
   double currentHigh = iHigh(_Symbol, PERIOD_CURRENT, 0);
   
   // Huidige laagte (laagste punt) in een neerwaartse trend
   double currentLow = iLow(_Symbol, PERIOD_CURRENT, 0);


   Print("currentHigh: ", currentHigh);
   Print("highestHigh: ", highestHigh);
   Print("currentLow: ", currentLow);
   Print("lowestLow: ", lowestLow);

   // Controleer of de markt de trendlijn doorbreekt in een opwaartse trend
   if(currentHigh > highestHigh)
   {
      Print("Markt doorbreekt trendlijn in een opwaartse trend");
      // Voer hier je handelslogica uit
   }
   
   // Controleer of de markt de trendlijn doorbreekt in een neerwaartse trend
   if(currentLow < lowestLow)
   {
      Print("Markt doorbreekt trendlijn in een neerwaartse trend");
      // Voer hier je handelslogica uit
   }
}

