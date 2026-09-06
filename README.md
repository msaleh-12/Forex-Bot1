# Abdullah SP1 - MetaTrader 5 Proprietary Indicator System

[![Node.js Engine](https://img.shields.io/badge/Node.js-v18%2B-green.svg)](https://nodejs.org/)
[![MetaTrader 5](https://img.shields.io/badge/MetaTrader-5-blue.svg)](https://www.metatrader5.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An enterprise-grade client-server indicator system that decouples proprietary algorithmic trading calculations from MetaTrader 5 (MT5). The trading engine executes server-side via a Node.js Express REST API, while the MQL5 client lightweight indicator handles chart execution and HTTP communication.

---

## 📐 System Architecture

```text
┌─────────────────────────────────────────────────────────┐
│                 MetaTrader 5 Client                      │
│             (mt5/AbdullahSP1_Client.mq5)                │
│  - Captures historical MqlRates on new candle           │
│  - Formats candlestick payload & parameters            │
│  - Sends HTTP POST WebRequest                           │
└────────────────────────────┬────────────────────────────┘
                             │ HTTP POST /api/signal
                             ▼
┌─────────────────────────────────────────────────────────┐
│                 Node.js Express Server                  │
│                   (server/server.js)                    │
│  - CORS & Payload validation                            │
│  - Signal endpoint & Full Series calculation endpoints  │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│              Proprietary Indicator Engine               │
│                  (server/indicator.js)                  │
│  - Normalizes settings & calculates Body Spreads        │
│  - Computes Moving Average (SMA) of Spreads             │
│  - Evaluates Low Volume & Small Body criteria           │
│  - Outputs BUY (No Demand) / SELL (No Supply) signals   │
└─────────────────────────────────────────────────────────┘
```

### Key Benefits of this Architecture
1. **IP Protection**: Core trading logic and math stay secure on your server rather than compiled into client-side `.ex5` binaries that can be decompiled.
2. **Centralized Logic**: Update signal parameters or calculation algorithms in one place without needing to redistribute updated `.mq5`/`.ex5` files to client terminals.
3. **Cross-Platform Readiness**: The server API can support MT4, TradingView Webhooks, Python bots, or web dashboards simultaneously.

---

## 📂 Repository Structure

```text
AbdullahSP1-MT5/
├── .gitignore               # Ignored dependencies & system files
├── README.md                # System documentation
├── full_context.txt         # Consolidated single-file codebase dump
├── mt5/
│   └── AbdullahSP1_Client.mq5 # MQL5 Custom Indicator Client for MT5
└── server/
    ├── package.json         # Node.js dependencies & scripts
    ├── server.js             # REST API Express Server
    ├── indicator.js          # Proprietary Indicator Calculation Engine
    └── indicator.test.js     # Native Node.js Unit Test Suite
```

---

## 💡 Algorithmic Logic & Signal Rules

The Abdullah SP1 strategy uses Volume Spread Analysis (VSA) principles to detect **No Demand** and **No Supply** setups:

### 1. Body Spread & Moving Average
- **Candle Body Spread**: `Spread = |Close - Open|`
- **Spread SMA**: `AvgSpread = SMA(Spread, spreadLen)` (Default `spreadLen = 20`)

### 2. Volume & Spread Filtering
- **Low Volume Condition**: A candle has lower volume than the preceding 2 bars:
  $$\text{Volume}_t < \text{Volume}_{t-1} \quad \text{AND} \quad \text{Volume}_t < \text{Volume}_{t-2}$$
- **Small Body Condition**: Candle body is smaller than the average spread scaled by a sensitivity factor:
  $$\text{Spread}_t < \text{AvgSpread}_t \times \text{smallFactor}$$

### 3. Signal Generation
- 🟢 **BUY (No Demand Signal)**:
  - Bullish Candle (`Close > Open`)
  - Low Volume condition met
  - Small Body condition met
  - Bar is confirmed (`confirmed == true`)
  - `showDemand == true`

- 🔴 **SELL (No Supply Signal)**:
  - Bearish Candle (`Close < Open`)
  - Low Volume condition met
  - Small Body condition met
  - Bar is confirmed (`confirmed == true`)
  - `showSupply == true`

> ⚠️ **Note**: Developing/forming bars (`confirmed == false`) are strictly rejected by the server to prevent signal repainting.

---

## 🚀 Quick Start & Installation

### 1. Server Setup (Node.js)

#### Prerequisites
- Node.js `v18.0.0` or higher

#### Installation & Run
```bash
# Navigate to the server folder
cd server

# Install dependencies
npm install

# Start production server (runs on port 3000 by default)
npm start
```

For development mode:
```bash
npm run dev
```

To run unit tests:
```bash
npm test
```

---

### 2. MetaTrader 5 Integration

#### Step A: Configure WebRequest in MT5
1. Open MetaTrader 5 terminal.
2. Navigate to **Tools -> Options** (or press `Ctrl + O`).
3. Click the **Expert Advisors** tab.
4. Check **"Allow WebRequest for listed URL"**.
5. Add `http://127.0.0.1:3000` (or your remote server IP/domain).
6. Click **OK**.

#### Step B: Install Indicator
1. Open MT5 and select **File -> Open Data Folder**.
2. Navigate to `MQL5/Indicators/`.
3. Copy `mt5/AbdullahSP1_Client.mq5` into this folder.
4. Restart MT5 or right-click **Indicators** in the Navigator panel and select **Refresh**.
5. Drag `AbdullahSP1_Client` onto any chart (e.g. EURUSD, H4).

---

## 📡 API Reference

### 1. Health Check
Checks if the indicator server is online and operational.

- **Endpoint**: `GET /api/health`
- **Response**:
```json
{
  "status": "ok",
  "timestamp": "2026-09-07T00:00:00.000Z",
  "uptime": 124.56
}
```

---

### 2. Calculate Latest Signal
Calculates the trading signal for the current candle series.

- **Endpoint**: `POST /api/signal`
- **Headers**: `Content-Type: application/json`
- **Request Body**:
```json
{
  "symbol": "EURUSD",
  "timeframe": "H4",
  "settings": {
    "spreadLen": 20,
    "smallFactor": 1.0,
    "showDemand": true,
    "showSupply": true
  },
  "candles": [
    {
      "time": 1700000000,
      "open": 1.0850,
      "high": 1.0890,
      "low": 1.0840,
      "close": 1.0875,
      "volume": 1250,
      "confirmed": true
    },
    {
      "time": 1700014400,
      "open": 1.0875,
      "high": 1.0880,
      "low": 1.0860,
      "close": 1.0870,
      "volume": 850,
      "confirmed": true
    }
  ]
}
```

- **Response**:
```json
{
  "symbol": "EURUSD",
  "timeframe": "H4",
  "serverTimestamp": "2026-09-07T00:00:00.000Z",
  "signal": "BUY",
  "timestamp": 1700014400,
  "close": 1.0870,
  "open": 1.0875,
  "volume": 850,
  "metrics": {
    "bodySpread": 0.0005,
    "avgSpread": 0.0012,
    "smallFactor": 1.0,
    "spreadThreshold": 0.0012,
    "lowVolume": true,
    "smallBody": true,
    "isBullish": true,
    "isBearish": false,
    "isConfirmed": true,
    "noDemand": true,
    "noSupply": false,
    "validDemand": true,
    "validSupply": false
  }
}
```

---

### 3. Calculate Full Series (Historical Analysis)
Calculates signals for every candle in the provided array.

- **Endpoint**: `POST /api/calculate`
- **Response**:
```json
{
  "symbol": "EURUSD",
  "timeframe": "H4",
  "totalCandles": 50,
  "signalsCount": {
    "buy": 3,
    "sell": 2
  },
  "results": [
    {
      "index": 0,
      "time": 1700000000,
      "signal": "NONE"
    },
    {
      "index": 49,
      "time": 1700705600,
      "signal": "BUY"
    }
  ]
}
```

---

## 🧪 Unit Testing

The repository includes a standalone test suite with **13 automated tests** covering SMA calculation, parameter normalization, boundary conditions, volume logic, and non-repainting unconfirmed bar rejections.

Run tests using:
```bash
cd server
npm test
```

Sample output:
```text
✔ 1. SMA Calculation
✔ 2. Settings Normalization & Backward Compatibility
✔ 3. Bullish No Demand (BUY Signal)
✔ 4. Bearish No Supply (SELL Signal)
✔ 5. High Volume Rejection
✔ 6. Body Too Large Rejection
✔ 7. Insufficient SMA History
✔ 8. Unconfirmed Candle Rejection
✔ 9. showDemand = false Rejection
✔ 10. showSupply = false Rejection
✔ 11. Exact Boundary Behavior for Body Spread Threshold
✔ 12. Detailed Volume Comparisons (vol < vol[1] AND vol < vol[2])
✔ 13. calculateFullSeries Verification
```

---

## 🛡️ License

This project is released under the **MIT License**.
