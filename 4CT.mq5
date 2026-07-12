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
input double MinBoxSizePips = 8.0;	 // Minimale grootte van de M30-structuur in pips

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
	if (HasOpenPositions())
		return;

	if (m30_SignalActive && (TimeCurrent() - m30_SignalTime > 1800))
	{
		m30_SignalActive = false;
	}

	// ------------------------------------------------------------------
	// DEEL A: SCANNEN VAN DE M30 STRUCTUUR (ROOD - GROEN - ROOD)
	// ------------------------------------------------------------------
	double c1_Open = iOpen(_Symbol, PERIOD_M30, 3);
	double c1_Close = iClose(_Symbol, PERIOD_M30, 3);
	double c2_Open = iOpen(_Symbol, PERIOD_M30, 2);
	double c2_Close = iClose(_Symbol, PERIOD_M30, 2);
	double c3_Open = iOpen(_Symbol, PERIOD_M30, 1);
	double c3_Close = iClose(_Symbol, PERIOD_M30, 1);

	bool longSequence = (c1_Close < c1_Open) &&
							  (c2_Close > c2_Open) &&
							  (c3_Close < c3_Open);

	if (longSequence)
	{
		double ref_BodyLow = c1_Close;
		double ref_BodyHigh = c1_Open;
		double c2_bottom = c2_Open;
		double c3_bottom = c3_Close;
		double epsilon = 5 * _Point;

		bool bottomsValid = (c2_bottom >= (ref_BodyLow - epsilon) && c3_bottom >= (ref_BodyLow - epsilon));
		bool topsValid = (c2_Close <= (ref_BodyHigh + epsilon) && c3_Open <= (ref_BodyHigh + epsilon));
		bool c3_inside_c2 = (c3_Open <= (c2_Close + epsilon)) && (c3_Close >= (c2_Open - epsilon));

		if (bottomsValid && topsValid && c3_inside_c2)
		{
			datetime m30_CandleTime = iTime(_Symbol, PERIOD_M30, 0);

			if (lastMessageTime != m30_CandleTime)
			{
				double c1_Low = iLow(_Symbol, PERIOD_M30, 3);
				double c2_Low = iLow(_Symbol, PERIOD_M30, 2);
				double c3_Low = iLow(_Symbol, PERIOD_M30, 1);

				double c1_High = iHigh(_Symbol, PERIOD_M30, 3);
				double c2_High = iHigh(_Symbol, PERIOD_M30, 2);
				double c3_High = iHigh(_Symbol, PERIOD_M30, 1);

				m30_ProtectedSL = MathMin(c1_Low, MathMin(c2_Low, c3_Low));
				double m30_BoxTop = MathMax(c1_High, MathMax(c2_High, c3_High));

				// BEREKEN DE TOTALE GROOTTE VAN DE M30 STRUCTUUR
				double boxSizePips = (m30_BoxTop - m30_ProtectedSL) / (10 * _Point);

				// PRIJSACTIE FILTER: Negeer de setup als de M30 box te klein is (weinig volatiliteit)
				if (boxSizePips >= MinBoxSizePips)
				{
					PrintFormat(">>> [M30 SETUP] Volatiele box herkend (%.1f pips). M1 zoekmodus actief.", boxSizePips);
					m30_SignalActive = true;
					m30_SignalTime = TimeCurrent();
					lastMessageTime = m30_CandleTime;
				}
				else
				{
					PrintFormat(">>> [FILTER] M30 Box genegeerd wegens te krap (%.1f pips).", boxSizePips);
					lastMessageTime = m30_CandleTime; // Zorg dat we deze niet nog een keer checken
				}
			}
		}
	}

	// ------------------------------------------------------------------
	// DEEL B: JOUW ORIGINELE M1 ENTRY (FACTOR 1.3 -> 1:2 RRR)
	// ------------------------------------------------------------------
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

		double engulfingFactor = 1.3;
		bool m1_engulfing = (m1_c0_bodySize >= (m1_c1_bodySize * engulfingFactor));

		if (m1_c1_bearish && m1_c0_bullish && m1_engulfing)
		{
			double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
			double buy_SL = m30_ProtectedSL;

			if (entryPrice > buy_SL)
			{
				double sl_Distance = entryPrice - buy_SL;
				double buy_TP = entryPrice + (sl_Distance * 2.0);

				trade.Buy(LotSize, _Symbol, entryPrice, buy_SL, buy_TP, "Pure4C MinBox-Fix");
				m30_SignalActive = false;
			}
		}
	}
}