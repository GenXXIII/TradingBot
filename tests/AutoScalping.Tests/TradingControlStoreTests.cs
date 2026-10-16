using AutoScalping.Api;
using AutoScalping.Domain;
using Microsoft.Extensions.Configuration;

namespace AutoScalping.Tests;

public sealed class TradingControlStoreTests
{
    [Fact]
    public void Start_requires_fresh_allowed_account_telemetry()
    {
        var store = CreateStore();

        var disconnected = store.Issue("start");
        store.UpdateTelemetry(new Mt5Telemetry { AccountMode = "demo", TerminalId = "test", MtfReady = true });
        var demo = store.Issue("start");

        Assert.False(disconnected.Accepted);
        Assert.True(demo.Accepted);
        Assert.Equal(BotMode.Running, demo.Command.Mode);
        Assert.Equal(StrategyProfile.Normal, demo.Command.Profile);
    }

    [Theory]
    [InlineData("start")]
    [InlineData("start-instant")]
    public void Automatic_start_waits_for_all_timeframe_history(string command)
    {
        var store = CreateStore();
        store.UpdateTelemetry(new Mt5Telemetry
        {
            AccountMode = "demo",
            TerminalId = "test",
            MtfSummary = "Waiting for closed D1 EMA history"
        });

        var result = store.Issue(command);

        Assert.False(result.Accepted);
        Assert.Contains("D1", result.Message);
        Assert.Equal(BotMode.Paused, result.Command.Mode);
    }

    [Fact]
    public void Real_account_needs_independent_api_gate()
    {
        var blockedStore = CreateStore();
        blockedStore.UpdateTelemetry(new Mt5Telemetry { AccountMode = "real", TerminalId = "real-test", MtfReady = true });
        var blocked = blockedStore.Issue("start");

        var allowedStore = CreateStore(allowRealControl: true);
        allowedStore.UpdateTelemetry(new Mt5Telemetry { AccountMode = "real", TerminalId = "real-test", MtfReady = true });
        var allowed = allowedStore.Issue("start");

        Assert.False(blocked.Accepted);
        Assert.True(allowed.Accepted);
    }

    [Fact]
    public void Emergency_lock_rejects_start_until_reset()
    {
        var store = CreateStore();
        store.UpdateTelemetry(new Mt5Telemetry { AccountMode = "demo", TerminalId = "test", MtfReady = true });

        var locked = store.Issue("emergency-stop");
        var rejected = store.Issue("start");
        var reset = store.Issue("reset-lock");

        Assert.Equal(BotMode.Locked, locked.Command.Mode);
        Assert.False(rejected.Accepted);
        Assert.True(reset.Accepted);
        Assert.Equal(BotMode.Paused, reset.Command.Mode);
    }

    [Fact]
    public void Instant_scalp_starts_only_on_demo_and_sets_explicit_profile()
    {
        var demoStore = CreateStore();
        demoStore.UpdateTelemetry(new Mt5Telemetry { AccountMode = "demo", TerminalId = "demo-test", MtfReady = true });

        var instant = demoStore.Issue("start-instant");

        Assert.True(instant.Accepted);
        Assert.Equal(BotMode.Running, instant.Command.Mode);
        Assert.Equal(StrategyProfile.InstantScalp, instant.Command.Profile);

        var realStore = CreateStore(allowRealControl: true);
        realStore.UpdateTelemetry(new Mt5Telemetry { AccountMode = "real", TerminalId = "real-test", MtfReady = true });

        var blocked = realStore.Issue("start-instant");

        Assert.False(blocked.Accepted);
    }

    [Fact]
    public void Legacy_hybrid_command_routes_to_normal_profile()
    {
        var store = CreateStore();
        store.UpdateTelemetry(new Mt5Telemetry
        {
            AccountMode = "demo",
            TerminalId = "hybrid-test",
            StrategyProfile = StrategyProfile.Hybrid,
            MtfReady = true
        });

        var hybrid = store.Issue("start-hybrid");

        Assert.True(hybrid.Accepted);
        Assert.Equal(BotMode.Running, hybrid.Command.Mode);
        Assert.Equal(StrategyProfile.Normal, hybrid.Command.Profile);
    }

    [Fact]
    public void Profile_change_is_blocked_while_a_position_basket_is_open()
    {
        var store = CreateStore();
        store.UpdateTelemetry(new Mt5Telemetry
        {
            AccountMode = "demo",
            TerminalId = "hybrid-test",
            PositionCount = 2,
            PositionSide = TradeSide.Long,
            StrategyProfile = StrategyProfile.Hybrid,
            MtfReady = true
        });

        var changed = store.Issue("start-instant");

        Assert.False(changed.Accepted);
    }

    [Fact]
    public void Legacy_hybrid_telemetry_can_acknowledge_normal_profile()
    {
        var store = CreateStore();
        store.UpdateTelemetry(new Mt5Telemetry
        {
            AccountMode = "demo",
            TerminalId = "hybrid-test",
            StrategyProfile = StrategyProfile.Hybrid,
            MtfReady = true
        });
        store.Issue("start-hybrid");
        store.Issue("emergency-stop");

        var reset = store.Issue("reset-lock");
        store.UpdateTelemetry(new Mt5Telemetry
        {
            AccountMode = "demo",
            StrategyProfile = StrategyProfile.Hybrid,
            LastCommandRevision = reset.Command.Revision
        });

        Assert.Equal(StrategyProfile.Normal, reset.Command.Profile);
        Assert.Equal(OperatorAction.None, store.CurrentCommand.Action);
    }

    [Fact]
    public void Matching_ea_risk_lock_is_reflected_in_dashboard_control_state()
    {
        var store = CreateStore();
        store.UpdateTelemetry(new Mt5Telemetry
        {
            AccountMode = "demo",
            StrategyProfile = StrategyProfile.Hybrid,
            MtfReady = true
        });
        store.Issue("start-hybrid");

        store.UpdateTelemetry(new Mt5Telemetry
        {
            AccountMode = "demo",
            BotMode = BotMode.Locked,
            StrategyProfile = StrategyProfile.Hybrid,
            LastReason = "Daily loss circuit breaker"
        });

        Assert.Equal(StrategyProfile.Normal, store.CurrentCommand.Profile);
        Assert.Equal(BotMode.Locked, store.CurrentCommand.Mode);
        Assert.Contains(store.Audit, entry => entry.Event == "ea-risk-lock");
    }

    [Fact]
    public void Persisted_legacy_hybrid_profile_is_migrated_to_normal()
    {
        var statePath = Path.Combine(Path.GetTempPath(), "autoscalper-tests", Guid.NewGuid().ToString("N"), "state.json");
        Directory.CreateDirectory(Path.GetDirectoryName(statePath)!);
        File.WriteAllText(
            statePath,
            "{\"Revision\":7,\"Mode\":0,\"SavedAt\":\"2026-10-15T00:00:00+00:00\",\"Profile\":2}");
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["State:Path"] = statePath,
                ["Mt5:AllowRealControl"] = bool.FalseString
            })
            .Build();

        var store = new TradingControlStore(configuration);

        Assert.Equal(StrategyProfile.Normal, store.CurrentCommand.Profile);
        Assert.Contains("\"Profile\":0", File.ReadAllText(statePath));
    }

    private static TradingControlStore CreateStore(bool allowRealControl = false)
    {
        var statePath = Path.Combine(Path.GetTempPath(), "autoscalper-tests", Guid.NewGuid().ToString("N"), "state.json");
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["State:Path"] = statePath,
                ["Mt5:AllowRealControl"] = allowRealControl.ToString()
            })
            .Build();
        return new TradingControlStore(configuration);
    }
}
