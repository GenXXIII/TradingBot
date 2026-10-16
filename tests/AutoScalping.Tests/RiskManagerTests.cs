using AutoScalping.Domain;
using AutoScalping.Engine;

namespace AutoScalping.Tests;

public sealed class RiskManagerTests
{
    private static readonly StrategySignal BuySignal = new(
        SignalAction.Buy,
        DateTimeOffset.UtcNow,
        2_650m,
        2_648m,
        2_653m,
        null,
        ["test"]);

    [Fact]
    public void Paused_mode_rejects_an_entry()
    {
        var manager = new RiskManager(new RiskSettings());
        var decision = manager.Evaluate(BuySignal, Context(BotMode.Paused));

        Assert.False(decision.Allowed);
        Assert.Contains("Paused", decision.Reason);
    }

    [Fact]
    public void Daily_loss_limit_rejects_an_entry()
    {
        var manager = new RiskManager(new RiskSettings());
        var context = Context(BotMode.Running) with { DailyRealizedPnl = -151m };

        var decision = manager.Evaluate(BuySignal, context);

        Assert.False(decision.Allowed);
        Assert.Contains("Daily loss", decision.Reason);
    }

    [Fact]
    public void Valid_entry_is_sized_from_stop_distance()
    {
        var manager = new RiskManager(new RiskSettings());

        var decision = manager.Evaluate(BuySignal, Context(BotMode.Running));

        Assert.True(decision.Allowed);
        Assert.Equal(0.12m, decision.VolumeLots);
    }

    private static RiskContext Context(BotMode mode) =>
        new(10_000m, 10_000m, 10_000m, 0m, 0, false, mode);
}
