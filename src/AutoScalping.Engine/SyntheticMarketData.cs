using AutoScalping.Domain;

namespace AutoScalping.Engine;

public static class SyntheticMarketData
{
    public static IReadOnlyList<Candle> Generate(int count = 4_000, int seed = 20261014)
    {
        var random = new Random(seed);
        var candles = new List<Candle>(count);
        var time = new DateTimeOffset(2026, 1, 5, 0, 0, 0, TimeSpan.Zero);
        decimal price = 2_650m;

        for (var i = 0; i < count; i++)
        {
            var regime = (i / 420) % 4;
            var drift = regime switch
            {
                0 => 0.035m,
                1 => -0.028m,
                2 => 0.006m,
                _ => 0.045m
            };
            var cycle = (decimal)Math.Sin(i / 13d) * 0.075m;
            var shock = ((decimal)random.NextDouble() - 0.5m) * (regime == 2 ? 0.75m : 0.45m);
            var open = price;
            var close = Math.Max(100m, open + drift + cycle + shock);
            var wick = 0.08m + ((decimal)random.NextDouble() * 0.28m);
            var high = Math.Max(open, close) + wick;
            var low = Math.Min(open, close) - wick;
            var spread = 12m + random.Next(0, 12);
            candles.Add(new Candle(time, open, high, low, close, random.Next(80, 800), spread));
            price = close;
            time = time.AddMinutes(1);
        }

        return candles;
    }
}
