using AutoScalping.Domain;
using System.Text.Json;

namespace AutoScalping.Api;

public sealed class TradingControlStore
{
    private readonly object _gate = new();
    private readonly string _statePath;
    private readonly bool _allowRealControl;
    private OperatorCommand _command = new(0, BotMode.Paused, OperatorAction.None, DateTimeOffset.UtcNow, "system");
    private Mt5Telemetry _telemetry = new();
    private readonly List<AuditEvent> _audit =
    [
        new AuditEvent(0, DateTimeOffset.UtcNow, "initialized", "Demo-first control plane started in paused mode")
    ];

    public TradingControlStore(IConfiguration configuration)
    {
        _statePath = configuration["State:Path"] ?? Path.Combine("data", "control-state.json");
        _allowRealControl = configuration.GetValue<bool>("Mt5:AllowRealControl");
        try
        {
            if (!File.Exists(_statePath))
            {
                return;
            }

            var saved = JsonSerializer.Deserialize<PersistedControlState>(File.ReadAllText(_statePath));
            if (saved is null)
            {
                return;
            }

            var restoredProfile = NormalizeProfile(saved.Profile);
            _command = new OperatorCommand(
                saved.Revision,
                saved.Mode,
                OperatorAction.None,
                saved.SavedAt,
                "persisted-state")
            {
                Profile = restoredProfile
            };
            _audit.Add(new AuditEvent(saved.Revision, DateTimeOffset.UtcNow, "state-restored", $"Restored safe mode {saved.Mode} / {restoredProfile}"));
            if (saved.Profile != restoredProfile)
            {
                PersistControlState();
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            _audit.Add(new AuditEvent(0, DateTimeOffset.UtcNow, "state-restore-failed", exception.Message));
        }
    }

    public OperatorCommand CurrentCommand
    {
        get
        {
            lock (_gate)
            {
                if (_command.Action != OperatorAction.None &&
                    DateTimeOffset.UtcNow - _command.IssuedAt > TimeSpan.FromSeconds(15))
                {
                    _command = _command with { Action = OperatorAction.None };
                }

                return _command;
            }
        }
    }

    public Mt5Telemetry Telemetry
    {
        get
        {
            lock (_gate)
            {
                return _telemetry;
            }
        }
    }

    public IReadOnlyList<AuditEvent> Audit
    {
        get
        {
            lock (_gate)
            {
                return _audit.OrderByDescending(x => x.Time).Take(30).ToArray();
            }
        }
    }

    public CommandResult Issue(string requestedCommand, string source = "dashboard")
    {
        lock (_gate)
        {
            var normalized = requestedCommand.Trim().ToLowerInvariant();
            if (_command.Mode == BotMode.Locked && normalized is not "reset-lock" and not "emergency-stop")
            {
                return new CommandResult(false, "Emergency lock is active. Reset the lock before another command.", _command);
            }

            if (normalized is "start" or "resume" or "start-instant" or "start-hybrid" or "buy" or "sell")
            {
                var telemetryIsFresh = _telemetry.ReceivedAt != default &&
                                       DateTimeOffset.UtcNow - _telemetry.ReceivedAt < TimeSpan.FromSeconds(12);
                var accountMayTrade = string.Equals(_telemetry.AccountMode, "demo", StringComparison.OrdinalIgnoreCase) ||
                                      (_allowRealControl && string.Equals(_telemetry.AccountMode, "real", StringComparison.OrdinalIgnoreCase));
                if (!telemetryIsFresh || !accountMayTrade)
                {
                    return new CommandResult(
                        false,
                        "Start/Buy/Sell requires fresh MT5 telemetry from an allowed account. Demo is allowed; real control is disabled by default.",
                        _command);
                }
            }

            if (normalized == "start-instant" &&
                !string.Equals(_telemetry.AccountMode, "demo", StringComparison.OrdinalIgnoreCase))
            {
                return new CommandResult(
                    false,
                    "Instant scalp is hard-blocked outside an MT5 demo account.",
                    _command);
            }

            if ((normalized is "start" or "resume" or "start-instant" or "start-hybrid") &&
                !_telemetry.MtfReady)
            {
                return new CommandResult(
                    false,
                    $"MT5 multi-timeframe history is not ready: {_telemetry.MtfSummary}. Wait for the six-chart scan before starting.",
                    _command);
            }

            var requestedProfile = normalized switch
            {
                "start-instant" => StrategyProfile.InstantScalp,
                "start-hybrid" => StrategyProfile.Normal,
                "resume" => NormalizeProfile(_command.Profile),
                _ => StrategyProfile.Normal
            };
            if ((normalized is "start" or "resume" or "start-instant" or "start-hybrid") &&
                _telemetry.PositionCount > 0 &&
                requestedProfile != _command.Profile)
            {
                return new CommandResult(
                    false,
                    "Close the active bot position basket before changing automatic profiles.",
                    _command);
            }

            var next = normalized switch
            {
                "start" => _command with
                {
                    Mode = BotMode.Running,
                    Action = OperatorAction.None,
                    Profile = StrategyProfile.Normal
                },
                "resume" => _command with { Mode = BotMode.Running, Action = OperatorAction.None },
                "start-instant" => _command with
                {
                    Mode = BotMode.Running,
                    Action = OperatorAction.None,
                    Profile = StrategyProfile.InstantScalp
                },
                "start-hybrid" => _command with
                {
                    Mode = BotMode.Running,
                    Action = OperatorAction.None,
                    Profile = StrategyProfile.Normal
                },
                "pause" => _command with { Mode = BotMode.Paused, Action = OperatorAction.None },
                "close" or "close-position" => _command with { Mode = BotMode.Paused, Action = OperatorAction.Flatten },
                "emergency-stop" => _command with { Mode = BotMode.Locked, Action = OperatorAction.Flatten },
                "reset-lock" => _command with
                {
                    Mode = BotMode.Paused,
                    Action = OperatorAction.ResetLock
                },
                "buy" => _command with { Action = OperatorAction.ManualBuy },
                "sell" => _command with { Action = OperatorAction.ManualSell },
                _ => null
            };

            if (next is null)
            {
                return new CommandResult(false, "Unknown command.", _command);
            }

            if (normalized is "buy" or "sell")
            {
                if (_telemetry.PositionCount > 0)
                {
                    return new CommandResult(false, "A bot position is already open. Close it before another manual entry.", _command);
                }
            }

            var revision = _command.Revision + 1;
            _command = next with
            {
                Revision = revision,
                IssuedAt = DateTimeOffset.UtcNow,
                Source = source
            };
            AddAudit(revision, "operator-command", normalized);
            PersistControlState();
            return new CommandResult(true, $"Command '{normalized}' issued.", _command);
        }
    }

    public void UpdateTelemetry(Mt5Telemetry telemetry)
    {
        lock (_gate)
        {
            _telemetry = telemetry with { ReceivedAt = DateTimeOffset.UtcNow };
            var telemetryProfile = NormalizeProfile(telemetry.StrategyProfile);
            if (telemetryProfile == _command.Profile &&
                telemetry.BotMode == BotMode.Locked &&
                _command.Mode != BotMode.Locked)
            {
                _command = _command with { Mode = BotMode.Locked, Action = OperatorAction.None };
                AddAudit(_command.Revision, "ea-risk-lock", $"{telemetry.StrategyProfile} locked itself: {telemetry.LastReason}");
                PersistControlState();
                return;
            }
            if (_command.Action != OperatorAction.None &&
                telemetry.LastCommandRevision >= _command.Revision &&
                telemetryProfile == _command.Profile)
            {
                AddAudit(_command.Revision, "command-acknowledged", $"{_command.Action} acknowledged by {telemetry.TerminalId}");
                _command = _command with { Action = OperatorAction.None };
            }
        }
    }

    private void AddAudit(long revision, string name, string detail)
    {
        _audit.Add(new AuditEvent(revision, DateTimeOffset.UtcNow, name, detail));
        if (_audit.Count > 200)
        {
            _audit.RemoveRange(0, _audit.Count - 200);
        }
    }

    private static StrategyProfile NormalizeProfile(StrategyProfile profile) =>
        profile == StrategyProfile.Hybrid ? StrategyProfile.Normal : profile;

    private void PersistControlState()
    {
        try
        {
            var directory = Path.GetDirectoryName(Path.GetFullPath(_statePath));
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var state = new PersistedControlState(_command.Revision, _command.Mode, DateTimeOffset.UtcNow)
            {
                Profile = _command.Profile
            };
            var temporaryPath = _statePath + ".tmp";
            File.WriteAllText(temporaryPath, JsonSerializer.Serialize(state));
            File.Move(temporaryPath, _statePath, true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            AddAudit(_command.Revision, "state-save-failed", exception.Message);
        }
    }
}

public sealed record CommandResult(bool Accepted, string Message, OperatorCommand Command);

internal sealed record PersistedControlState(long Revision, BotMode Mode, DateTimeOffset SavedAt)
{
    public StrategyProfile Profile { get; init; } = StrategyProfile.Normal;
}
