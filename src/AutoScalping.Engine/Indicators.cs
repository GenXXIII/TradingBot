using AutoScalping.Domain;

namespace AutoScalping.Engine;

public static class Indicators
{
    public static decimal Ema(IReadOnlyList<decimal> values, int period)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(period, 2);
        if (values.Count < period)
        {
            throw new ArgumentException("Not enough values for EMA.", nameof(values));
        }

        var multiplier = 2m / (period + 1m);
        var ema = values.Take(period).Average();
        for (var i = period; i < values.Count; i++)
        {
            ema = ((values[i] - ema) * multiplier) + ema;
        }

        return ema;
    }

    public static decimal Rsi(IReadOnlyList<decimal> closes, int period)
    {
        if (closes.Count < period + 1)
        {
            throw new ArgumentException("Not enough values for RSI.", nameof(closes));
        }

        decimal gains = 0;
        decimal losses = 0;
        var start = closes.Count - period;
        for (var i = start; i < closes.Count; i++)
        {
            var change = closes[i] - closes[i - 1];
            if (change >= 0)
            {
                gains += change;
            }
            else
            {
                losses -= change;
            }
        }

        if (losses == 0)
        {
            return gains == 0 ? 50m : 100m;
        }

        var relativeStrength = gains / losses;
        return 100m - (100m / (1m + relativeStrength));
    }

    public static decimal Atr(IReadOnlyList<Candle> candles, int period)
    {
        if (candles.Count < period + 1)
        {
            throw new ArgumentException("Not enough candles for ATR.", nameof(candles));
        }

        decimal total = 0;
        var start = candles.Count - period;
        for (var i = start; i < candles.Count; i++)
        {
            var current = candles[i];
            var previousClose = candles[i - 1].Close;
            var trueRange = Math.Max(
                current.High - current.Low,
                Math.Max(Math.Abs(current.High - previousClose), Math.Abs(current.Low - previousClose)));
            total += trueRange;
        }

        return total / period;
    }

    public static decimal Adx(IReadOnlyList<Candle> candles, int period)
    {
        if (candles.Count < (period * 2) + 1)
        {
            throw new ArgumentException("Not enough candles for ADX.", nameof(candles));
        }

        var dxValues = new List<decimal>();
        var start = candles.Count - (period * 2);
        for (var windowStart = start; windowStart < candles.Count - period; windowStart++)
        {
            decimal trueRange = 0;
            decimal plusDm = 0;
            decimal minusDm = 0;
            for (var i = windowStart + 1; i <= windowStart + period; i++)
            {
                var upMove = candles[i].High - candles[i - 1].High;
                var downMove = candles[i - 1].Low - candles[i].Low;
                plusDm += upMove > downMove && upMove > 0 ? upMove : 0;
                minusDm += downMove > upMove && downMove > 0 ? downMove : 0;
                trueRange += Math.Max(
                    candles[i].High - candles[i].Low,
                    Math.Max(
                        Math.Abs(candles[i].High - candles[i - 1].Close),
                        Math.Abs(candles[i].Low - candles[i - 1].Close)));
            }

            if (trueRange == 0)
            {
                dxValues.Add(0);
                continue;
            }

            var plusDi = 100m * plusDm / trueRange;
            var minusDi = 100m * minusDm / trueRange;
            var sum = plusDi + minusDi;
            dxValues.Add(sum == 0 ? 0 : 100m * Math.Abs(plusDi - minusDi) / sum);
        }

        return dxValues.Count == 0 ? 0 : dxValues.Average();
    }

    public static IReadOnlyList<Candle> Aggregate(IReadOnlyList<Candle> candles, int barsPerGroup)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(barsPerGroup, 1);
        var result = new List<Candle>();
        for (var i = 0; i + barsPerGroup <= candles.Count; i += barsPerGroup)
        {
            var group = candles.Skip(i).Take(barsPerGroup).ToArray();
            result.Add(new Candle(
                group[0].OpenTime,
                group[0].Open,
                group.Max(x => x.High),
                group.Min(x => x.Low),
                group[^1].Close,
                group.Sum(x => x.TickVolume),
                group.Average(x => x.SpreadPoints)));
        }

        return result;
    }
}
