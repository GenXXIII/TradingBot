# AutoScalpingTrading

A standalone, deterministic auto-trading system for MetaTrader 5 demo accounts, including Exness when you choose to use it. It contains no AI/LLM integration. `AutoScalperHybrid` now provides both Normal and Fast Scalp modes using the complete BSD-licensed Nyao Scalper v46 engine; the original EA remains as a fallback.

The system can autonomously find setups, size risk, place Buy/Sell orders, attach stop-loss and take-profit, move protection to break-even, stop after risk-limit breaches, and run continuously on a Windows VPS. It cannot guarantee a win rate or profit. Short-term leveraged trading can lose money quickly, so real-account execution is disabled by default.

## What is included

- `mt5/Experts/AutoScalperExness.mq5`: native MQL5 Expert Advisor for MT5 (the historical filename does not restrict the broker).
- `mt5/Experts/AutoScalperExness.ex5`: compiled EA (0 compiler errors and 0 warnings at handoff).
- `mt5/Experts/AutoScalperHybrid.mq5`: complete Nyao v46 engine with the project's dashboard bridge and independent safety locks.
- `mt5/Experts/AutoScalperHybrid.ex5`: compiled Hybrid EA.
- `mt5/Profiles/Presets`: original 3-digit Nyao defaults plus the adjusted `XAUUSD-2digit-M5` Hybrid preset.
- `src/AutoScalping.Api`: .NET 10 control plane, telemetry API, durable mode state, and audit events.
- `src/AutoScalping.Engine`: deterministic strategy, indicators, risk manager, and cost-aware validation backtester.
- `web`: responsive Next.js control dashboard.
- `tests`: unit and integration-oriented checks for risk, determinism, and MT5 telemetry parsing.
- `scripts`: native Windows install, start, stop, and status commands. The EA runs directly inside your MT5 Desktop terminal.

## Safety model

The EA starts paused with `InpAllowRealAccount=false`, while the API starts with `ALLOW_REAL_CONTROL=false`. On a real account, execution remains blocked until both independent gates are deliberately changed.

Controls have precise meanings:

- **Normal: best setup**: use stable closed-bar Nyao scoring and wait patiently for the strongest position after multi-timeframe context, HTF, range, spread, duplicate, session, news and risk filters agree.
- **Fast: five-position basket**: on a demo hedging account, evaluate every tick and open five automatically risk-sized positions only after multi-timeframe context, a fresh local EMA reclaim, EMA direction/slope, RSI, candle direction, ATR distance, spread and risk checks agree.
- **Pause entries**: block new automatic entries; broker-side SL/TP continues protecting an existing position.
- **Buy / Sell**: demo-only manual entry through the EA, still using spread checks, risk-sized volume, SL, and TP.
- **Close position**: pause entries and flatten only positions/orders with this EA's symbol and magic number.
- **Emergency stop**: flatten the EA's exposure and persist a locked state.
- **Reset lock**: clear the lock and remain paused. It does not automatically resume trading.

Hard guards include one Normal position per symbol, one Fast basket at a time, maximum spread, daily realized-loss lock, equity drawdown lock, broker volume validation, emergency stop-distance validation, and a unique magic number. Manual trades and other EAs are not touched. Neither profile has a fixed daily trade-count cap.

### Instant demo scalp profile

Fast mode in the combined Hybrid EA is intended for rapid automated execution on an MT5 demo hedging account. Unlike Normal, it does not inherit the D1 direction gate or multi-hour trend score. BUY and SELL use the same mirrored short-horizon rules: EMA5 must be on the correct side of EMA12 and sloping with the trade, price must freshly reclaim EMA5 in that direction, RSI and the live candle must confirm, and price must remain close enough to EMA5. Spread, expected-movement, emergency-stop and risk checks still apply. A qualified setup opens five same-direction positions sized from the current account balance and the broker-SL distance. If five minimum lots exceed the 0.5% stop-risk budget, it does not trade. After a profitable exit there is no fixed per-candle quota or cooldown timer: the next fresh EMA reclaim may qualify immediately. A losing exit still pauses entries for three minutes. The bot keeps scanning for later setups until **STOP & CLOSE** is pressed. The demo-only Fast profile has a separate 0.10% daily realized-loss lock.

Before either automatic entry, the EA checks completed EMA5/EMA12 candles on M1, M5, M15, H1, H4 and D1. If any timeframe history is missing, automatic entries wait. The current Fast source requires **both M1 and M5** to agree with the proposed direction and rejects a setup when both M15 and H1 oppose it; H4/D1 are shown as context but do not dictate every scalp. Normal requires at least two agreeing M15/H1/H4/D1 trends and no more than one opposing trend, in addition to its existing D1 filter. The dashboard shows this context before Start is pressed; it is not a promise of higher accuracy. The existing MT5 economic-calendar filter pauses new entries around high-impact matching-currency events, and the supplied two-digit XAUUSD preset uses 30 minutes before and after.

- treat +1.5% of basket-entry balance as a profit milestone, not a mandatory take-profit; after reaching it, trail group profit from its peak by half the initial planned SL risk (with a floor of half the milestone);
- size each order automatically from the stop distance, with a 0.50-lot per-position ceiling and a 5% buffer below the combined risk limit;
- start a risk-based group profit trail once peak floating profit reaches half the initial planned SL risk; a positive basket can also close if both M1/M5 reverse or both M15/H1 oppose the trade;
- close an adverse basket if both M1/M5 reverse, or after losing one-quarter of initial planned risk when the original short-term context has faded;
- review the setup after five minutes, but allow it to continue if the short-term trend remains confirmed;
- close earlier if combined floating P/L reaches -0.5% of entry balance or if any one position exits independently;
- resume scanning immediately after a profitable exit, but pause three minutes after a loss;
- apply no fixed daily trade-count cap, while keeping the 0.10% daily-loss lock for Fast Scalp; a daily-only lock resets on the next broker-server day, while real-account and drawdown locks do not reset automatically;
- cap calculated emergency basket risk at 0.50% of balance; skip the whole entry if five minimum lots will not fit;
- submit a broker-side SL on every position; group TP is managed by the EA, not guaranteed by a broker TP order.

Every basket starts negative because of spread and may still close at a loss. The quality and cost filters reduce avoidable entries but cannot guarantee a profitable exit.
At balances such as $10 or $100, a five-position XAUUSD basket will often be blocked because five broker-minimum lots risk more than 0.5% at a valid SL. The EA never rounds volume up to force a trade. The +1.5% milestone is not guaranteed, and a fading signal can close the group below it. Once reached, the trailing floor is a software market-exit trigger, not a guaranteed fill. Broker stops, gaps, commission and slippage can make actual loss exceed the planned ceiling. This aggressive Fast configuration must be validated with broker real-tick tests and demo forward testing before any consideration of real funds.

As of 2026-10-16, the revised Fast source is **experimental and has not been installed on the demo chart**. Its $10,000 real-tick tests produced [-$163.25 in July](reports/hybrid-fast-2026-07-10k-profittrail-port3002/summary.md), [-$318.35 in August](reports/hybrid-fast-2026-08-10k-profittrail/summary.md), and [+$18.40 in September](reports/hybrid-fast-2026-09-10k-profittrail/summary.md). Across these separate monthly runs, the net result is -$463.20; July and September had 100% real-tick history quality, while August had 93%. This is not a reliable profit edge and has not earned a demo forward test. Keep the dashboard paused until testing and deployment are explicitly resumed.

### Nyao Hybrid engine

Hybrid contains the complete Nyao v46 implementation rather than a partial rewrite. Normal uses its closed-bar entry and position-management paths; Fast adds an every-tick, quality-gated basket entry path and manages the basket as a group. The engine includes trend and legacy score models, higher-timeframe trend and range filters, spread and duplicate-entry guards, limit entries, signal dampening, loss-streak paper mode, optional health-based loss management and partial close, checkpoint exits, break-even and trailing, news/session/market-close/leverage checks, basket and equity protections, restart-safe state, reports, Discord alerts, and the optional hedge-chain recovery system. Some of these features apply only to Normal.

The supplied presets intentionally keep the high-risk features conservative:

- `BaseLotSize=0.01`;
- `EnableHedgeChain=false` (the hedge chain is a martingale and remains opt-in);
- `EnableDynamicLots=false`;
- `RiskPerTradePct=0.0`, so the preset uses the fixed base lot;
- independent bridge locks at 1.5% daily realized loss and 5% peak-equity drawdown;
- `InpAllowRealAccount=false` and `InpRequireDashboardStart=true`.
- `MagicNumber=26101546`, separate from the original Nyao EA so Hybrid cannot adopt its positions.
- `MaxOpenOrders=1` for Normal; Fast independently opens five risk-sized positions as one basket and only enters on a fresh qualifying EMA reclaim.

Use `AutoScalperHybrid.XAUUSD-2digit-M5.set` for a gold symbol quoted like `4094.31`. It adjusts the original 3-digit point values by 10: `SLValue=2000`, `TPValue=2000`, `ZonePoints=1000`, and `MaxSpreadPoints=50`. Use `AutoScalperHybrid.default.set` only for a 3-digit quote such as `4094.310`. Both are starting profiles for testing, not profit guarantees.

## Combined strategy

Normal signals use completed candles:

1. The default Trend Score combines range position, EMA200 distance, directional efficiency and long-lookback momentum.
2. The configured D1 EMA50 filter must confirm the direction.
3. The winning closed-bar score must pass its threshold and the normal spread, range, duplicate, cooldown and position limits.
4. Checkpoint exits, broker stop-loss, break-even, trailing and optional health management protect open positions.
5. News, session, market-close, leverage, basket-loss, daily-loss and drawdown gates can block or stop trading independently.
6. The supplied preset uses a fixed `0.01` base lot; optional broker-aware risk sizing remains available through `RiskPerTradePct`.

Fast Scalp uses the local EMA5/EMA12, RSI and ATR confirmation documented above. It can take either direction when that direction independently qualifies; it does not force alternating BUY/SELL trades or equal counts. Symbol specifications and spreads differ by broker, account type, and symbol suffix, so attach the EA to the exact chart you want to trade (for example `XAUUSD`, `XAUUSDm`, or another account-specific name).

## Start directly on Windows

1. Copy `.env.example` to `.env` and replace `MT5_BRIDGE_KEY` with a long random local key.
2. From this directory, build and start the API and dashboard as native background processes:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local.ps1
   ```

3. Open `http://127.0.0.1:3000`.
4. The control API is at `http://127.0.0.1:5182`; its health endpoint is `/health`.

The start script also opens the installed MT5 terminal automatically. If MT5 is installed in a custom folder, set `MT5_TERMINAL_PATH` in `.env`. Use `-SkipMt5Launch` only when you intentionally do not want MT5 opened.

After the first successful build, use `-SkipBuild` for a faster start:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local.ps1 -SkipBuild
```

Check status or stop only this project's tracked processes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\status-local.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\stop-local.ps1
```

Runtime files and logs are under `.runtime`; durable control state is under `data`. Stopping the services does not delete either directory.

## Connect your MT5 demo account

1. In MT5 Desktop, select **File > Login to Trade Account** and enter the demo account's login, password, and server. These credentials stay in MT5 and are never entered into this project.
2. In MT5 select **File > Open Data Folder** and copy that folder path.
3. Install the EA (quote the path if it contains spaces):

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-ea.ps1 -Mt5DataFolder "C:\path\from\MT5"
   ```

4. Restart MT5 or refresh **Navigator > Expert Advisors**.
5. In **Tools > Options > Expert Advisors**:
   - enable algorithmic trading;
   - enable WebRequest for `http://127.0.0.1:5182`.
6. Drag `AutoScalperHybrid` onto an M5 chart. Do not also attach the original EA to the same symbol.
7. For Hybrid on a 2-digit XAUUSD quote, open **Inputs > Load** and select `MQL5\Profiles\Presets\AutoScalpingTrading\AutoScalperHybrid.XAUUSD-2digit-M5.set`.
8. Keep `InpAllowRealAccount=false`, confirm `BaseLotSize=0.01` for Normal and `EnableHedgeChain=false`, and set `InpBridgeKey` to the same value as `.env`. Fast uses automatic risk-sized lots and can be far larger than 0.01 on a large demo balance.
9. Confirm the dashboard shows the terminal as connected and the account as `DEMO`.
10. Choose **Normal: best setup** or **Fast: five-position basket** on the dashboard. Both control the attached `AutoScalperHybrid` EA.

On this computer, the compiled EA has already been installed into the detected MT5 data folder under `MQL5\Experts\AutoScalpingTrading`. Refresh Navigator or restart MT5, then complete steps 5-10. Attaching the EA and enabling Algo Trading remain deliberate MT5 actions because they authorize order execution.

MetaQuotes documents the same login flow and fields in [Connect to an Account](https://www.metatrader5.com/en/terminal/help/startworking/authorization).

If you later use an Exness account, its EA setup requirements are documented in [Exness EA setup](https://get.exness.help/hc/en-us/articles/360019530859-Using-Expert-Advisors-EA).

## MT5 backtest before demo forward testing

The EA detects Strategy Tester mode, runs autonomously there, and disables dashboard WebRequests because MT5 does not execute `WebRequest` in Strategy Tester.

Recommended tester setup:

- Expert: `AutoScalperHybrid`
- Symbol: the exact broker symbol intended for demo
- Period: M5
- Model: **Every tick based on real ticks**
- Range: multiple market regimes, ideally at least two years if quality data is available
- Forward test: reserve at least the last one-third
- Execution delay: random or a measured VPS-to-broker delay
- Optimization criterion: **Custom max** (the EA penalizes drawdown and rejects fewer than 100 trades)

Load the preset matching the symbol's quote digits. Strategy Tester automatically runs Normal without the dashboard when `InpAutoRunInStrategyTester=true`; set `InpTestFastScalp=true` to test Fast instead. The vendored `tools/backtest/nyao_backtest.py` runner is also retained for repeatable monthly real-tick plans.

Do not optimize only for win rate. Review net profit after costs, profit factor, expectancy, maximum drawdown, trade count, parameter stability, and out-of-sample results. MetaQuotes describes the tester and its external-call limitations in the [MQL5 Strategy Tester documentation](https://www.mql5.com/en/docs/runtime/testing).

## Demo-to-real promotion gate

Real trading is a later, manual decision. Enabling it requires both `InpAllowRealAccount=true` in MT5 and `ALLOW_REAL_CONTROL=true` in `.env`, followed by restarting the native services. At minimum, require all of the following first:

- MT5 real-tick backtests across trending, ranging, volatile, and quiet periods;
- positive out-of-sample expectancy after spread, commission, and slippage;
- at least 100 demo trades over at least four weeks;
- profit factor at or above 1.25 and maximum drawdown at or below 5% in the demo observation window;
- no duplicate orders, unprotected positions, restart failures, or circuit-breaker failures;
- stable results under modest parameter changes rather than one narrow optimized setting;
- a small initial live-risk allocation you can afford to lose.

These are engineering acceptance thresholds, not a promise that future trading will be profitable. The CFTC notes that automated systems cannot consistently predict the future and that most retail forex traders lose money; see its [forex trading risk guidance](https://www.cftc.gov/LearnAndProtect/forexfrauds).

## Development verification

```powershell
dotnet test .\AutoScalpingTrading.slnx
cd .\web
npm.cmd run lint
npm.cmd run build
npm.cmd audit --omit=dev
```

Compile the EA from the command line when MetaEditor is installed:

```powershell
& "C:\Program Files\MetaTrader 5\MetaEditor64.exe" /compile:"$PWD\mt5\Experts\AutoScalperExness.mq5" /log:"$PWD\mt5\compile.log"
& "C:\Program Files\MetaTrader 5\MetaEditor64.exe" /compile:"$PWD\mt5\Experts\AutoScalperHybrid.mq5" /log:"$PWD\mt5\hybrid-compile.log"
```

## Operational notes

- XAUUSD is not a true 24/7 market. Run the system continuously on a reliable Windows VPS, but expect weekend closures, maintenance, disconnects, and abnormal spreads.
- Native 24/7 operation requires Windows, MT5 Desktop, the API, and the dashboard processes to remain running. Disable sleep and automatic hibernation on the machine used for forward testing.
- SL/TP is submitted with each order so protection remains at the broker if the dashboard or API stops.
- The last control mode is persisted by the API. One-shot Buy/Sell/Flatten actions expire and are never replayed after a service restart.
- The dashboard's bundled synthetic test is only a deterministic software validation. It is intentionally labeled as such and is not trading evidence.
- Keep the bridge API bound to a trusted machine/network; change the default key before any extended test.
- Nyao Scalper attribution and BSD-3-Clause terms are retained under `third_party/NyaoScalper`; see `THIRD-PARTY-NOTICES.md`.
