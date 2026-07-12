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

bool m30_SignalActive = false;		 // Schakelt de M1-zoekmodus in of uit
datetime m30_SignalTime = 0;			 // Onthoudt wanneer de M30 kaars sloot
static double m30_ProtectedSL = 0.0; // Slaat de harde M30-bodem op

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
	datetime currentTime = iTime(_Symbol, _Period, 0);

	// 1. Als er al een actieve positie (trade) loopt van deze bot, doen we niks
	if (HasOpenPositions())
		return;

	// 2. TIMEOUT CHECK: Als de M30-zoekmodus al langer dan 30 minuten (1800 seconden) openstaat
	// zonder dat er op M1 een engulfing is geweest, resetten we de modus.
	if (m30_SignalActive && (TimeCurrent() - m30_SignalTime > 1800))
	{
		Print(">>> [TIMEOUT] Geen M1 entry gevonden binnen 30 minuten na M30 setup. Resetmodus...");
		m30_SignalActive = false;
	}

	// ------------------------------------------------------------------
	// DEEL A: SCANNEN VAN DE M30 STRUCTUUR
	// ------------------------------------------------------------------
	// We halen de data specifiek op van PERIOD_M30
	double c1_Open = iOpen(_Symbol, PERIOD_M30, 3);
	double c1_Close = iClose(_Symbol, PERIOD_M30, 3);
	double c2_Open = iOpen(_Symbol, PERIOD_M30, 2);
	double c2_Close = iClose(_Symbol, PERIOD_M30, 2);
	double c3_Open = iOpen(_Symbol, PERIOD_M30, 1);
	double c3_Close = iClose(_Symbol, PERIOD_M30, 1);

	bool longSequence = (c1_Close < c1_Open) && // C1: Rood
							  (c2_Close > c2_Open) && // C2: Groen
							  (c3_Close < c3_Open);	  // C3: Rood

	if (longSequence)
	{
		double ref_BodyLow = c1_Close;
		double ref_BodyHigh = c1_Open;
		double c2_bottom = c2_Open;
		double c3_bottom = c3_Close;
		double epsilon = 5 * _Point; // Jouw sweet spot marge van 0.5 pips

		bool bottomsValid = (c2_bottom >= (ref_BodyLow - epsilon) && c3_bottom >= (ref_BodyLow - epsilon));
		bool topsValid = (c2_Close <= (ref_BodyHigh + epsilon) && c3_Open <= (ref_BodyHigh + epsilon));
		bool c3_inside_c2 = (c3_Open <= (c2_Close + epsilon)) && (c3_Close >= (c2_Open - epsilon));

		// Als de M30 kaars NET gesloten is en aan de eisen voldoet:
		if (bottomsValid && topsValid && c3_inside_c2)
		{
			// Haal de sluitingstijd van de zojuist voltooide M30 kaars op
			datetime m30_CandleTime = iTime(_Symbol, PERIOD_M30, 0);

			if (lastMessageTime != m30_CandleTime)
			{
				// Haal de absolute laagste wick op van de 3 M30-kaarsen uit de structuur
				double c1_Low = iLow(_Symbol, PERIOD_M30, 3);
				double c2_Low = iLow(_Symbol, PERIOD_M30, 2);
				double c3_Low = iLow(_Symbol, PERIOD_M30, 1);

				m30_ProtectedSL = MathMin(c1_Low, MathMin(c2_Low, c3_Low));

				Print(">>> [M30 SETUP] Perfect patroon herkend op M30! Schakelen naar M1 zoekmodus...");
				m30_SignalActive = true;
				m30_SignalTime = TimeCurrent();
				lastMessageTime = m30_CandleTime; // Zorgt dat dit maar 1x per M30 kaars triggert
			}
		}
	}

	// ------------------------------------------------------------------
	// DEEL B: SCANNEN VAN DE M1 ENTRY TRIGER (BULLISH ENGULFING)
	// ------------------------------------------------------------------
	// Dit deel wordt pas uitgevoerd zodra de M30-zoekmodus hierboven is geactiveerd
	if (m30_SignalActive)
	{
		double m1_c1_Open = iOpen(_Symbol, PERIOD_M1, 1);
		double m1_c1_Close = iClose(_Symbol, PERIOD_M1, 1);
		double m1_c0_Open = iOpen(_Symbol, PERIOD_M1, 0);
		double m1_c0_Close = iClose(_Symbol, PERIOD_M1, 0);

		bool m1_c1_bearish = (m1_c1_Close < m1_c1_Open);
		bool m1_c0_bullish = (m1_c0_Close > m1_c0_Open);

		double m1_c1_bodySize = MathAbs(m1_c1_Open - m1_c1_Close);
		double m1_c0_bodySize = MathAbs(m1_c0_Close - m1_c0_Open);

		// We zetten de factor strak op 1.0: pure momentum ommekeer zonder te laat in te stappen
		double engulfingFactor = 1.3;
		bool m1_engulfing = (m1_c0_bodySize >= (m1_c1_bodySize * engulfingFactor));

		if (m1_c1_bearish && m1_c0_bullish && m1_engulfing)
		{
			double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

			// 1. Stop Loss: De beschermde, ruime bodem van de M30 structuur
			double buy_SL = m30_ProtectedSL;

			// Controleer of de SL wiskundig wel onder onze entry ligt
			if (entryPrice > buy_SL)
			{
				// 2. Take Profit: Risk-to-Reward Ratio = 1:2 op basis van de M30 structuur
				double sl_Distance = entryPrice - buy_SL;
				double buy_TP = entryPrice + (sl_Distance * 2);

				Print(">>> [M1 EXECUTION] Bullish Engulfing bevestigd. Open Market Buy met M30 SL.");
				trade.Buy(LotSize, _Symbol, entryPrice, buy_SL, buy_TP, "Pure4C M30-SL-Fix");

				m30_SignalActive = false; // Reset de zoekmodus direct
			}
		}
	}
}