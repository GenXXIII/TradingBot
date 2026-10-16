using AutoScalping.Domain;

namespace AutoScalping.Engine;

public sealed class BacktestEngine(StrategySettings strategySettings, RiskSettings riskSettings)
{
    private readonly StrategySettings _strategySettings = strategySettings;
    private readonly RiskSettings _riskSettings = riskSettings;
    private readonly DeterministicScalpingStrategy _strategy = new(strategySettings);
    private readonly RiskManager _risk = new(riskSettings);

    public BacktestResult Run(IReadOnlyList<Candle> candles, string dataset)
    {
        if (candles.Count < 400)
        {
            throw new ArgumentException("A backtest requires at least 400 one-minute candles.", nameof(candles));
        }

        var ordered = candles.OrderBy(x => x.OpenTime).ToArray();
        var trades = new List<SimulatedTrade>();
        var equityCurve = new List<EquityPoint>();
        var balance = _riskSettings.StartingBalance;
        var peakEquity = balance;
        var currentDay = DateOnly.FromDateTime(ordered[0].OpenTime.UtcDateTime);
        decimal dailyPnl = 0;
        var tradesToday = 0;
        var cooldownUntil = -1;
        OpenTrade? open = null;

        for (var i = 260; i < ordered.Length; i++)
        {
            var bar = ordered[i];
            var day = DateOnly.FromDateTime(bar.OpenTime.UtcDateTime);
            if (day != currentDay)
            {
                currentDay = day;
                dailyPnl = 0;
                tradesToday = 0;
            }

            if (open is not null)
            {
                var exit = ResolveExit(open, bar, false);
                if (exit is not null)
                {
                    var trade = CloseTrade(open, bar.OpenTime, exit.Value.Price, exit.Value.Reason, trades.Count + 1);
                    trades.Add(trade);
                    balance += trade.NetPnl;
                    dailyPnl += trade.NetPnl;
                    open = null;
                    cooldownUntil = i + _strategySettings.CooldownBars;
                }
            }

            if (open is null && i >= cooldownUntil)
            {
                var signalCandles = ordered.Take(i + 1).ToArray();
                var trendCandles = Indicators.Aggregate(signalCandles, 5);
                var signal = _strategy.Evaluate(signalCandles, trendCandles);
                var decision = _risk.Evaluate(signal, new RiskContext(
                    balance,
                    balance,
                    peakEquity,
                    dailyPnl,
                    tradesToday,
                    false,
                    BotMode.Running));

                if (decision.Allowed)
                {
                    open = Open(signal, decision.VolumeLots, bar.SpreadPoints);
                    tradesToday++;
                }
            }

            var equity = balance + (open is null ? 0 : Unrealized(open, bar.Close));
            peakEquity = Math.Max(peakEquity, equity);
            equityCurve.Add(new EquityPoint(bar.OpenTime, decimal.Round(equity, 2)));
        }

        if (open is not null)
        {
            var last = ordered[^1];
            var exit = ResolveExit(open, last, true)!.Value;
            var trade = CloseTrade(open, last.OpenTime, exit.Price, exit.Reason, trades.Count + 1);
            trades.Add(trade);
            balance += trade.NetPnl;
            equityCurve.Add(new EquityPoint(last.OpenTime, decimal.Round(balance, 2)));
        }

        var metrics = CalculateMetrics(trades, equityCurve, _riskSettings.StartingBalance);
        return new BacktestResult(
            dataset,
            ordered[0].OpenTime,
            ordered[^1].OpenTime,
            metrics,
            trades,
            equityCurve,
            [
                "Synthetic validation is a software check, not evidence of live profitability.",
            "Run the EA in MT5 Strategy Tester with your broker's symbol data, then forward-test on demo.",
                "Intrabar stop/target collisions are resolved against the strategy (stop first)."
            ]);
    }

    private OpenTrade Open(StrategySignal signal, decimal lots, decimal spreadPoints)
    {
        var halfSpread = (spreadPoints * _riskSettings.PointSize) / 2m;
        var slippage = _riskSettings.SlippagePoints * _riskSettings.PointSize;
        var side = signal.Action == SignalAction.Buy ? TradeSide.Long : TradeSide.Short;
        var fill = side == TradeSide.Long
            ? signal.Entry + halfSpread + slippage
            : signal.Entry - halfSpread - slippage;
        var stopDistance = Math.Abs(signal.Entry - signal.StopLoss);
        var targetDistance = Math.Abs(signal.TakeProfit - signal.Entry);
        var stop = side == TradeSide.Long ? fill - stopDistance : fill + stopDistance;
        var target = side == TradeSide.Long ? fill + targetDistance : fill - targetDistance;
        return new OpenTrade(side, signal.BarTime, fill, stop, target, lots);
    }

    private (decimal Price, string Reason)? ResolveExit(OpenTrade position, Candle bar, bool force)
    {
        var halfSpread = (bar.SpreadPoints * _riskSettings.PointSize) / 2m;
        var slippage = _riskSettings.SlippagePoints * _riskSettings.PointSize;
        if (position.Side == TradeSide.Long)
        {
            if (bar.Low <= position.StopLoss)
            {
                return (position.StopLoss - halfSpread - slippage, "stop-loss");
            }

            if (bar.High >= position.TakeProfit)
            {
                return (position.TakeProfit - halfSpread - slippage, "take-profit");
            }

            return force ? (bar.Close - halfSpread - slippage, "end-of-test") : null;
        }

        if (bar.High >= position.StopLoss)
        {
            return (position.StopLoss + halfSpread + slippage, "stop-loss");
        }

        if (bar.Low <= position.TakeProfit)
        {
            return (position.TakeProfit + halfSpread + slippage, "take-profit");
        }

        return force ? (bar.Close + halfSpread + slippage, "end-of-test") : null;
    }

    private SimulatedTrade CloseTrade(OpenTrade position, DateTimeOffset time, decimal exit, string reason, int number)
    {
        var direction = position.Side == TradeSide.Long ? 1m : -1m;
        var points = ((exit - position.EntryPrice) / _riskSettings.PointSize) * direction;
        var gross = points * _riskSettings.CurrencyPerPointPerLot * position.VolumeLots;
        var costs = _riskSettings.CommissionPerLotRoundTrip * position.VolumeLots;
        return new SimulatedTrade(
            number,
            position.Side,
            position.EntryTime,
            time,
            decimal.Round(position.EntryPrice, 3),
            decimal.Round(exit, 3),
            position.VolumeLots,
            decimal.Round(gross, 2),
            decimal.Round(costs, 2),
            decimal.Round(gross - costs, 2),
            reason);
    }

    private decimal Unrealized(OpenTrade position, decimal mark)
    {
        var direction = position.Side == TradeSide.Long ? 1m : -1m;
        var points = ((mark - position.EntryPrice) / _riskSettings.PointSize) * direction;
        return points * _riskSettings.CurrencyPerPointPerLot * position.VolumeLots;
    }

    private static BacktestMetrics CalculateMetrics(
        IReadOnlyList<SimulatedTrade> trades,
        IReadOnlyList<EquityPoint> curve,
        decimal startingBalance)
    {
        var winners = trades.Where(x => x.NetPnl > 0).ToArray();
        var losers = trades.Where(x => x.NetPnl <= 0).ToArray();
        var net = trades.Sum(x => x.NetPnl);
        var grossProfit = winners.Sum(x => x.NetPnl);
        var grossLoss = Math.Abs(losers.Sum(x => x.NetPnl));
        decimal peak = startingBalance;
        decimal maxDrawdown = 0;
        foreach (var point in curve)
        {
            peak = Math.Max(peak, point.Equity);
            if (peak > 0)
            {
                maxDrawdown = Math.Max(maxDrawdown, 100m * (peak - point.Equity) / peak);
            }
        }

        return new BacktestMetrics(
            trades.Count,
            winners.Length,
            losers.Length,
            trades.Count == 0 ? 0 : decimal.Round(100m * winners.Length / trades.Count, 2),
            decimal.Round(net, 2),
            grossLoss == 0 ? (grossProfit > 0 ? 99m : 0m) : decimal.Round(grossProfit / grossLoss, 2),
            trades.Count == 0 ? 0 : decimal.Round(net / trades.Count, 2),
            decimal.Round(maxDrawdown, 2),
            decimal.Round(100m * net / startingBalance, 2));
    }

    private sealed record OpenTrade(
        TradeSide Side,
        DateTimeOffset EntryTime,
        decimal EntryPrice,
        decimal StopLoss,
        decimal TakeProfit,
        decimal VolumeLots);
}
