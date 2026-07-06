//+------------------------------------------------------------------+
//|                                                       DTDB4C.mq5 |
//|                                                    Daniel Carter |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version "3.00"

// Inputs
input int ZZ_Depth = 8;
input int ZZ_Deviation = 3;
input int ZZ_Backstep = 10;
input ulong EA_MagicNumber = 123456; // Unieke ID voor deze bot
#include <Trade\Trade.mqh>
CTrade trade;
int zigzagHandle;
datetime lastMessageTime = 0; // Voorkomt dat we elke tick de log volprinten

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	zigzagHandle = iCustom(_Symbol, _Period, "Examples\\ZigZag", ZZ_Depth, ZZ_Deviation, ZZ_Backstep);
	if (zigzagHandle == INVALID_HANDLE)
	{
		Print("Fout: Kon ZigZag indicator niet laden.");
		return (INIT_FAILED);
	}

	Print("Trade Bot Succesvol Gestart. Wachten op patronen...");
	return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
	IndicatorRelease(zigzagHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
	// Zorg dat we dit maximaal één keer per minuut/candle controleren of printen
	datetime currentTime = iTime(_Symbol, _Period, 0);
	if (HasOpenPositions())
		return;
	double zzValues[];
	ArraySetAsSeries(zzValues, true);
	if (CopyBuffer(zigzagHandle, 0, 0, 100, zzValues) < 0)
		return;

	int zzBars[4];
	int found = 0;

	for (int i = 0; i < 100; i++)
	{
		if (zzValues[i] > 0)
		{
			zzBars[found] = i;
			found++;
			if (found == 4)
				break;
		}
	}

	if (found < 4)
		return;

	// Posities van de candles
	int bar_Leg2 = zzBars[0];
	int bar_Neckline = zzBars[1];
	int bar_Leg1 = zzBars[2];

	// 1. Check: Minstens 5 kaarsen tussen de 1e leg (top/bodem) en de neckline
	if ((bar_Leg1 - bar_Neckline) < 5)
	{
		return; // Te dicht op elkaar, skip dit patroon
	}

	// 2. Optioneel (aanbevolen): Check ook minstens 5 kaarsen tussen de neckline en leg 2
	if ((bar_Neckline - bar_Leg2) < 5)
	{
		return; // Te dicht op elkaar, skip dit patroon
	}

	double price_Leg2 = zzValues[bar_Leg2];
	double price_Neckline = zzValues[bar_Neckline];
	double price_Leg1 = zzValues[bar_Leg1];

	// --- LOGICA VOOR DOUBLE TOP (M-PATROON) ---
	if (price_Leg1 > price_Neckline && price_Leg2 > price_Neckline)
	{
		double top1_High = iHigh(_Symbol, _Period, bar_Leg1);
		double top2_High = iHigh(_Symbol, _Period, bar_Leg2);
		bool patternValid = true;

		// We starten nu bij de ALLEREERSTE kaars (bar_Leg1) en lopen naar het heden (0)
		for (int b = bar_Leg1; b >= 0; b--)
		{
			// Sla de exacte kaars van Top 1 zelf over, we kijken naar alles wat daarna gebeurt
			if (b == bar_Leg1)
				continue;

			// VOORWAARDE: Geen enkele body sluiting mag boven de absolute wick-high van Top 1 uitkomen
			if (iClose(_Symbol, _Period, b) > top1_High)
			{
				patternValid = false;
				break; // Direct afkeuren en loop stoppen
			}
		}

		if (patternValid)
		{

			// We controleren de laatste 4 gesloten candles:
			// b=4 (Candle 1), b=3 (Candle 2), b=2 (Candle 3), b=1 (Candle 4)
			double c1_Open = iOpen(_Symbol, _Period, 4);
			double c1_Close = iClose(_Symbol, _Period, 4);

			double c2_Open = iOpen(_Symbol, _Period, 3);
			double c2_Close = iClose(_Symbol, _Period, 3);

			double c3_Open = iOpen(_Symbol, _Period, 2);
			double c3_Close = iClose(_Symbol, _Period, 2);

			double c4_Open = iOpen(_Symbol, _Period, 1);
			double c4_Close = iClose(_Symbol, _Period, 1);

			// 1. Controleer de volgorde: Bullish -> Bearish -> Bullish -> Bearish
			bool sequenceValid = (c1_Close > c1_Open) && // Candle 1: Bullish
										(c2_Close < c2_Open) && // Candle 2: Bearish
										(c3_Close > c3_Open) && // Candle 3: Bullish
										(c4_Close < c4_Open);	// Candle 4: Bearish

			if (sequenceValid)
			{
				// Candle 1 is de referentiecandle. De body-high is de Close.
				double ref_BodyHigh = c1_Close;

				// 2. Regel: Volgende 3 candles mogen met hun body niet hoger sluiten dan ref_BodyHigh
				if (c2_Close <= ref_BodyHigh && c3_Close <= ref_BodyHigh && c4_Close <= ref_BodyHigh)
				{
					if (lastMessageTime != currentTime)
					{
						Print(">>> [ENTRY TRIGGER][M-PATROON] 4-Candle Theorie bevestigd bij Top 2! Open Sell Trade. Target: ", price_Neckline);
						Comment("4-CANDLE THEORY CONFIRMED: SELL!");

						// 1. Pak de hoogste wick van EXACT de 4e candle (index 1)
						double candle4_High = iHigh(_Symbol, _Period, 1);

						// 2. Voeg 1 PIP buffer toe (1 pip = 10 punten op een 5-digit broker)
						double sl_Buffer = 10 * _Point;
						double sell_StopLoss = candle4_High + sl_Buffer;

						// 3. Open de Sell trade
						trade.SetExpertMagicNumber(EA_MagicNumber);
						trade.Sell(0.10, _Symbol, 0, sell_StopLoss, price_Neckline, "DTDB4C Sell");

						lastMessageTime = currentTime;
					}
				}
			}
		}
	}

	// --- LOGICA VOOR DOUBLE BOTTOM (W-PATROON) ---
	if (price_Leg1 < price_Neckline && price_Leg2 < price_Neckline)
	{
		double bottom1_Low = iLow(_Symbol, _Period, bar_Leg1);
		double bottom2_Low = iLow(_Symbol, _Period, bar_Leg2);
		bool patternValid = true;

		// We starten bij de ALLEREERSTE kaars (bar_Leg1) en lopen naar het heden (0)
		for (int b = bar_Leg1; b >= 0; b--)
		{
			// Sla de exacte kaars van Bottom 1 zelf over
			if (b == bar_Leg1)
				continue;

			// VOORWAARDE: Geen enkele body sluiting mag ONDER de absolute wick-low van Bottom 1 uitkomen
			if (iClose(_Symbol, _Period, b) < bottom1_Low)
			{
				patternValid = false;
				break; // Direct afkeuren en loop stoppen
			}
		}
		if (patternValid)
		{

			// We controleren de laatste 4 gesloten candles vanaf de tweede bodem:
			// b=4 (Candle 1), b=3 (Candle 2), b=2 (Candle 3), b=1 (Candle 4)

			double c1_Open = iOpen(_Symbol, _Period, 4);
			double c1_Close = iClose(_Symbol, _Period, 4);

			double c2_Open = iOpen(_Symbol, _Period, 3);
			double c2_Close = iClose(_Symbol, _Period, 3);

			double c3_Open = iOpen(_Symbol, _Period, 2);
			double c3_Close = iClose(_Symbol, _Period, 2);

			double c4_Open = iOpen(_Symbol, _Period, 1);
			double c4_Close = iClose(_Symbol, _Period, 1);

			// 1. Controleer de volgorde: Bearish -> Bullish -> Bearish -> Bullish
			bool sequenceValid = (c1_Close < c1_Open) && // Candle 1: Bearish
										(c2_Close > c2_Open) && // Candle 2: Bullish
										(c3_Close < c3_Open) && // Candle 3: Bearish
										(c4_Close > c4_Open);	// Candle 4: Bullish

			if (sequenceValid)
			{
				// Candle 1 is Bearish, dus de Close is de onderkant van de body (body-low)
				double ref_BodyLow = c1_Close;

				// 2. Regel: Volgende 3 candles mogen met hun body NIET LAGER sluiten dan ref_BodyLow
				if (c2_Close >= ref_BodyLow && c3_Close >= ref_BodyLow && c4_Close >= ref_BodyLow)
				{
					if (lastMessageTime != currentTime)
					{
						Print(">>> [ENTRY TRIGGER][W-PATROON] 4-Candle Theorie bevestigd bij Bottom 2! Open Buy Trade. Target: ", price_Neckline);
						Comment("4-CANDLE THEORY CONFIRMED: BUY!");

						// 1. Pak de laagste wick van EXACT de 4e candle (index 1)
						double candle4_Low = iLow(_Symbol, _Period, 1);

						// 2. Trek er 1 PIP buffer vanaf (10 punten)
						double sl_Buffer = 10 * _Point;
						double buy_StopLoss = candle4_Low - sl_Buffer;

						// 3. Open de Buy trade
						trade.SetExpertMagicNumber(EA_MagicNumber);
						trade.Buy(0.10, _Symbol, 0, buy_StopLoss, price_Neckline, "DTDB4C Buy");

						lastMessageTime = currentTime;
					}
				}
			}
		}
	}
}
bool HasOpenPositions()
{
	// Loop door alle open posities
	for (int i = PositionsTotal() - 1; i >= 0; i--)
	{
		// 1. Haal het unieke ticket-nummer op van de positie (dit selecteert de positie direct!)
		ulong ticket = PositionGetTicket(i);

		if (ticket > 0)
		{
			// 2. Controleer nu veilig het symbool en het Magic Number
			if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
				 PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
			{
				return true; // Deze specifieke bot heeft al een trade openstaan!
			}
		}
	}
	return false; // Geen actieve trades van deze bot gevonden
}
//+------------------------------------------------------------------+