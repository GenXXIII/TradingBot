using AutoScalping.Domain;
using System.Globalization;

namespace AutoScalping.Api;

public static class TelemetryParser
{
    public static Mt5Telemetry Parse(string body)
    {
        var values = body
            .Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2))
            .Where(parts => parts.Length == 2)
            .ToDictionary(
                parts => Uri.UnescapeDataString(parts[0].Replace('+', ' ')),
                parts => Uri.UnescapeDataString(parts[1].Replace('+', ' ')),
                StringComparer.OrdinalIgnoreCase);

        return new Mt5Telemetry
        {
            TerminalId = Get(values, "terminal_id", "unknown-terminal"),
            AccountMode = Get(values, "account_mode", "unknown"),
            Broker = Get(values, "broker", "unknown"),
            Symbol = Get(values, "symbol", "unknown"),
            Balance = Decimal(values, "balance"),
            Equity = Decimal(values, "equity"),
            DailyPnl = Decimal(values, "daily_pnl"),
            Bid = Decimal(values, "bid"),
            Ask = Decimal(values, "ask"),
            SpreadPoints = Decimal(values, "spread_points"),
            PositionSide = EnumValue(values, "position_side", TradeSide.Flat),
            PositionCount = Integer(values, "position_count"),
            PositionVolume = Decimal(values, "position_volume"),
            PositionEntry = Decimal(values, "position_entry"),
            PositionPnl = Decimal(values, "position_pnl"),
            BotMode = EnumValue(values, "bot_mode", BotMode.Paused),
            StrategyProfile = EnumValue(values, "strategy_profile", StrategyProfile.Normal),
            MtfSummary = Get(values, "mtf_summary", "Waiting for MT5 timeframe context"),
            MtfReady = Boolean(values, "mtf_ready"),
            MtfFastBuy = Boolean(values, "mtf_fast_buy"),
            MtfFastSell = Boolean(values, "mtf_fast_sell"),
            MtfNormalBuy = Boolean(values, "mtf_normal_buy"),
            MtfNormalSell = Boolean(values, "mtf_normal_sell"),
            FastBasketTargetMoney = Decimal(values, "fast_basket_target_money"),
            FastBasketLossMoney = Decimal(values, "fast_basket_loss_money"),
            FastBasketInitialRisk = Decimal(values, "fast_basket_initial_risk"),
            LastReason = Get(values, "last_reason", "No reason reported"),
            LastCommandRevision = Long(values, "last_command_revision")
        };
    }

    private static string Get(IReadOnlyDictionary<string, string> values, string key, string fallback) =>
        values.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value) ? value : fallback;

    private static decimal Decimal(IReadOnlyDictionary<string, string> values, string key) =>
        values.TryGetValue(key, out var value) && decimal.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var result)
            ? result
            : 0;

    private static long Long(IReadOnlyDictionary<string, string> values, string key) =>
        values.TryGetValue(key, out var value) && long.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var result)
            ? result
            : 0;

    private static int Integer(IReadOnlyDictionary<string, string> values, string key) =>
        values.TryGetValue(key, out var value) && int.TryParse(value, NumberStyles.Any, CultureInfo.InvariantCulture, out var result)
            ? result
            : 0;

    private static bool Boolean(IReadOnlyDictionary<string, string> values, string key) =>
        values.TryGetValue(key, out var value) && bool.TryParse(value, out var result) && result;

    private static T EnumValue<T>(IReadOnlyDictionary<string, string> values, string key, T fallback) where T : struct, Enum =>
        values.TryGetValue(key, out var value) && Enum.TryParse<T>(value, true, out var result) ? result : fallback;
}
