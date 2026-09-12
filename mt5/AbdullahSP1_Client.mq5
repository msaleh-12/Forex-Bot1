//+------------------------------------------------------------------+
//|                                    AbdullahSP1_Client.mq5         |
//|                     Copyright 2026, Abdullah SP1 Engine           |
//|  Thin client: sends OHLCV to a private server, draws the         |
//|  BUY/SELL markers the server tells it to. No strategy logic      |
//|  lives in this file - it is 100% on your server.                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Abdullah SP1 Engine"
#property version   "3.00"
#property strict

//--- Inputs: Server connection
input string InpServerBaseUrl   = "http://127.0.0.1:3000"; // Server base URL, NO trailing slash
input int    InpHttpTimeoutMs   = 5000;                     // WebRequest timeout (ms)

//--- Inputs: Data window sizes
input int    InpCandleCount     = 50;    // Closed candles sent per live signal check
input int    InpHistoryCount    = 300;   // Closed candles used for historical backfill
input bool   InpBackfillOnStart = true;  // Draw historical markers when EA attaches

//--- Inputs: Strategy settings (mirrors your Pine inputs, sent to server)
input int    InpSpreadLen    = 20;
input double InpSmallFactor  = 1.0;
input bool   InpShowDemand   = true;   // No Demand -> BUY marker (above bar)
input bool   InpShowSupply   = true;   // No Supply -> SELL marker (below bar)

//--- Inputs: Marker appearance (mirrors ndDotCol / nsDotCol in Pine)
input color  InpBuyColor     = clrOrange; // No Demand marker color
input color  InpSellColor    = clrLime;   // No Supply marker color
input int    InpMarkerCode   = 159;       // Wingdings filled-circle arrow code
input int    InpMarkerWidth  = 1;
input double InpOffsetFactor = 0.35;      // Marker distance from bar, as fraction of that bar's range

input bool   DEBUG_MODE      = true;

#define OBJ_PREFIX "SP1_"

//--- Global state
datetime g_lastSeenFormingBarTime = 0;
bool     g_backfillDone           = false;

//+------------------------------------------------------------------+
//| Timeframe -> string                                               |
//+------------------------------------------------------------------+
string GetTimeframeString(ENUM_TIMEFRAMES period)
{
   switch(period)
   {
      case PERIOD_M1:  return("M1");
      case PERIOD_M5:  return("M5");
      case PERIOD_M15: return("M15");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H4:  return("H4");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
      default: return(EnumToString(period));
   }
}

//+------------------------------------------------------------------+
//| Build the JSON "candles" array from a rates buffer.               |
//| Every candle passed in here is treated as CLOSED (confirmed=true) |
//| — caller is responsible for never including the forming bar.      |
//+------------------------------------------------------------------+
string BuildCandlesJson(const MqlRates &rates[], int count)
{
   string json = "[";
   for(int i = 0; i < count; i++)
   {
      json += "{\"time\":" + IntegerToString((long)rates[i].time) +
              ",\"open\":"  + DoubleToString(rates[i].open, _Digits) +
              ",\"high\":"  + DoubleToString(rates[i].high, _Digits) +
              ",\"low\":"   + DoubleToString(rates[i].low, _Digits) +
              ",\"close\":" + DoubleToString(rates[i].close, _Digits) +
              ",\"volume\":" + IntegerToString(rates[i].tick_volume) +
              ",\"confirmed\":true}";
      if(i < count - 1) json += ",";
   }
   json += "]";
   return json;
}

//+------------------------------------------------------------------+
//| Build the shared "settings" JSON block                            |
//+------------------------------------------------------------------+
string BuildSettingsJson()
{
   return "{\"spreadLen\":" + IntegerToString(InpSpreadLen) +
          ",\"smallFactor\":" + DoubleToString(InpSmallFactor, 2) +
          ",\"showDemand\":" + (InpShowDemand ? "true" : "false") +
          ",\"showSupply\":" + (InpShowSupply ? "true" : "false") + "}";
}

//+------------------------------------------------------------------+
//| POST helper. Returns HTTP status code, or -1 on failure.          |
//+------------------------------------------------------------------+
int HttpPost(string url, string jsonBody, string &responseOut)
{
   uchar data[];
   uchar result[];
   string result_headers;
   string headers = "Content-Type: application/json\r\n";

   StringToCharArray(jsonBody, data, 0, StringLen(jsonBody));

   ResetLastError();
   int status = WebRequest("POST", url, headers, InpHttpTimeoutMs, data, result, result_headers);

   if(status == -1)
   {
      int err = GetLastError();
      Print("[SP1 ERROR] WebRequest failed. Error: ", err,
            ". Add this exact URL under Tools -> Options -> Expert Advisors -> Allow WebRequest: ", url);
      return -1;
   }

   responseOut = CharArrayToString(result);
   if(DEBUG_MODE) Print("[SP1 DEBUG] POST ", url, " -> HTTP ", status);
   return status;
}

//+------------------------------------------------------------------+
//| Draw one marker on the chart (idempotent - skips if it exists)    |
//+------------------------------------------------------------------+
void DrawMarker(datetime barTime, double barHigh, double barLow, bool isBuy)
{
   string name = OBJ_PREFIX + (isBuy ? "BUY_" : "SELL_") + IntegerToString((long)barTime);

   if(ObjectFind(0, name) >= 0) return; // already drawn

   double range  = barHigh - barLow;
   double offset = MathMax(range * InpOffsetFactor, 10 * _Point);
   double price  = isBuy ? (barHigh + offset) : (barLow - offset);
   color  col    = isBuy ? InpBuyColor : InpSellColor;

   ObjectCreate(0, name, OBJ_ARROW, 0, barTime, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, InpMarkerCode);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, InpMarkerWidth);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_BOTTOM : ANCHOR_TOP);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   if(DEBUG_MODE) Print("[SP1 DEBUG] Marker drawn: ", name, " @ ", price);
}

//+------------------------------------------------------------------+
//| Extract "signal":"BUY"/"SELL"/"NONE" from a /api/signal response  |
//+------------------------------------------------------------------+
string ExtractSignal(const string &response)
{
   if(StringFind(response, "\"signal\":\"BUY\"") >= 0)  return "BUY";
   if(StringFind(response, "\"signal\":\"SELL\"") >= 0) return "SELL";
   return "NONE";
}

//+------------------------------------------------------------------+
//| Parse /api/calculate response and draw markers for every          |
//| historical BUY/SELL entry. Relies on field order emitted by       |
//| server/indicator.js: {"index":N, ..., "time":T, ..., "signal":S}  |
//+------------------------------------------------------------------+
void ProcessCalculateResponse(const string &response, const MqlRates &rates[])
{
   int pos = 0;
   int drawn = 0;

   while(true)
   {
      int idxTag = StringFind(response, "\"index\":", pos);
      if(idxTag < 0) break;

      int idxStart = idxTag + 8;
      int idxComma = StringFind(response, ",", idxStart);
      if(idxComma < 0) break;
      int barIndex = (int)StringToInteger(StringSubstr(response, idxStart, idxComma - idxStart));

      int nextIdxTag = StringFind(response, "\"index\":", idxComma);
      int searchEnd  = (nextIdxTag < 0) ? StringLen(response) : nextIdxTag;

      int sigTag = StringFind(response, "\"signal\":\"", idxComma);
      if(sigTag < 0 || sigTag > searchEnd) { pos = (nextIdxTag < 0) ? StringLen(response) : nextIdxTag; continue; }

      int sigStart = sigTag + 10;
      int sigEnd   = StringFind(response, "\"", sigStart);
      string signal = StringSubstr(response, sigStart, sigEnd - sigStart);

      if((signal == "BUY" || signal == "SELL") && barIndex >= 0 && barIndex < ArraySize(rates))
      {
         DrawMarker(rates[barIndex].time, rates[barIndex].high, rates[barIndex].low, signal == "BUY");
         drawn++;
      }

      pos = (nextIdxTag < 0) ? StringLen(response) : nextIdxTag;
   }

   if(DEBUG_MODE) Print("[SP1 DEBUG] Historical backfill complete. Markers drawn: ", drawn);
}

//+------------------------------------------------------------------+
//| One-time historical backfill via /api/calculate                   |
//+------------------------------------------------------------------+
void RunHistoricalBackfill()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, false); // oldest -> newest

   // shift=1 skips the currently forming bar entirely - every bar we fetch is closed
   int copied = CopyRates(_Symbol, _Period, 1, InpHistoryCount, rates);
   if(copied < InpSpreadLen)
   {
      Print("[SP1 ERROR] Backfill: not enough history (", copied, " bars, need ", InpSpreadLen, ")");
      return;
   }

   string body = "{\"symbol\":\"" + _Symbol + "\"" +
                 ",\"timeframe\":\"" + GetTimeframeString(_Period) + "\"" +
                 ",\"settings\":" + BuildSettingsJson() +
                 ",\"candles\":" + BuildCandlesJson(rates, copied) + "}";

   string response;
   int status = HttpPost(InpServerBaseUrl + "/api/calculate", body, response);
   if(status != 200)
   {
      Print("[SP1 ERROR] Backfill request failed with status ", status);
      return;
   }

   ProcessCalculateResponse(response, rates);
   g_backfillDone = true;
}

//+------------------------------------------------------------------+
//| Check the most recently CLOSED candle for a live signal            |
//+------------------------------------------------------------------+
void CheckLiveSignal()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, false); // oldest -> newest

   // shift=1 -> we never send the still-forming bar, fixing the "always NONE" bug
   int copied = CopyRates(_Symbol, _Period, 1, InpCandleCount, rates);
   if(copied < InpSpreadLen)
   {
      if(DEBUG_MODE) Print("[SP1 DEBUG] Not enough closed candles yet (", copied, ")");
      return;
   }

   MqlRates lastClosed = rates[copied - 1];

   string body = "{\"symbol\":\"" + _Symbol + "\"" +
                 ",\"timeframe\":\"" + GetTimeframeString(_Period) + "\"" +
                 ",\"settings\":" + BuildSettingsJson() +
                 ",\"candles\":" + BuildCandlesJson(rates, copied) + "}";

   string response;
   int status = HttpPost(InpServerBaseUrl + "/api/signal", body, response);
   if(status != 200)
   {
      Print("[SP1 ERROR] Signal request failed with status ", status);
      return;
   }

   string signal = ExtractSignal(response);
   if(DEBUG_MODE) Print("[SP1 DEBUG] Live signal for closed bar ", TimeToString(lastClosed.time), " = ", signal);

   if(signal == "BUY")
      DrawMarker(lastClosed.time, lastClosed.high, lastClosed.low, true);
   else if(signal == "SELL")
      DrawMarker(lastClosed.time, lastClosed.high, lastClosed.low, false);

   Comment("Abdullah SP1 | ", _Symbol, " ", GetTimeframeString(_Period),
           " | Last closed bar: ", TimeToString(lastClosed.time),
           " | Signal: ", signal);
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_lastSeenFormingBarTime = 0;
   g_backfillDone = false;

   Print("[SP1] Abdullah SP1 EA initialized. Server: ", InpServerBaseUrl);

   if(InpBackfillOnStart)
      RunHistoricalBackfill();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   Print("[SP1] Abdullah SP1 EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentFormingBarTime = iTime(_Symbol, _Period, 0);
   if(currentFormingBarTime == 0) return;

   // Only act once per new bar (i.e. once the previous bar has actually closed)
   if(currentFormingBarTime == g_lastSeenFormingBarTime) return;
   g_lastSeenFormingBarTime = currentFormingBarTime;

   CheckLiveSignal();
}
//+------------------------------------------------------------------+
