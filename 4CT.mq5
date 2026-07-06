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
	if (HasOpenPositions())
	{
		// Als de huidige tijd verschilt van lastMessageTime, betekent dit
		// dat de kaars waarin we de trade openden (de 5e candle) nu volledig gesloten is.
		if (currentTime != lastMessageTime)
		{
			Print(">>> [TAKE PROFIT] 5e candle is gesloten. Sluit positie.");
			trade.PositionClose(_Symbol); // Sluit de openstaande trade op de markt
		}
		return; // Stop hier, we gaan geen nieuwe trades openen zolang er een loopt
	}

	// Haal de data op van de laatste 4 gesloten candles
	double c1_Open = iOpen(_Symbol, _Period, 4);
	double c1_Close = iClose(_Symbol, _Period, 4);

	double c2_Open = iOpen(_Symbol, _Period, 3);
	double c2_Close = iClose(_Symbol, _Period, 3);

	double c3_Open = iOpen(_Symbol, _Period, 2);
	double c3_Close = iClose(_Symbol, _Period, 2);

	double c4_Open = iOpen(_Symbol, _Period, 1);
	double c4_Close = iClose(_Symbol, _Period, 1);
	double c4_High = iHigh(_Symbol, _Period, 1);
	double c4_Low = iLow(_Symbol, _Period, 1);

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
							  (c3_Close < c3_Open) && // C3: Rood
							  (c4_Close > c4_Open);	  // C4: Groen

	if (longSequence)
	{
		double ref_BodyLow = c1_Close; // Onderkant paarse box
		double ref_BodyHigh = c1_Open; // Bovenkant paarse box

		double c2_bottom = c2_Open;
		double c3_bottom = c3_Close;
		double c4_bottom = c4_Open;

		// Vorige box-eisen
		bool bottomsValid = (c2_bottom >= ref_BodyLow && c3_bottom >= ref_BodyLow && c4_bottom >= ref_BodyLow);
		bool topsValid = (c2_Close < ref_BodyHigh && c3_Open < ref_BodyHigh);

		// Candle 3 body volledig binnen Candle 2 body (Inside Bar)
		bool c3_inside_c2 = (c3_Open < c2_Close) && (c3_Close > c2_Open);

		// NIEUWE EIS: C4 close moet HOGER zijn dan C2 close (top) en C3 open (top)
		// bool c4_breakout = (c4_Close > c2_Close) && (c4_Close > c3_Open);

		if (bottomsValid && topsValid && c3_inside_c2)
		{
			if (lastMessageTime != currentTime)
			{
				Print(">>> [4-CANDLE] Candle 3 gesloten! Plaatsen Buy Stop op c3_Open.");

				// 1. Entry Prijs: De openingsprijs van de zojuist gesloten candle 3
				double entryPrice = c3_Open;

				// 2. Stop Loss: Het laagste punt (wick) van candle 4 (index 2 in deze context)
				double buy_SL = c4_Low;

				// 3. Take Profit: Risk-to-Reward Ratio = 1:2
				// Afstand van de geplande entry tot de SL vermenigvuldigen met 2
				double sl_Distance = entryPrice - buy_SL;
				double buy_TP = entryPrice + (sl_Distance * 2.0); // 2x het risico

				// 4. Plaats de Pending Buy Stop order direct bij het sluiten van candle 3
				trade.BuyStop(LotSize, entryPrice, _Symbol, buy_SL, buy_TP, ORDER_TIME_GTC, 0, "Pure4C BuyStop");

				lastMessageTime = currentTime;
			}
		}
	}
}