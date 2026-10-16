using AutoScalping.Api;
using AutoScalping.Domain;

namespace AutoScalping.Tests;

public sealed class TelemetryParserTests
{
    [Fact]
    public void Parses_mt5_form_telemetry()
    {
        var result = TelemetryParser.Parse(
            "terminal_id=demo-01&account_mode=demo&broker=Exness&symbol=XAUUSDm&balance=10000.25&equity=10002.50&position_side=long&position_count=5&strategy_profile=instantscalp&last_reason=Trade+open&last_command_revision=4");

        Assert.Equal("demo-01", result.TerminalId);
        Assert.Equal("XAUUSDm", result.Symbol);
        Assert.Equal(10_002.50m, result.Equity);
        Assert.Equal(TradeSide.Long, result.PositionSide);
        Assert.Equal(5, result.PositionCount);
        Assert.Equal(StrategyProfile.InstantScalp, result.StrategyProfile);
        Assert.Equal("Trade open", result.LastReason);
        Assert.Equal(4, result.LastCommandRevision);
    }

    [Fact]
    public void Parses_hybrid_profile_case_insensitively()
    {
        var result = TelemetryParser.Parse("strategy_profile=hybrid&position_count=2&last_reason=Nyao+active");

        Assert.Equal(StrategyProfile.Hybrid, result.StrategyProfile);
        Assert.Equal(2, result.PositionCount);
        Assert.Equal("Nyao active", result.LastReason);
    }

    [Fact]
    public void Parses_multi_timeframe_context_and_defaults_missing_flags_to_wait()
    {
        var result = TelemetryParser.Parse(
            "mtf_summary=M1%3ABUY+M5%3ASELL&mtf_ready=true&mtf_fast_buy=true&mtf_fast_sell=false&mtf_normal_buy=true&fast_basket_target_money=150&fast_basket_loss_money=50&fast_basket_initial_risk=47.5");

        Assert.Equal("M1:BUY M5:SELL", result.MtfSummary);
        Assert.True(result.MtfReady);
        Assert.True(result.MtfFastBuy);
        Assert.False(result.MtfFastSell);
        Assert.True(result.MtfNormalBuy);
        Assert.False(result.MtfNormalSell);
        Assert.Equal(150m, result.FastBasketTargetMoney);
        Assert.Equal(50m, result.FastBasketLossMoney);
        Assert.Equal(47.5m, result.FastBasketInitialRisk);
        Assert.False(TelemetryParser.Parse("terminal_id=old-ea").MtfReady);
    }
}
