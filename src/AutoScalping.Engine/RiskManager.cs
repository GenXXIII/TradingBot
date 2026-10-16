using AutoScalping.Domain;

namespace AutoScalping.Engine;

public sealed class RiskManager(RiskSettings settings)
{
    private readonly RiskSettings _settings = settings;

    public RiskDecision Evaluate(StrategySignal signal, RiskContext context)
    {
        if (context.Mode != BotMode.Running)
        {
            return new RiskDecision(false, 0, $"Bot mode is {context.Mode}");
        }

        if (signal.Action == SignalAction.Hold)
        {
            return new RiskDecision(false, 0, "No entry signal");
        }

        if (context.HasOpenPosition)
        {
            return new RiskDecision(false, 0, "Only one bot position is allowed");
        }

        if (context.TradesToday >= _settings.MaximumTradesPerDay)
        {
            return new RiskDecision(false, 0, "Daily trade limit reached");
        }

        var dailyLossLimit = context.Balance * (_settings.MaximumDailyLossPercent / 100m);
        if (context.DailyRealizedPnl <= -dailyLossLimit)
        {
            return new RiskDecision(false, 0, "Daily loss circuit breaker is active");
        }

        var drawdown = context.PeakEquity <= 0 ? 0 :
            100m * (context.PeakEquity - context.Equity) / context.PeakEquity;
        if (drawdown >= _settings.MaximumDrawdownPercent)
        {
            return new RiskDecision(false, 0, "Maximum drawdown circuit breaker is active");
        }

        var stopDistance = Math.Abs(signal.Entry - signal.StopLoss);
        var stopPoints = stopDistance / _settings.PointSize;
        if (stopPoints <= 0)
        {
            return new RiskDecision(false, 0, "Stop distance is invalid");
        }

        var riskAmount = context.Balance * (_settings.RiskPerTradePercent / 100m);
        var rawLots = riskAmount / (stopPoints * _settings.CurrencyPerPointPerLot);
        var steppedLots = Math.Floor(rawLots / _settings.LotStep) * _settings.LotStep;
        var lots = Math.Clamp(steppedLots, _settings.MinimumLot, _settings.MaximumLot);
        if (lots <= 0)
        {
            return new RiskDecision(false, 0, "Calculated volume is below the broker minimum");
        }

        return new RiskDecision(true, lots, "All pre-trade risk checks passed");
    }
}
