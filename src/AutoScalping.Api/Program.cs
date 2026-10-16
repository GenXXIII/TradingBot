using AutoScalping.Api;
using AutoScalping.Domain;
using AutoScalping.Engine;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateBuilder(args);
builder.Services.ConfigureHttpJsonOptions(options =>
    options.SerializerOptions.Converters.Add(new JsonStringEnumConverter(System.Text.Json.JsonNamingPolicy.CamelCase)));
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
    policy.WithOrigins("http://localhost:3000", "http://127.0.0.1:3000").AllowAnyHeader().AllowAnyMethod()));
builder.Services.AddSingleton<TradingControlStore>();
builder.Services.AddSingleton<BridgeSecurity>();
builder.Services.AddSingleton(new StrategySettings());
builder.Services.AddSingleton(new RiskSettings());
builder.Services.AddSingleton<BacktestEngine>();
builder.Services.AddSingleton(sp =>
    sp.GetRequiredService<BacktestEngine>().Run(SyntheticMarketData.Generate(), "deterministic synthetic regimes / seed 20261014"));

var app = builder.Build();
app.UseCors();

app.MapGet("/health", () => Results.Ok(new
{
    status = "healthy",
    service = "auto-scalping-control-plane",
    aiEnabled = false,
    time = DateTimeOffset.UtcNow
}));

app.MapGet("/api/dashboard", (
    TradingControlStore store,
    BacktestResult backtest,
    StrategySettings strategy,
    RiskSettings risk,
    IConfiguration configuration) =>
{
    var telemetry = store.Telemetry;
    var connected = telemetry.ReceivedAt != default &&
                    DateTimeOffset.UtcNow - telemetry.ReceivedAt < TimeSpan.FromSeconds(12);
    return Results.Ok(new DashboardResponse(
        DateTimeOffset.UtcNow,
        connected,
        configuration.GetValue<bool>("Mt5:AllowRealControl"),
        "MT5 demo-first",
        store.CurrentCommand,
        telemetry,
        backtest,
        strategy,
        risk,
        store.Audit,
        [
            "Real-account trading is disabled by default inside the EA.",
            "Attach AutoScalperHybrid for both dashboard modes: Normal waits for the best Nyao setup; Fast uses live Nyao quality confirmation.",
            "Fast Scalp is demo-only and opens five risk-sized positions per independently confirmed local EMA/RSI reclaim; it does not inherit Normal's D1 direction bias.",
            "The complete Nyao v46 management engine remains active; hedge-chain martingale and dynamic lots are disabled in the supplied preset.",
            "Fast Scalp treats five positions as one basket. +1.5% of entry balance is a trailing-profit milestone, not a fixed take-profit; -0.5% is the planned floating-loss ceiling. Signal exits, stops, costs and slippage can change the realized result.",
            "Synthetic results validate software behavior only; use MT5 real-tick testing and demo forward testing for evidence."
        ]));
});

app.MapPost("/api/control/{command}", (string command, TradingControlStore store) =>
{
    var result = store.Issue(command);
    return result.Accepted ? Results.Ok(result) : Results.BadRequest(result);
});

app.MapPost("/api/backtests/run", (BacktestEngine engine) =>
    Results.Ok(engine.Run(SyntheticMarketData.Generate(), "deterministic synthetic regimes / seed 20261014")));

app.MapGet("/api/mt5/command", (HttpRequest request, TradingControlStore store, BridgeSecurity security) =>
{
    if (!security.IsAuthorized(request))
    {
        return Results.Text("unauthorized", statusCode: StatusCodes.Status401Unauthorized);
    }

    var command = store.CurrentCommand;
    var response = string.Join('\n',
        $"revision={command.Revision}",
        $"mode={command.Mode.ToString().ToLowerInvariant()}",
        $"profile={command.Profile.ToString().ToLowerInvariant()}",
        $"action={command.Action.ToString().ToLowerInvariant()}",
        $"issued_at_unix={command.IssuedAt.ToUnixTimeSeconds()}");
    return Results.Text(response, "text/plain");
});

app.MapPost("/api/mt5/telemetry", async (HttpRequest request, TradingControlStore store, BridgeSecurity security) =>
{
    if (!security.IsAuthorized(request))
    {
        return Results.Unauthorized();
    }

    using var reader = new StreamReader(request.Body);
    var body = await reader.ReadToEndAsync();
    if (string.IsNullOrWhiteSpace(body))
    {
        return Results.BadRequest(new { error = "Telemetry body is empty." });
    }

    store.UpdateTelemetry(TelemetryParser.Parse(body));
    return Results.Ok(new { accepted = true, serverTime = DateTimeOffset.UtcNow });
});

app.Run();

public partial class Program;
