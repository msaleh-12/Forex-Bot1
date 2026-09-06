import express from 'express';
import { calculateSignal, calculateFullSeries } from './indicator.js';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json({ limit: '10mb' }));

app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});

app.get('/', (req, res) => {
  res.json({
    app: 'Abdullah SP1 Server',
    version: '1.0.0',
    status: 'online',
    endpoints: {
      health: 'GET /api/health',
      signal: 'POST /api/signal',
      calculate: 'POST /api/calculate',
    },
  });
});

app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

app.post('/api/signal', (req, res) => {
  try {
    const { symbol = 'EURUSD', timeframe = 'H4', candles = [], settings = {} } = req.body;

    if (!Array.isArray(candles) || candles.length === 0) {
      return res.status(400).json({
        error: 'Invalid payload: candles array is required',
        signal: 'NONE',
      });
    }

    const result = calculateSignal(candles, settings);

    return res.json({
      symbol,
      timeframe,
      serverTimestamp: new Date().toISOString(),
      ...result,
    });
  } catch (err) {
    console.error('Error calculating signal:', err);
    return res.status(500).json({
      error: 'Internal server calculation error',
      signal: 'NONE',
      message: err.message,
    });
  }
});

app.post('/api/calculate', (req, res) => {
  try {
    const { symbol = 'EURUSD', timeframe = 'H4', candles = [], settings = {} } = req.body;

    if (!Array.isArray(candles) || candles.length === 0) {
      return res.status(400).json({
        error: 'Invalid payload: candles array is required',
        results: [],
      });
    }

    const series = calculateFullSeries(candles, settings);

    return res.json({
      symbol,
      timeframe,
      totalCandles: candles.length,
      signalsCount: {
        buy: series.filter((s) => s.signal === 'BUY').length,
        sell: series.filter((s) => s.signal === 'SELL').length,
      },
      results: series,
    });
  } catch (err) {
    console.error('Error calculating series:', err);
    return res.status(500).json({
      error: 'Internal server calculation error',
      message: err.message,
    });
  }
});

app.listen(PORT, () => {
  console.log(`=================================================`);
  console.log(` Abdullah SP1 Indicator API Server Running`);
  console.log(` URL: http://localhost:${PORT}`);
  console.log(` Health Check: http://localhost:${PORT}/api/health`);
  console.log(`=================================================`);
});