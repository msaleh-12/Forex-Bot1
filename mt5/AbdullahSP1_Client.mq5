//+------------------------------------------------------------------+
//|                                         AbdullahSP1_Client.mq5   |
//|                        Copyright 2026, Proprietary Engine Client |
//|                                       http://127.0.0.1:3000     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Abdullah SP1 Engine"
#property link      "http://127.0.0.1:3000"
#property version   "2.00"
#property script_show_inputs

//--- Inputs
input string   InpServerUrl     = "http://127.0.0.1:3000/api/signal";
input int      InpCandleCount   = 50;
input int      InpSpreadLen     = 20;
input double   InpSmallFactor   = 1.0;
input bool     InpShowDemand    = true;
input bool     InpShowSupply    = true;
input bool     DEBUG_MODE       = true;

//--- Global state
static datetime g_lastCandleTime = 0;

//+------------------------------------------------------------------+
//| Helper to convert ENUM_TIMEFRAMES to string                      |
//+------------------------------------------------------------------+
string GetTimeframeString(ENUM_TIMEFRAMES period)
  {
   switch(period)
     {
      case PERIOD_M1:  return("M1");
      case PERIOD_M2:  return("M2");
      case PERIOD_M3:  return("M3");
      case PERIOD_M4:  return("M4");
      case PERIOD_M5:  return("M5");
      case PERIOD_M6:  return("M6");
      case PERIOD_M10: return("M10");
      case PERIOD_M12: return("M12");
      case PERIOD_M15: return("M15");
      case PERIOD_M20: return("M20");
      case PERIOD_M30: return("M30");
      case PERIOD_H1:  return("H1");
      case PERIOD_H2:  return("H2");
      case PERIOD_H3:  return("H3");
      case PERIOD_H4:  return("H4");
      case PERIOD_H6:  return("H6");
      case PERIOD_H8:  return("H8");
      case PERIOD_D1:  return("D1");
      case PERIOD_W1:  return("W1");
      case PERIOD_MN1: return("MN1");
      default:         return(EnumToString(period));
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_lastCandleTime = 0;
   Print("[SP1] Abdullah SP1 Client Initialized. Server URL: ", InpServerUrl);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("[SP1] Abdullah SP1 Client Deinitialized. Reason: ", reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Get current candle open time
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime == 0)
     {
      if(DEBUG_MODE) Print("[SP1 DEBUG] Failed to get current candle open time for ", _Symbol);
      return;
     }

   // New-candle detection: do NOT send repeated API requests during forming candle
   if(currentBarTime == g_lastCandleTime)
     {
      return;
     }

   // Update tracked bar time on new candle
   g_lastCandleTime = currentBarTime;

   if(DEBUG_MODE)
     {
      Print("[SP1 DEBUG] New candle detected");
      Print("[SP1 DEBUG] Symbol: ", _Symbol);
      Print("[SP1 DEBUG] Timeframe: ", GetTimeframeString(_Period));
     }

   // 2. Collect candles using CopyRates
   MqlRates rates[];
   ArraySetAsSeries(rates, false); // Oldest = index 0, Newest = index count-1

   int copied = CopyRates(_Symbol, _Period, 0, InpCandleCount, rates);
   if(copied < InpSpreadLen)
     {
      Print("[SP1 ERROR] CopyRates failed or returned insufficient candles: ", copied, " (required: ", InpSpreadLen, ")");
      return;
     }

   if(DEBUG_MODE)
     {
      Print("[SP1 DEBUG] Candles collected: ", copied);
      Print("[SP1 DEBUG] First candle: ", TimeToString(rates[0].time, TIME_DATE|TIME_MINUTES), " (timestamp: ", (long)rates[0].time, ")");
      Print("[SP1 DEBUG] Last candle: ", TimeToString(rates[copied - 1].time, TIME_DATE|TIME_MINUTES), " (timestamp: ", (long)rates[copied - 1].time, ")");
      Print("[SP1 DEBUG] Last candle confirmed: false");
     }

   // Explicit ordering verification
   if(rates[0].time >= rates[copied - 1].time)
     {
      Print("[SP1 ERROR] Invalid candle ordering! Oldest time (", (long)rates[0].time, ") >= Newest time (", (long)rates[copied - 1].time, ")");
      return;
     }

   // 3. Build JSON Payload
   string jsonBody = "{\"symbol\":\"" + _Symbol + "\"" +
                     ",\"timeframe\":\"" + GetTimeframeString(_Period) + "\"" +
                     ",\"settings\":{" +
                       "\"spreadLen\":" + IntegerToString(InpSpreadLen) +
                       ",\"smallFactor\":" + DoubleToString(InpSmallFactor, 2) +
                       ",\"showDemand\":" + (InpShowDemand ? "true" : "false") +
                       ",\"showSupply\":" + (InpShowSupply ? "true" : "false") +
                     "}" +
                     ",\"candles\":[";

   for(int i = 0; i < copied; i++)
     {
      bool isConfirmed = (i < copied - 1); // Historical candles are true; current forming candle (copied - 1) is false
      jsonBody += "{\"time\":" + IntegerToString((long)rates[i].time) +
                  ",\"open\":" + DoubleToString(rates[i].open, _Digits) +
                  ",\"high\":" + DoubleToString(rates[i].high, _Digits) +
                  ",\"low\":" + DoubleToString(rates[i].low, _Digits) +
                  ",\"close\":" + DoubleToString(rates[i].close, _Digits) +
                  ",\"volume\":" + IntegerToString(rates[i].tick_volume) +
                  ",\"confirmed\":" + (isConfirmed ? "true" : "false") + "}";

      if(i < copied - 1)
         jsonBody += ",";
     }
   jsonBody += "]}";

   // 4. Send HTTP WebRequest
   uchar data[];
   uchar result[];
   string result_headers;
   string headers = "Content-Type: application/json\r\n";

   StringToCharArray(jsonBody, data, 0, StringLen(jsonBody));

   if(DEBUG_MODE) Print("[SP1 DEBUG] HTTP request sent");

   ResetLastError();
   int res = WebRequest("POST", InpServerUrl, headers, 3000, data, result, result_headers);

   if(res == -1)
     {
      int err = GetLastError();
      Print("[SP1 ERROR] WebRequest failed with error code: ", err, ". Check MT5 Allow WebRequest settings for URL: ", InpServerUrl);
      return;
     }

   if(DEBUG_MODE) Print("[SP1 DEBUG] HTTP response code: ", res);

   if(res != 200)
     {
      Print("[SP1 ERROR] Server returned HTTP error code: ", res);
      return;
     }

   // 5. Parse Response Signal
   string responseStr = CharArrayToString(result);
   if(DEBUG_MODE) Print("[SP1 DEBUG] Server response: ", responseStr);

   string parsedSignal = "NONE";
   if(StringFind(responseStr, "\"signal\":\"BUY\"") >= 0)
      parsedSignal = "BUY";
   else if(StringFind(responseStr, "\"signal\":\"SELL\"") >= 0)
      parsedSignal = "SELL";
   else if(StringFind(responseStr, "\"signal\":\"NONE\"") >= 0)
      parsedSignal = "NONE";
   else
     {
      Print("[SP1 ERROR] Unexpected or unparseable server response: ", responseStr);
      return;
     }

   if(DEBUG_MODE) Print("[SP1 DEBUG] Final signal: ", parsedSignal);
  }
//+------------------------------------------------------------------+
