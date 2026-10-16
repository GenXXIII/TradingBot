# Local MT5 Smoke Test With Prestarted Agent

| Setting | Value |
|---|---|
| EA | Nyao Scalper v46.0 (`nyao_scalper.mq5`) |
| Settings | `settings/default.set` |
| Git commit | unknown |
| Symbol / timeframes | XAUUSD / M5 |
| Tick data | 1 minute OHLC |
| Deposit / leverage | 2,000 USD / 1:500 |
| Runs | One run per month, each starting from a fresh deposit |
| Generated | 2026-10-15 01:17 with `tools/backtest/nyao_backtest.py` |

## Summary

Total return is the sum of the monthly returns (each month starts from the same deposit, not compounded).

| Timeframe | Total return | Profitable | Best / worst run | Max drawdown | Trades | Win rate | Avg win / loss | Profit factor | Tick data |
|---|---|---|---|---|---|---|---|---|---|
| M5 | -3.0% | 0/1 | -3.0% / -3.0% | 9.7% | 6 | 17% | $11.65 / -$14.24 | 0.16 | 100% |

## Results per run

| Run | M5 |
|---|---|
| 2026-09 | -3.0% (DD 10%, 6 trades) |

## Balance graphs

### M5

**2026-09** -3.0%

![M5 2026-09](graphs/M5_2026-09.png)
