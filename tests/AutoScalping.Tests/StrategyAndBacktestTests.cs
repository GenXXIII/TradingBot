using AutoScalping.Domain;
using AutoScalping.Engine;

namespace AutoScalping.Tests;

public sealed class StrategyAndBacktestTests
{
    [Fact]
    public void Strategy_waits_for_closed_bar_warmup()
    {
        var strategy = new DeterministicScalpingStrategy(new StrategySettings());
        var candles = SyntheticMarketData.Generate(40);

        var result = strategy.Evaluate(candles, Indicators.Aggregate(candles, 5));

        Assert.Equal(SignalAction.Hold, result.Action);
        Assert.Contains("Warm-up", result.Reasons.Single());
    }

    [Fact]
    public void Synthetic_generation_is_reproducible()
    {
        var first = SyntheticMarketData.Generate(500, 42);
        var second = SyntheticMarketData.Generate(500, 42);

        Assert.Equal(first, second);
    }

    [Fact]
    public void Backtest_is_deterministic_and_includes_cost_warnings()
    {
        var engine = new BacktestEngine(new StrategySettings(), new RiskSettings());
        var candles = SyntheticMarketData.Generate(1_200, 99);

        var first = engine.Run(candles, "test");
        var second = engine.Run(candles, "test");

        Assert.Equal(first.Metrics, second.Metrics);
        Assert.NotEmpty(first.EquityCurve);
        Assert.Contains(first.Warnings, warning => warning.Contains("not evidence", StringComparison.OrdinalIgnoreCase));
    }
}
