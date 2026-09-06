/**
 * PROPRIETARY ABDULLAH SP1 INDICATOR ENGINE
 * SECRET SERVER-SIDE IMPLEMENTATION
 */

export const DEFAULT_SETTINGS = {
  spreadLen: 20,
  smallFactor: 1.0,
  showDemand: true,
  showSupply: true,
};

export function normalizeSettings(custom = {}) {
  return {
    spreadLen: Math.max(1, Math.floor(custom.spreadLen ?? custom.lookbackLength ?? DEFAULT_SETTINGS.spreadLen)),
    smallFactor: Math.max(0.01, custom.smallFactor ?? custom.sensitivity ?? DEFAULT_SETTINGS.smallFactor),
    showDemand: custom.showDemand ?? custom.showSignalA ?? DEFAULT_SETTINGS.showDemand,
    showSupply: custom.showSupply ?? custom.showSignalB ?? DEFAULT_SETTINGS.showSupply,
  };
}

export function calculateSMA(values, period) {
  const result = new Array(values.length).fill(null);
  if (!Array.isArray(values) || period <= 0 || values.length < period) return result;

  let sum = 0;
  for (let i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) {
      sum -= values[i - period];
    }
    if (i >= period - 1) {
      result[i] = sum / period;
    }
  }
  return result;
}

export function calculateSignal(candles, customSettings = {}) {
  if (!Array.isArray(candles) || candles.length === 0) {
    return { signal: 'NONE', reason: 'No candle data provided' };
  }

  const settings = normalizeSettings(customSettings);

  if (candles.length < settings.spreadLen) {
    return {
      signal: 'NONE',
      reason: `Insufficient candle history (${candles.length} candles provided, ${settings.spreadLen} required)`,
    };
  }

  const bodySpreads = candles.map((c) => Math.abs(c.close - c.open));
  const smaValues = calculateSMA(bodySpreads, settings.spreadLen);

  const lastIdx = candles.length - 1;
  const targetCandle = candles[lastIdx];

  if (lastIdx < 2) {
    return { signal: 'NONE', reason: 'Bar index must be >= 2 for lowVolume check' };
  }

  const lowVolume =
    targetCandle.volume < candles[lastIdx - 1].volume &&
    targetCandle.volume < candles[lastIdx - 2].volume;

  const avgSpread = smaValues[lastIdx];
  const bodySpread = bodySpreads[lastIdx];
  const smallBody = avgSpread !== null ? bodySpread < avgSpread * settings.smallFactor : false;

  const isBullish = targetCandle.close > targetCandle.open;
  const isBearish = targetCandle.close < targetCandle.open;
  const isConfirmed = targetCandle.confirmed !== undefined ? Boolean(targetCandle.confirmed) : true;

  const noDemand = Boolean(settings.showDemand) && lowVolume && smallBody && isBullish;
  const noSupply = Boolean(settings.showSupply) && lowVolume && smallBody && isBearish;

  const validDemand = noDemand && isConfirmed;
  const validSupply = noSupply && isConfirmed;

  let signal = 'NONE';
  if (validDemand) signal = 'BUY';
  else if (validSupply) signal = 'SELL';

  return {
    signal,
    timestamp: targetCandle.time,
    close: targetCandle.close,
    open: targetCandle.open,
    volume: targetCandle.volume,
    metrics: {
      bodySpread,
      avgSpread,
      smallFactor: settings.smallFactor,
      spreadThreshold: avgSpread !== null ? avgSpread * settings.smallFactor : null,
      lowVolume,
      smallBody,
      isBullish,
      isBearish,
      isConfirmed,
      noDemand,
      noSupply,
      validDemand,
      validSupply,
    },
  };
}

export function calculateFullSeries(candles, customSettings = {}) {
  if (!Array.isArray(candles) || candles.length === 0) return [];
  const settings = normalizeSettings(customSettings);

  const bodySpreads = candles.map((c) => Math.abs(c.close - c.open));
  const smaValues = calculateSMA(bodySpreads, settings.spreadLen);

  return candles.map((c, i) => {
    const lowVolume = i >= 2 && c.volume < candles[i - 1].volume && c.volume < candles[i - 2].volume;
    const avgSpread = smaValues[i];
    const bodySpread = bodySpreads[i];
    const smallBody = avgSpread !== null ? bodySpread < avgSpread * settings.smallFactor : false;
    const isBullish = c.close > c.open;
    const isBearish = c.close < c.open;
    const isConfirmed = c.confirmed !== undefined ? Boolean(c.confirmed) : true;

    const noDemand = Boolean(settings.showDemand) && lowVolume && smallBody && isBullish;
    const noSupply = Boolean(settings.showSupply) && lowVolume && smallBody && isBearish;

    const validDemand = noDemand && isConfirmed;
    const validSupply = noSupply && isConfirmed;

    let signal = 'NONE';
    if (validDemand) signal = 'BUY';
    else if (validSupply) signal = 'SELL';

    return {
      index: i,
      time: c.time,
      open: c.open,
      high: c.high,
      low: c.low,
      close: c.close,
      volume: c.volume,
      bodySpread,
      avgSpread,
      lowVolume,
      smallBody,
      isBullish,
      isBearish,
      isConfirmed,
      noDemand,
      noSupply,
      validDemand,
      validSupply,
      signal,
    };
  });
}