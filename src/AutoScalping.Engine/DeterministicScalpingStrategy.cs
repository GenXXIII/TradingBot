using AutoScalping.Domain;

namespace AutoScalping.Engine;

public sealed class DeterministicScalpingStrategy(StrategySettings settings)
{
    private readonly StrategySettings _settings = settings;

    public int RequiredSignalBars => Math.Max(_settings.SlowEmaPeriod, _settings.AdxPeriod * 2) + 2;
    public int RequiredTrendBars => _settings.TrendSlowEmaPeriod + 2;

    public StrategySignal Evaluate(IReadOnlyList<Candle> signalCandles, IReadOnlyList<Candle> trendCandles)
    {
        var lastTime = signalCandles.Count == 0 ? DateTimeOffset.MinValue : signalCandles[^1].OpenTime;
        if (signalCandles.Count < RequiredSignalBars || trendCandles.Count < RequiredTrendBars)
        {
            return StrategySignal.Hold(lastTime, "Warm-up: not enough closed bars");
        }

        var last = signalCandles[^1];
        if (last.SpreadPoints > _settings.MaximumSpreadPoints)
        {
            return StrategySignal.Hold(last.OpenTime, "Spread exceeds configured maximum");
        }

        var closes = signalCandles.Select(x => x.Close).ToArray();
        var priorCloses = closes[..^1];
        var trendCloses = trendCandles.Select(x => x.Close).ToArray();
        var fast = Indicators.Ema(closes, _settings.FastEmaPeriod);
        var priorFast = Indicators.Ema(priorCloses, _settings.FastEmaPeriod);
        var slow = Indicators.Ema(closes, _settings.SlowEmaPeriod);
        var trendFast = Indicators.Ema(trendCloses, _settings.TrendFastEmaPeriod);
        var trendSlow = Indicators.Ema(trendCloses, _settings.TrendSlowEmaPeriod);
        var rsi = Indicators.Rsi(closes, _settings.RsiPeriod);
        var atr = Indicators.Atr(signalCandles, _settings.AtrPeriod);
        var adx = Indicators.Adx(signalCandles, _settings.AdxPeriod);
        var snapshot = new IndicatorSnapshot(fast, slow, trendFast, trendSlow, rsi, atr, adx);

        if (atr <= 0 || adx < _settings.MinimumAdx)
        {
            return StrategySignal.Hold(last.OpenTime, "Trend strength or volatility filter not satisfied", snapshot);
        }

        var previous = signalCandles[^2];
        var longTrend = fast > slow && trendFast > trendSlow;
        var shortTrend = fast < slow && trendFast < trendSlow;
        var bullishPullbackRecovery = previous.Close <= priorFast && last.Close > fast && last.Close > last.Open;
        var bearishPullbackRecovery = previous.Close >= priorFast && last.Close < fast && last.Close < last.Open;

        if (_settings.EnableLong && longTrend && bullishPullbackRecovery &&
            rsi >= _settings.LongRsiMinimum && rsi <= _settings.LongRsiMaximum)
        {
            return new StrategySignal(
                SignalAction.Buy,
                last.OpenTime,
                last.Close,
                last.Close - (atr * _settings.StopAtrMultiple),
                last.Close + (atr * _settings.TargetAtrMultiple),
                snapshot,
                ["M1 EMA trend is bullish", "M5 EMA trend confirms", "Pullback recovered above fast EMA", "RSI and ADX filters passed"]);
        }

        if (_settings.EnableShort && shortTrend && bearishPullbackRecovery &&
            rsi >= _settings.ShortRsiMinimum && rsi <= _settings.ShortRsiMaximum)
        {
            return new StrategySignal(
                SignalAction.Sell,
                last.OpenTime,
                last.Close,
                last.Close + (atr * _settings.StopAtrMultiple),
                last.Close - (atr * _settings.TargetAtrMultiple),
                snapshot,
                ["M1 EMA trend is bearish", "M5 EMA trend confirms", "Pullback rejected below fast EMA", "RSI and ADX filters passed"]);
        }

        return StrategySignal.Hold(last.OpenTime, "No fully confirmed closed-bar setup", snapshot);
    }
}
