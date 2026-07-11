//+------------------------------------------------------------------+
//|                                                   Pure4Candle.mq5 |
//|                                                     Daniel Carter |
//|                                              https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

// Inputs
input ulong EA_MagicNumber = 654321; // Unieke ID voor deze bot
input double LotSize = 0.10;			 // Grootte van de trade

datetime lastMessageTime = 0; // Voorkomt dubbele entries op dezelfde candle

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
	trade.SetExpertMagicNumber(EA_MagicNumber);
	Print("Pure 4-Candle Bot Gestart. Scannen naar live patronen...");
	return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Helper: Controleer of er al een positie openstaat                |
//+------------------------------------------------------------------+
bool HasOpenPositions()
{
	for (int i = PositionsTotal() - 1; i >= 0; i--)
	{
		ulong ticket = PositionGetTicket(i);
		if (ticket > 0)
		{
			if (PositionGetString(POSITION_SYMBOL) == _Symbol &&
				 PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
			{
				return true;
			}
		}
	}
	return false;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
	// Controleer alleen bij een nieuwe tick/candle en stop als er al een trade loopt
	datetime currentTime = iTime(_Symbol, _Period, 0);
	// Controleer of er al een positie openstaat van deze bot
	// Blokkeer de bot als er al een actieve trade loopt óf als er een pending order klaarstaat
	// 1. Als er een actieve positie (trade) loopt, doen we niks
	if (HasOpenPositions())
		return;

	// 2. Als er GEEN trade loopt, maar wel een openstaande PENDING order van DEZE bot:
	if (OrdersTotal() > 0)
	{
		// Als de tijd is versprongen, is de kaars gesloten zonder de order te triggeren!
		if (currentTime != lastMessageTime)
		{
			Print(">>> [CANCEL] Kaars is voorbij en order is niet geraakt. Annuleren...");

			for (int i = OrdersTotal() - 1; i >= 0; i--)
			{
				if (OrderGetTicket(i) > 0)
				{
					if (OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == EA_MagicNumber)
					{
						trade.OrderDelete(OrderGetTicket(i));
					}
				}
			}

			// BELANGRIJK: We zetten lastMessageTime NIET gelijk aan currentTime bij een cancel,
			// zodat de bot DIRECT op deze tick al mag scannen naar een nieuw patroon!
			lastMessageTime = 0;
		}

		// De return moet ALLEEN gelden als de order op deze specifieke tick nog LIVE moet blijven wachten!
		if (OrdersTotal() > 0)
		{
			return;
		}
	}

	// Haal de data op van de laatste 4 gesloten candles
	double c1_Open = iOpen(_Symbol, _Period, 3);
	double c1_Close = iClose(_Symbol, _Period, 3);

	double c2_Open = iOpen(_Symbol, _Period, 2);
	double c2_Close = iClose(_Symbol, _Period, 2);

	double c3_Open = iOpen(_Symbol, _Period, 1);
	double c3_Close = iClose(_Symbol, _Period, 1);

	double c4_Open = iOpen(_Symbol, _Period, 0);
	double c4_Close = iClose(_Symbol, _Period, 0);
	double c4_High = iHigh(_Symbol, _Period, 0);
	double c4_Low = iLow(_Symbol, _Period, 0);

	// // --- CHECK 1: PURE BEARISH SEQUENCE (SHORT / SELL) ---
	// bool shortSequence = (c1_Close > c1_Open) && // C1: Groen
	// 							(c2_Close < c2_Open) && // C2: Rood
	// 							(c3_Close > c3_Open) && // C3: Groen
	// 							(c4_Close < c4_Open);	// C4: Rood

	// if (shortSequence)
	// {
	// 	// Referentieniveau is de BOVENKANT van de body van Candle 1 (de Close)
	// 	double ref_BodyHigh = c1_Close;

	// 	// Bepaal de bovenkant van de body voor C2, C3 en C4
	// 	double c2_top = c2_Open;  // Rood, dus Open is bovenkant
	// 	double c3_top = c3_Close; // Groen, dus Close is bovenkant
	// 	double c4_top = c4_Open;  // Rood, dus Open is bovenkant

	// 	// Eis: Geen enkele bovenkant van de body mag hoger zijn dan ref_BodyHigh
	// 	if (c2_top <= ref_BodyHigh && c3_top <= ref_BodyHigh && c4_top <= ref_BodyHigh)
	// 	{
	// 		if (lastMessageTime != currentTime)
	// 		{
	// 			Print(">>> [4-CANDLE SHORT] Patroon correct binnen box! Open Sell.");

	// 			double sl_Buffer = 10 * _Point;
	// 			double sell_SL = c4_High + sl_Buffer;
	// 			double sl_Distance = sell_SL - c4_Close;
	// 			double sell_TP = c4_Close - (sl_Distance * 2);

	// 			trade.Sell(LotSize, _Symbol, 0, sell_SL, sell_TP, "Pure4C Short");
	// 			lastMessageTime = currentTime;
	// 		}
	// 	}
	// }

	// --- CHECK 2: PURE BULLISH SEQUENCE (LONG / BUY) ---
	bool longSequence = (c1_Close < c1_Open) && // C1: Rood
							  (c2_Close > c2_Open) && // C2: Groen
							  (c3_Close < c3_Open);	  // C3: Rood
															  //(c4_Close > c4_Open);	  // C4: Groen

	if (longSequence)
	{
		double ref_BodyLow = c1_Close; // Onderkant paarse box
		double ref_BodyHigh = c1_Open; // Bovenkant paarse box

		double c2_bottom = c2_Open;
		double c3_bottom = c3_Close;

		// VOEG DEZE REGEL TOE: Marge van 0.3 pips (3 punten)
		double epsilon = 0 * _Point;

		// PAS DEZE DRIE REGELS AAN (epsilon toegevoegd):
		bool bottomsValid = (c2_bottom >= (ref_BodyLow - epsilon) && c3_bottom >= (ref_BodyLow - epsilon));
		bool topsValid = (c2_Close <= (ref_BodyHigh + epsilon) && c3_Open <= (ref_BodyHigh + epsilon));
		bool c3_inside_c2 = (c3_Open <= (c2_Close + epsilon)) && (c3_Close >= (c2_Open - epsilon));

		// NIEUWE EIS: C4 close moet HOGER zijn dan C2 close (top) en C3 open (top)
		// bool c4_breakout = (c4_Close > c2_Close) && (c4_Close > c3_Open);

		if (bottomsValid && topsValid && c3_inside_c2)
		{
			if (lastMessageTime != currentTime)
			{
				Print(">>> [4-CANDLE] Candle 3 gesloten! Plaatsen Buy Limit op c1_Close.");

				// 1. Entry Prijs: De sluitingsprijs van candle 1 (onderkant van de box)
				double entryPrice = c1_Close;
				double c1_Low = iLow(_Symbol, _Period, 3);
				double c2_Low = iLow(_Symbol, _Period, 2);
				double c3_Low = iLow(_Symbol, _Period, 1);
				// 2. Stop Loss: Hardcoded op 3 pips (30 punten) onder de entry prijs

				double buy_SL = MathMin(c1_Low, MathMin(c2_Low, c3_Low));
				// 3. Take Profit: Risk-to-Reward Ratio = 1:2
				// De sl_Distance is nu exact gelijk aan die 3 pips risico
				double sl_Distance = entryPrice - buy_SL;
				double buy_TP = entryPrice + (sl_Distance * 3.0); // 2x het risico (dus 6 pips winst)

				// 4. Plaats de Pending Buy Limit order direct bij het sluiten van candle 3
				trade.BuyLimit(LotSize, entryPrice, _Symbol, buy_SL, buy_TP, ORDER_TIME_GTC, 0, "Pure4C BuyLimit");

				lastMessageTime = currentTime;
			}
		}
	}
}