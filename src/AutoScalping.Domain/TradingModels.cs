namespace AutoScalping.Domain;

public enum TradeSide
{
    Flat,
    Long,
    Short
}

public enum SignalAction
{
    Hold,
    Buy,
    Sell
}

public enum BotMode
{
    Paused,
    Running,
    Locked
}

public enum StrategyProfile
{
    Normal,
    InstantScalp,
    Hybrid
}

public enum OperatorAction
{
    None,
    Flatten,
    ManualBuy,
    ManualSell,
    ResetLock
}

public sealed record Candle(
    DateTimeOffset OpenTime,
    decimal Open,
    decimal High,
    decimal Low,
    decimal Close,
    long TickVolume,
    decimal SpreadPoints);

public sealed record IndicatorSnapshot(
    decimal FastEma,
    decimal SlowEma,
    decimal TrendFastEma,
    decimal TrendSlowEma,
    decimal Rsi,
    decimal Atr,
    decimal Adx);

public sealed record StrategySignal(
    SignalAction Action,
    DateTimeOffset BarTime,
    decimal Entry,
    decimal StopLoss,
    decimal TakeProfit,
    IndicatorSnapshot? Indicators,
    IReadOnlyList<string> Reasons)
{
    public static StrategySignal Hold(DateTimeOffset time, string reason, IndicatorSnapshot? indicators = null) =>
        new(SignalAction.Hold, time, 0, 0, 0, indicators, [reason]);
}

public sealed record StrategySettings
{
    public int FastEmaPeriod { get; init; } = 20;
    public int SlowEmaPeriod { get; init; } = 50;
    public int TrendFastEmaPeriod { get; init; } = 20;
    public int TrendSlowEmaPeriod { get; init; } = 50;
    public int RsiPeriod { get; init; } = 14;
    public int AtrPeriod { get; init; } = 14;
    public int AdxPeriod { get; init; } = 14;
    public decimal MinimumAdx { get; init; } = 18m;
    public decimal LongRsiMinimum { get; init; } = 52m;
    public decimal LongRsiMaximum { get; init; } = 68m;
    public decimal ShortRsiMinimum { get; init; } = 32m;
    public decimal ShortRsiMaximum { get; init; } = 48m;
    public decimal StopAtrMultiple { get; init; } = 1.3m;
    public decimal TargetAtrMultiple { get; init; } = 1.8m;
    public decimal MaximumSpreadPoints { get; init; } = 35m;
    public int CooldownBars { get; init; } = 5;
    public bool EnableLong { get; init; } = true;
    public bool EnableShort { get; init; } = true;
}

public sealed record RiskSettings
{
    public decimal StartingBalance { get; init; } = 10_000m;
    public decimal RiskPerTradePercent { get; init; } = 0.25m;
    public decimal MaximumDailyLossPercent { get; init; } = 1.5m;
    public decimal MaximumDrawdownPercent { get; init; } = 5m;
    public int MaximumTradesPerDay { get; init; } = 6;
    public decimal CommissionPerLotRoundTrip { get; init; } = 7m;
    public decimal SlippagePoints { get; init; } = 3m;
    public decimal PointSize { get; init; } = 0.01m;
    public decimal CurrencyPerPointPerLot { get; init; } = 1m;
    public decimal MinimumLot { get; init; } = 0.01m;
    public decimal MaximumLot { get; init; } = 10m;
    public decimal LotStep { get; init; } = 0.01m;
}

public sealed record RiskContext(
    decimal Balance,
    decimal Equity,
    decimal PeakEquity,
    decimal DailyRealizedPnl,
    int TradesToday,
    bool HasOpenPosition,
    BotMode Mode);

public sealed record RiskDecision(bool Allowed, decimal VolumeLots, string Reason);

public sealed record SimulatedTrade(
    int Number,
    TradeSide Side,
    DateTimeOffset EntryTime,
    DateTimeOffset ExitTime,
    decimal EntryPrice,
    decimal ExitPrice,
    decimal VolumeLots,
    decimal GrossPnl,
    decimal Costs,
    decimal NetPnl,
    string ExitReason);

public sealed record EquityPoint(DateTimeOffset Time, decimal Equity);

public sealed record BacktestMetrics(
    int TotalTrades,
    int WinningTrades,
    int LosingTrades,
    decimal WinRatePercent,
    decimal NetProfit,
    decimal ProfitFactor,
    decimal Expectancy,
    decimal MaximumDrawdownPercent,
    decimal ReturnPercent);

public sealed record BacktestResult(
    string Dataset,
    DateTimeOffset StartedAt,
    DateTimeOffset FinishedAt,
    BacktestMetrics Metrics,
    IReadOnlyList<SimulatedTrade> Trades,
    IReadOnlyList<EquityPoint> EquityCurve,
    IReadOnlyList<string> Warnings);

public sealed record OperatorCommand(
    long Revision,
    BotMode Mode,
    OperatorAction Action,
    DateTimeOffset IssuedAt,
    string Source)
{
    public StrategyProfile Profile { get; init; } = StrategyProfile.Normal;
}

public sealed record AuditEvent(
    long Revision,
    DateTimeOffset Time,
    string Event,
    string Detail);

public sealed record Mt5Telemetry
{
    public string TerminalId { get; init; } = "not-connected";
    public string AccountMode { get; init; } = "unknown";
    public string Broker { get; init; } = "Not connected";
    public string Symbol { get; init; } = "chart-symbol";
    public decimal Balance { get; init; }
    public decimal Equity { get; init; }
    public decimal DailyPnl { get; init; }
    public decimal Bid { get; init; }
    public decimal Ask { get; init; }
    public decimal SpreadPoints { get; init; }
    public TradeSide PositionSide { get; init; }
    public int PositionCount { get; init; }
    public decimal PositionVolume { get; init; }
    public decimal PositionEntry { get; init; }
    public decimal PositionPnl { get; init; }
    public BotMode BotMode { get; init; } = BotMode.Paused;
    public StrategyProfile StrategyProfile { get; init; } = StrategyProfile.Normal;
    public string MtfSummary { get; init; } = "Waiting for MT5 timeframe context";
    public bool MtfReady { get; init; }
    public bool MtfFastBuy { get; init; }
    public bool MtfFastSell { get; init; }
    public bool MtfNormalBuy { get; init; }
    public bool MtfNormalSell { get; init; }
    public decimal FastBasketTargetMoney { get; init; }
    public decimal FastBasketLossMoney { get; init; }
    public decimal FastBasketInitialRisk { get; init; }
    public string LastReason { get; init; } = "Waiting for MT5 telemetry";
    public long LastCommandRevision { get; init; }
    public DateTimeOffset ReceivedAt { get; init; }
}
