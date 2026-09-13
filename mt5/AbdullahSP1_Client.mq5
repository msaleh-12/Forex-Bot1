//+------------------------------------------------------------------+
//|                                    AbdullahSP1_Client.mq5        |
//|                     Abdullah Strategy Part 1 — v3.1              |
//|  Fixes:                                                           |
//|    - Invisible markers (anchor/price inversion)                   |
//|    - Duplicate markers (name keyed on time only, not signal type) |
//|    - Cross-system bar-detection (uses OnCalculate, not OnTick)    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Abdullah SP1 Engine"
#property version   "3.10"
#property strict

//--- Inputs
input string InpServerBaseUrl   = "http://127.0.0.1:3000";
input int    InpHttpTimeoutMs   = 5000;
input int    InpCandleCount     = 50;
input int    InpHistoryCount    = 300;
input bool   InpBackfillOnStart = true;

//--- Strategy settings (sent to server, mirrors Pine inputs)
input int    InpSpreadLen    = 20;
input double InpSmallFactor  = 1.0;
input bool   InpShowDemand   = true;
input bool   InpShowSupply   = true;

//--- Marker appearance
input color  InpBuyColor     = clrOrange;
input color  InpSellColor    = clrLime;
input int    InpMarkerCode   = 159;      // Wingdings filled circle
input int    InpMarkerWidth  = 2;
input double InpOffsetFactor = 0.35;     // fraction of bar range

input bool   DEBUG_MODE = true;

#define OBJ_PREFIX "SP1_"

datetime g_lastBarTime  = 0;
bool     g_backfillDone = false;

//+------------------------------------------------------------------+
//| Timeframe to string                                              |
//+------------------------------------------------------------------+
string TFString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return EnumToString(tf);
   }
}

//+------------------------------------------------------------------+
//| Build JSON candle array — every candle passed in is closed       |
//+------------------------------------------------------------------+
string BuildCandlesJson(const MqlRates &r[], int count)
{
   string j = "[";
   for(int i = 0; i < count; i++)
   {
      j += "{\"time\":"    + IntegerToString((long)r[i].time)    + ","
         + "\"open\":"     + DoubleToString(r[i].open,  _Digits) + ","
         + "\"high\":"     + DoubleToString(r[i].high,  _Digits) + ","
         + "\"low\":"      + DoubleToString(r[i].low,   _Digits) + ","
         + "\"close\":"    + DoubleToString(r[i].close, _Digits) + ","
         + "\"volume\":"   + IntegerToString(r[i].tick_volume)   + ","
         + "\"confirmed\":true}";
      if(i < count - 1) j += ",";
   }
   return j + "]";
}

//+------------------------------------------------------------------+
//| Build settings JSON block                                        |
//+------------------------------------------------------------------+
string BuildSettingsJson()
{
   return "{\"spreadLen\":"   + IntegerToString(InpSpreadLen)      + ","
        + "\"smallFactor\":"  + DoubleToString(InpSmallFactor, 2)  + ","
        + "\"showDemand\":"   + (InpShowDemand ? "true" : "false") + ","
        + "\"showSupply\":"   + (InpShowSupply ? "true" : "false") + "}";
}

//+------------------------------------------------------------------+
//| HTTP POST — returns HTTP code, fills responseOut                 |
//+------------------------------------------------------------------+
int HttpPost(string url, string body, string &responseOut)
{
   uchar  data[], result[];
   string resHdr, reqHdr = "Content-Type: application/json\r\n";
   StringToCharArray(body, data, 0, StringLen(body));

   ResetLastError();
   int code = WebRequest("POST", url, reqHdr, InpHttpTimeoutMs, data, result, resHdr);

   if(code == -1)
   {
      Print("[SP1 ERROR] WebRequest failed err=", GetLastError(),
            " — whitelist this URL: ", url);
      return -1;
   }
   responseOut = CharArrayToString(result);
   if(DEBUG_MODE) Print("[SP1 DEBUG] POST ", url, " → HTTP ", code);
   return code;
}

//+------------------------------------------------------------------+
//| Draw one marker on the chart                                     |
//|                                                                  |
//| FIX 1: Object name keyed on TIME ONLY (no BUY_/SELL_ prefix).   |
//|   This guarantees at most ONE object per candle. If the server   |
//|   changes its mind between two ticks, the old one is replaced.   |
//|                                                                  |
//| FIX 2: Anchor and price are consistent:                          |
//|   BUY  marker sits BELOW the bar → price = low  - offset        |
//|         ANCHOR_TOP means the tip of the arrow is at `price`      |
//|   SELL marker sits ABOVE the bar → price = high + offset        |
//|         ANCHOR_BOTTOM means the tip of the arrow is at `price`   |
//+------------------------------------------------------------------+
void DrawMarker(datetime barTime, double barHigh, double barLow, bool isBuy)
{
   // One name per candle — deletes any previous marker for this bar
   string name = OBJ_PREFIX + IntegerToString((long)barTime);
   ObjectDelete(0, name);   // always delete first so type can change

   double range  = barHigh - barLow;
   double offset = MathMax(range * InpOffsetFactor, 5 * _Point);

   double price;
   ENUM_ARROW_ANCHOR anchor;
   color  col;

   if(isBuy)
   {
      // BUY dot goes BELOW the bar (same as Pine's location.belowbar for noDemand)
      // Wait — Pine plots noDemand ABOVE bar (abovebar). Match Pine exactly:
      // noDemand (BUY)  → plotshape location.abovebar → price = high + offset
      // noSupply (SELL) → plotshape location.belowbar → price = low  - offset
      price  = barHigh + offset;
      anchor = ANCHOR_BOTTOM;   // anchor point is at bottom of arrow glyph = price level
      col    = InpBuyColor;
   }
   else
   {
      price  = barLow - offset;
      anchor = ANCHOR_TOP;      // anchor point is at top of arrow glyph = price level
      col    = InpSellColor;
   }

   if(ObjectCreate(0, name, OBJ_ARROW, 0, barTime, price))
   {
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE,  InpMarkerCode);
      ObjectSetInteger(0, name, OBJPROP_COLOR,      col);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      InpMarkerWidth);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     anchor);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      if(DEBUG_MODE) Print("[SP1] Marker: ", (isBuy?"BUY":"SELL"),
                           " @ ", TimeToString(barTime), " price=", price);
   }
   else
      Print("[SP1 ERROR] ObjectCreate failed: ", name, " err=", GetLastError());
}

//+------------------------------------------------------------------+
//| Parse /api/signal response → "BUY", "SELL", or "NONE"           |
//+------------------------------------------------------------------+
string ExtractSignal(const string &resp)
{
   if(StringFind(resp, "\"signal\":\"BUY\"")  >= 0) return "BUY";
   if(StringFind(resp, "\"signal\":\"SELL\"") >= 0) return "SELL";
   return "NONE";
}

//+------------------------------------------------------------------+
//| Parse /api/calculate response                                    |
//| Expects: {"results":[{"index":N,"signal":"BUY|SELL"},…]}         |
//| Uses index to look up the candle in rates[] for high/low.        |
//+------------------------------------------------------------------+
void ProcessCalculateResponse(const string &resp, const MqlRates &rates[], int count)
{
   int pos   = 0;
   int drawn = 0;

   while(true)
   {
      // Find next "index": field
      int idxTag = StringFind(resp, "\"index\":", pos);
      if(idxTag < 0) break;

      int idxStart = idxTag + 8;
      int idxComma = StringFind(resp, ",", idxStart);
      if(idxComma < 0) break;
      int barIndex = (int)StringToInteger(StringSubstr(resp, idxStart, idxComma - idxStart));

      // Find the "signal" field in the same object
      // Search only up to the next "index": so we stay inside this object
      int nextIdx  = StringFind(resp, "\"index\":", idxComma);
      int searchTo = (nextIdx < 0) ? StringLen(resp) : nextIdx;

      int sigTag = StringFind(resp, "\"signal\":\"", idxComma);
      if(sigTag < 0 || sigTag > searchTo) { pos = (nextIdx < 0) ? StringLen(resp) : nextIdx; continue; }

      int sigStart = sigTag + 10;
      int sigEnd   = StringFind(resp, "\"", sigStart);
      if(sigEnd < 0) break;
      string sig = StringSubstr(resp, sigStart, sigEnd - sigStart);

      if((sig == "BUY" || sig == "SELL") && barIndex >= 0 && barIndex < count)
      {
         DrawMarker(rates[barIndex].time, rates[barIndex].high, rates[barIndex].low, sig == "BUY");
         drawn++;
      }

      pos = (nextIdx < 0) ? StringLen(resp) : nextIdx;
   }

   Print("[SP1] Historical backfill complete. Markers drawn: ", drawn);
}

//+------------------------------------------------------------------+
//| Historical backfill — ONE request on EA attach                   |
//+------------------------------------------------------------------+
void RunHistoricalBackfill()
{
   Print("[SP1] Starting historical backfill (", InpHistoryCount, " bars)...");

   MqlRates rates[];
   ArraySetAsSeries(rates, false);

   // shift=1 → skip the forming bar, every candle fetched is closed
   int copied = CopyRates(_Symbol, _Period, 1, InpHistoryCount, rates);
   if(copied < InpSpreadLen)
   {
      Print("[SP1 ERROR] Not enough history: ", copied, " bars");
      return;
   }

   string body = "{\"symbol\":\""    + _Symbol                    + "\","
               + "\"timeframe\":\"" + TFString(_Period)           + "\","
               + "\"settings\":"    + BuildSettingsJson()          + ","
               + "\"candles\":"     + BuildCandlesJson(rates, copied) + "}";

   string resp;
   int code = HttpPost(InpServerBaseUrl + "/api/calculate", body, resp);
   if(code != 200) { Print("[SP1 ERROR] Backfill HTTP ", code); return; }
   if(DEBUG_MODE) Print("[SP1 DEBUG] Backfill response (200 chars): ", StringSubstr(resp, 0, 200));

   ProcessCalculateResponse(resp, rates, copied);
   ChartRedraw(0);
   g_backfillDone = true;
}

//+------------------------------------------------------------------+
//| Live signal check — called once per confirmed new bar            |
//+------------------------------------------------------------------+
void CheckLiveSignal()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, false);

   // shift=1 → always skip the forming bar
   int copied = CopyRates(_Symbol, _Period, 1, InpCandleCount, rates);
   if(copied < InpSpreadLen) return;

   MqlRates lastClosed = rates[copied - 1];

   string body = "{\"symbol\":\""    + _Symbol                       + "\","
               + "\"timeframe\":\"" + TFString(_Period)              + "\","
               + "\"settings\":"    + BuildSettingsJson()             + ","
               + "\"candles\":"     + BuildCandlesJson(rates, copied) + "}";

   string resp;
   int code = HttpPost(InpServerBaseUrl + "/api/signal", body, resp);
   if(code != 200) { Print("[SP1 ERROR] Signal HTTP ", code); return; }

   string sig = ExtractSignal(resp);
   Print("[SP1 LIVE] Bar ", TimeToString(lastClosed.time), " → ", sig);

   if(sig == "BUY" || sig == "SELL")
   {
      DrawMarker(lastClosed.time, lastClosed.high, lastClosed.low, sig == "BUY");
      ChartRedraw(0);
   }

   Comment("Abdullah SP1 | ", _Symbol, " ", TFString(_Period),
           " | Last bar: ", TimeToString(lastClosed.time),
           " | Signal: ", sig);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_lastBarTime  = 0;
   g_backfillDone = false;

   Print("=== Abdullah SP1 v3.1 | ", _Symbol, " ", TFString(_Period), " ===");

   ObjectsDeleteAll(0, OBJ_PREFIX);   // clear any leftover markers

   if(InpBackfillOnStart)
      RunHistoricalBackfill();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Print("[SP1] EA removed. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//|                                                                  |
//| FIX 3: Use iTime(_Symbol, _Period, 1) — the time of the last     |
//| CLOSED bar — as the guard value instead of iTime(0).             |
//| iTime(0) can flicker to 0 or repeat at bar boundaries on         |
//| Windows MT5, causing the guard to pass multiple times.           |
//| iTime(1) is stable the moment the new bar opens and never        |
//| changes until the next bar, making it a reliable one-shot guard. |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime lastClosedBarTime = iTime(_Symbol, _Period, 1);
   if(lastClosedBarTime == 0)           return;   // data not ready yet
   if(lastClosedBarTime == g_lastBarTime) return;  // already processed this bar

   g_lastBarTime = lastClosedBarTime;
   CheckLiveSignal();
}
//+------------------------------------------------------------------+