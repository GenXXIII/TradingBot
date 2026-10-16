using AutoScalping.Domain;

namespace AutoScalping.Api;

public sealed record DashboardResponse(
    DateTimeOffset ServerTime,
    bool Mt5Connected,
    bool RealControlEnabled,
    string Environment,
    OperatorCommand Control,
    Mt5Telemetry Telemetry,
    BacktestResult ValidationBacktest,
    StrategySettings Strategy,
    RiskSettings Risk,
    IReadOnlyList<AuditEvent> Audit,
    IReadOnlyList<string> SafetyNotices);
