import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  calculateSMA,
  calculateSignal,
  calculateFullSeries,
  normalizeSettings,
} from './indicator.js';

function generateCandles(count, defaultBody = 10, defaultVolume = 100) {
  const candles = [];
  for (let i = 0; i < count; i++) {
    candles.push({
      time: 1700000000 + i * 3600,
      open: 100,
      high: 120,
      low: 80,
      close: 100 + defaultBody,
      volume: defaultVolume,
      confirmed: true,
    });
  }
  return candles;
}

describe('Abdullah SP1 Indicator Core Tests', () => {

  test('1. SMA Calculation', () => {
    const values = [10, 20, 30, 40, 50];
    const sma3 = calculateSMA(values, 3);
    assert.deepEqual(sma3, [null, null, 20, 30, 40]);

    const smaInvalid = calculateSMA(values, 0);
    assert.deepEqual(smaInvalid, [null, null, null, null, null]);

    const smaShort = calculateSMA([10], 5);
    assert.deepEqual(smaShort, [null]);
  });

  test('2. Settings Normalization & Backward Compatibility', () => {
    const s1 = normalizeSettings({ spreadLen: 15, smallFactor: 0.8, showDemand: false, showSupply: true });
    assert.equal(s1.spreadLen, 15);
    assert.equal(s1.smallFactor, 0.8);
    assert.equal(s1.showDemand, false);
    assert.equal(s1.showSupply, true);

    // Fallback to legacy names
    const s2 = normalizeSettings({ lookbackLength: 25, sensitivity: 1.2, showSignalA: true, showSignalB: false });
    assert.equal(s2.spreadLen, 25);
    assert.equal(s2.smallFactor, 1.2);
    assert.equal(s2.showDemand, true);
    assert.equal(s2.showSupply, false);
  });

  test('3. Bullish No Demand (BUY Signal)', () => {
    const candles = generateCandles(20, 10, 100);

    // Setup volume pattern for last 3 bars: bar17=100, bar18=90, bar19=80
    candles[17].volume = 100;
    candles[18].volume = 90;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      high: 110,
      low: 95,
      close: 105, // Bullish, bodySpread = 5 < avgSpread (10 * 1.0)
      volume: 80, // 80 < 90 AND 80 < 100
      confirmed: true,
    };

    const res = calculateSignal(candles);
    assert.equal(res.signal, 'BUY');
    assert.equal(res.metrics.isBullish, true);
    assert.equal(res.metrics.lowVolume, true);
    assert.equal(res.metrics.smallBody, true);
    assert.equal(res.metrics.validDemand, true);
  });

  test('4. Bearish No Supply (SELL Signal)', () => {
    const candles = generateCandles(20, 10, 100);

    candles[17].volume = 100;
    candles[18].volume = 90;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      high: 105,
      low: 90,
      close: 95, // Bearish, bodySpread = 5 < avgSpread (10)
      volume: 80, // 80 < 90 AND 80 < 100
      confirmed: true,
    };

    const res = calculateSignal(candles);
    assert.equal(res.signal, 'SELL');
    assert.equal(res.metrics.isBearish, true);
    assert.equal(res.metrics.lowVolume, true);
    assert.equal(res.metrics.smallBody, true);
    assert.equal(res.metrics.validSupply, true);
  });

  test('5. High Volume Rejection', () => {
    const candles = generateCandles(20, 10, 100);

    candles[17].volume = 100;
    candles[18].volume = 90;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      close: 105,
      volume: 95, // Rejection: 95 is NOT < 90
      confirmed: true,
    };

    const res = calculateSignal(candles);
    assert.equal(res.signal, 'NONE');
    assert.equal(res.metrics.lowVolume, false);
  });

  test('6. Body Too Large Rejection', () => {
    const candles = generateCandles(20, 10, 100);

    candles[17].volume = 100;
    candles[18].volume = 90;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      close: 115, // bodySpread = 15 >= avgSpread (approx 10 * 1.0)
      volume: 80,
      confirmed: true,
    };

    const res = calculateSignal(candles);
    assert.equal(res.signal, 'NONE');
    assert.equal(res.metrics.smallBody, false);
  });

  test('7. Insufficient SMA History', () => {
    const candles = generateCandles(5, 10, 100);
    const res = calculateSignal(candles, { spreadLen: 20 });

    assert.equal(res.signal, 'NONE');
    assert.ok(res.reason.includes('Insufficient candle history'));
  });

  test('8. Unconfirmed Candle Rejection', () => {
    const candles = generateCandles(20, 10, 100);

    candles[17].volume = 100;
    candles[18].volume = 90;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      close: 105,
      volume: 80,
      confirmed: false, // Forming MT5 candle must NEVER produce signal
    };

    const res = calculateSignal(candles);
    assert.equal(res.signal, 'NONE');
    assert.equal(res.metrics.isConfirmed, false);
    assert.equal(res.metrics.validDemand, false);
  });

  test('9. showDemand = false Rejection', () => {
    const candles = generateCandles(20, 10, 100);

    candles[17].volume = 100;
    candles[18].volume = 90;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      close: 105,
      volume: 80,
      confirmed: true,
    };

    const res = calculateSignal(candles, { showDemand: false });
    assert.equal(res.signal, 'NONE');
    assert.equal(res.metrics.noDemand, false);
  });

  test('10. showSupply = false Rejection', () => {
    const candles = generateCandles(20, 10, 100);

    candles[17].volume = 100;
    candles[18].volume = 90;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      close: 95,
      volume: 80,
      confirmed: true,
    };

    const res = calculateSignal(candles, { showSupply: false });
    assert.equal(res.signal, 'NONE');
    assert.equal(res.metrics.noSupply, false);
  });

  test('11. Exact Boundary Behavior for Body Spread Threshold', () => {
    // 20 candles with bodySpread = 10 (avgSpread = 10)
    const candles = generateCandles(20, 10, 100);

    candles[17].volume = 100;
    candles[18].volume = 90;

    // Case A: bodySpread == avgSpread (10 == 10). Condition is bodySpread < avgSpread * smallFactor.
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      close: 110, // bodySpread = 10
      volume: 80,
      confirmed: true,
    };
    const resExact = calculateSignal(candles, { smallFactor: 1.0 });
    assert.equal(resExact.metrics.smallBody, false);
    assert.equal(resExact.signal, 'NONE');

    // Case B: bodySpread = 9.99 < 10. Condition bodySpread < avgSpread * smallFactor is true.
    candles[19].close = 109.99;
    const resBelow = calculateSignal(candles, { smallFactor: 1.0 });
    assert.equal(resBelow.metrics.smallBody, true);
    assert.equal(resBelow.signal, 'BUY');
  });

  test('12. Detailed Volume Comparisons (vol < vol[1] AND vol < vol[2])', () => {
    const candles = generateCandles(20, 10, 100);
    candles[17].volume = 80;
    candles[18].volume = 100;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      close: 105,
      volume: 90, // 90 < 100 (vol[1]) BUT 90 > 80 (vol[2]) -> Rejection
      confirmed: true,
    };

    const res = calculateSignal(candles);
    assert.equal(res.metrics.lowVolume, false);
    assert.equal(res.signal, 'NONE');
  });

  test('13. calculateFullSeries Verification', () => {
    const candles = generateCandles(20, 10, 100);

    candles[17].volume = 100;
    candles[18].volume = 90;
    candles[19] = {
      time: 1700000000 + 19 * 3600,
      open: 100,
      close: 105,
      volume: 80,
      confirmed: true,
    };

    const series = calculateFullSeries(candles);
    assert.equal(series.length, 20);
    assert.equal(series[19].signal, 'BUY');
    assert.equal(series[0].signal, 'NONE'); // bar 0 index < 2
  });

});
