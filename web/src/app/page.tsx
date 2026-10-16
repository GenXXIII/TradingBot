"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import styles from "./page.module.css";

type BotMode = "paused" | "running" | "locked";
type TradeSide = "flat" | "long" | "short";
type StrategyProfile = "normal" | "instantScalp" | "hybrid";

type Dashboard = {
  serverTime: string;
  mt5Connected: boolean;
  realControlEnabled: boolean;
  environment: string;
  control: {
    revision: number;
    mode: BotMode;
    action: string;
    issuedAt: string;
    source: string;
    profile: StrategyProfile;
  };
  telemetry: {
    terminalId: string;
    accountMode: string;
    broker: string;
    symbol: string;
    balance: number;
    equity: number;
    dailyPnl: number;
    bid: number;
    ask: number;
    spreadPoints: number;
    positionSide: TradeSide;
    positionCount: number;
    positionVolume: number;
    positionEntry: number;
    positionPnl: number;
    botMode: BotMode;
    strategyProfile: StrategyProfile;
    mtfSummary: string;
    mtfReady: boolean;
    mtfFastBuy: boolean;
    mtfFastSell: boolean;
    mtfNormalBuy: boolean;
    mtfNormalSell: boolean;
    fastBasketTargetMoney: number;
    fastBasketLossMoney: number;
    fastBasketInitialRisk: number;
    lastReason: string;
    lastCommandRevision: number;
    receivedAt: string;
  };
  validationBacktest: {
    dataset: string;
    startedAt: string;
    finishedAt: string;
    metrics: {
      totalTrades: number;
      winningTrades: number;
      losingTrades: number;
      winRatePercent: number;
      netProfit: number;
      profitFactor: number;
      expectancy: number;
      maximumDrawdownPercent: number;
      returnPercent: number;
    };
    equityCurve: { time: string; equity: number }[];
    warnings: string[];
  };
  strategy: {
    fastEmaPeriod: number;
    slowEmaPeriod: number;
    minimumAdx: number;
    stopAtrMultiple: number;
    targetAtrMultiple: number;
  };
  risk: {
    riskPerTradePercent: number;
    maximumDailyLossPercent: number;
    maximumDrawdownPercent: number;
    maximumTradesPerDay: number;
    commissionPerLotRoundTrip: number;
    slippagePoints: number;
  };
  audit: { revision: number; time: string; event: string; detail: string }[];
  safetyNotices: string[];
};

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:5182";

function money(value: number) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 2,
  }).format(value || 0);
}

function number(value: number, digits = 2) {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: digits }).format(value || 0);
}

function EquityChart({ points }: { points: { equity: number }[] }) {
  const path = useMemo(() => {
    if (points.length < 2) return "";
    const sampled = points.filter((_, index) => index % Math.max(1, Math.floor(points.length / 140)) === 0);
    const values = sampled.map((point) => point.equity);
    const minimum = Math.min(...values);
    const maximum = Math.max(...values);
    const range = Math.max(1, maximum - minimum);
    return sampled
      .map((point, index) => {
        const x = (index / Math.max(1, sampled.length - 1)) * 1000;
        const y = 220 - ((point.equity - minimum) / range) * 180;
        return `${x.toFixed(1)},${y.toFixed(1)}`;
      })
      .join(" ");
  }, [points]);

  return (
    <svg className={styles.chart} viewBox="0 0 1000 260" preserveAspectRatio="none" aria-label="Validation equity curve">
      <defs>
        <linearGradient id="chart-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#63e6aa" stopOpacity="0.28" />
          <stop offset="100%" stopColor="#63e6aa" stopOpacity="0" />
        </linearGradient>
      </defs>
      <line x1="0" y1="70" x2="1000" y2="70" className={styles.gridLine} />
      <line x1="0" y1="140" x2="1000" y2="140" className={styles.gridLine} />
      <line x1="0" y1="210" x2="1000" y2="210" className={styles.gridLine} />
      {path && <polygon points={`0,240 ${path} 1000,240`} fill="url(#chart-fill)" />}
      {path && <polyline points={path} className={styles.chartLine} />}
    </svg>
  );
}

export default function Home() {
  const [data, setData] = useState<Dashboard | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState("");

  const refresh = useCallback(async () => {
    try {
      const response = await fetch(`${API_URL}/api/dashboard`, { cache: "no-store" });
      if (!response.ok) throw new Error(`Control API returned ${response.status}`);
      setData(await response.json());
      setError("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Control API is unavailable");
    }
  }, []);

  useEffect(() => {
    const initial = window.setTimeout(refresh, 0);
    const timer = window.setInterval(refresh, 2_000);
    return () => {
      window.clearTimeout(initial);
      window.clearInterval(timer);
    };
  }, [refresh]);

  async function command(name: string) {
    setBusy(name);
    setNotice("");
    try {
      const response = await fetch(`${API_URL}/api/control/${name}`, { method: "POST" });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.message ?? "Command was rejected");
      setNotice(payload.message);
      await refresh();
    } catch (reason) {
      setNotice(reason instanceof Error ? reason.message : "Command failed");
    } finally {
      setBusy("");
    }
  }

  if (!data) {
    return (
      <main className={styles.loading}>
        <div className={styles.logoMark}>AS</div>
        <p>{error || "Connecting to the trading control plane…"}</p>
      </main>
    );
  }

  const { telemetry, validationBacktest: backtest } = data;
  const mode = data.control.mode;
  const connectedAccountAllowed = data.mt5Connected && (
    telemetry.accountMode.toLowerCase() === "demo" ||
    (telemetry.accountMode.toLowerCase() === "real" && data.realControlEnabled)
  );
  const positionOpen = telemetry.positionCount > 0;
  const instantProfile = data.control.profile === "instantScalp";

  return (
    <main className={styles.shell}>
      <header className={styles.header}>
        <div className={styles.brand}>
          <div className={styles.logoMark}>AS</div>
          <div>
            <strong>AutoScalper</strong>
            <span>MT5 desktop control</span>
          </div>
        </div>
        <div className={styles.headerStatus}>
          <span className={`${styles.dot} ${data.mt5Connected ? styles.online : styles.offline}`} />
          <span>{data.mt5Connected ? `${telemetry.terminalId} connected` : "MT5 bridge offline"}</span>
          <span className={styles.demoBadge}>{telemetry.accountMode === "demo" ? "DEMO" : "DEMO GATE"}</span>
        </div>
      </header>

      <section className={styles.hero}>
        <div>
          <p className={styles.eyebrow}>AUTONOMOUS EXECUTION / NO AI</p>
          <div className={styles.modeLine}>
            <h1>{mode === "running" ? (instantProfile ? "Fast precision scalp running" : "Best-position mode running") : mode === "locked" ? "Emergency locked" : "Strategy paused"}</h1>
            <span className={`${styles.modeBadge} ${styles[mode]}`}>{mode}</span>
          </div>
          <p className={styles.reason}>{telemetry.lastReason}</p>
        </div>
        <div className={styles.heroMeta}>
          <span>Symbol</span>
          <strong>{telemetry.symbol}</strong>
          <span>Broker</span>
          <strong>{telemetry.broker}</strong>
        </div>
      </section>

      <section className={`${styles.panel} ${styles.timeframePanel}`} aria-label="Multi-timeframe pre-trade check">
        <div className={styles.panelHeader}>
          <div>
            <p className={styles.eyebrow}>PRE-TRADE CONTEXT</p>
            <h2>Multi-timeframe check</h2>
          </div>
          <span className={styles.revision}>{data.mt5Connected && telemetry.mtfReady ? "6 closed-bar charts" : "Waiting for MT5 history"}</span>
        </div>
        <p className={styles.timeframeSummary}>{data.mt5Connected ? telemetry.mtfSummary : "Connect MT5 to scan M1, M5, M15, H1, H4 and D1."}</p>
        <div className={styles.timeframeDecisions}>
          <span>Fast BUY: {telemetry.mtfReady && telemetry.mtfFastBuy ? "context agrees" : "wait"}</span>
          <span>Fast SELL: {telemetry.mtfReady && telemetry.mtfFastSell ? "context agrees" : "wait"}</span>
          <span>Normal BUY: {telemetry.mtfReady && telemetry.mtfNormalBuy ? "context agrees" : "wait"}</span>
          <span>Normal SELL: {telemetry.mtfReady && telemetry.mtfNormalSell ? "context agrees" : "wait"}</span>
        </div>
        <p className={styles.caption}>This is trend context, not an entry signal. After you press Start, each trade still needs its own signal, spread, news, position and risk checks.</p>
      </section>

      <section className={styles.controls} aria-label="Trading controls">
        <div className={styles.controlGroup}>
          <button className={styles.startButton} disabled={busy !== "" || !connectedAccountAllowed || !telemetry.mtfReady || mode === "running" || mode === "locked"} onClick={() => command("start")}>
            <span>▶</span> Normal: best setup
          </button>
          <button className={styles.instantButton} disabled={busy !== "" || !data.mt5Connected || telemetry.accountMode.toLowerCase() !== "demo" || !telemetry.mtfReady || mode === "running" || mode === "locked"} onClick={() => command("start-instant")}>
            Fast: five-position basket
          </button>
          <button disabled={busy !== "" || mode !== "running"} onClick={() => command(instantProfile ? "close-position" : "pause")}>
            <span>{instantProfile ? "■" : "Ⅱ"}</span> {instantProfile ? "STOP & CLOSE" : "Pause entries"}
          </button>
        </div>
        <div className={styles.divider} />
        <div className={styles.controlGroup}>
          <button className={styles.buyButton} disabled={busy !== "" || !connectedAccountAllowed || positionOpen || mode === "locked"} onClick={() => command("buy")}>↑ Buy</button>
          <button className={styles.sellButton} disabled={busy !== "" || !connectedAccountAllowed || positionOpen || mode === "locked"} onClick={() => command("sell")}>↓ Sell</button>
          <button disabled={busy !== "" || !positionOpen} onClick={() => command("close-position")}>Close position</button>
        </div>
        <div className={styles.controlSpacer} />
        {mode === "locked" ? (
          <button className={styles.resetButton} disabled={busy !== ""} onClick={() => command("reset-lock")}>Reset lock</button>
        ) : (
          <button className={styles.emergencyButton} disabled={busy !== ""} onClick={() => command("emergency-stop")}>■ Emergency stop</button>
        )}
      </section>

      {(notice || error) && <div className={styles.notice}>{notice || error}</div>}

      <section className={styles.metricGrid}>
        <article className={styles.metricCard}>
          <span>Account equity</span>
          <strong>{money(telemetry.equity)}</strong>
          <small>Balance {money(telemetry.balance)}</small>
        </article>
        <article className={styles.metricCard}>
          <span>Today&apos;s bot P/L</span>
          <strong className={telemetry.dailyPnl < 0 ? styles.negative : styles.positive}>{money(telemetry.dailyPnl)}</strong>
          <small>{instantProfile ? "Fast scalp lock −0.10%" : `Normal lock −${data.risk.maximumDailyLossPercent}%`}</small>
        </article>
        <article className={styles.metricCard}>
          <span>Live spread</span>
          <strong>{number(telemetry.spreadPoints, 1)} <i>pts</i></strong>
          <small>{instantProfile ? "Fast preset maximum 50 pts" : "Normal preset maximum 50 pts"}</small>
        </article>
        <article className={styles.metricCard}>
          <span>Bot position</span>
          <strong className={telemetry.positionSide === "long" ? styles.positive : telemetry.positionSide === "short" ? styles.negative : ""}>
            {telemetry.positionSide.toUpperCase()}
          </strong>
          <small>{positionOpen ? `${telemetry.positionCount} positions / ${number(telemetry.positionVolume)} lots / ${money(telemetry.positionPnl)}` : "No market exposure"}</small>
        </article>
      </section>

      <section className={styles.mainGrid}>
        <article className={`${styles.panel} ${styles.performancePanel}`}>
          <div className={styles.panelHeader}>
            <div>
              <p className={styles.eyebrow}>SOFTWARE VALIDATION</p>
              <h2>Deterministic test run</h2>
            </div>
            <span className={styles.syntheticBadge}>SYNTHETIC — NOT A PROFIT CLAIM</span>
          </div>
          <EquityChart points={backtest.equityCurve} />
          <div className={styles.testMetrics}>
            <div><span>Net result</span><strong>{money(backtest.metrics.netProfit)}</strong></div>
            <div><span>Profit factor</span><strong>{number(backtest.metrics.profitFactor)}</strong></div>
            <div><span>Win rate</span><strong>{number(backtest.metrics.winRatePercent)}%</strong></div>
            <div><span>Max drawdown</span><strong>{number(backtest.metrics.maximumDrawdownPercent)}%</strong></div>
            <div><span>Trades</span><strong>{backtest.metrics.totalTrades}</strong></div>
          </div>
          <p className={styles.caption}>Use MT5 Strategy Tester with your broker&apos;s real ticks, then demo forward testing. Accuracy alone is not the promotion criterion.</p>
        </article>

        <article className={styles.panel}>
          <div className={styles.panelHeader}>
            <div>
              <p className={styles.eyebrow}>ACTIVE POLICY</p>
              <h2>Risk guardrails</h2>
            </div>
            <span className={styles.shield}>◇</span>
          </div>
          <dl className={styles.policyList}>
            <div><dt>Risk per trade</dt><dd>{number(data.risk.riskPerTradePercent)}%</dd></div>
            <div><dt>Daily loss lock</dt><dd>{instantProfile ? "0.10%" : `${number(data.risk.maximumDailyLossPercent)}%`}</dd></div>
            <div><dt>Account drawdown lock</dt><dd>{number(data.risk.maximumDrawdownPercent)}%</dd></div>
            <div><dt>Daily trade-count cap</dt><dd>None; risk locks still apply</dd></div>
            <div><dt>Stop / target</dt><dd>{number(data.strategy.stopAtrMultiple)}R ATR / {number(data.strategy.targetAtrMultiple)}R ATR</dd></div>
            <div><dt>Active profile</dt><dd>{instantProfile ? "Five risk-sized positions on one confirmed setup" : "Best closed-bar Nyao setup"}</dd></div>
            <div><dt>Fast profit milestone / loss ceiling</dt><dd>{money(telemetry.fastBasketTargetMoney)} / {money(telemetry.fastBasketLossMoney)}</dd></div>
            <div><dt>Open basket starting SL risk</dt><dd>{money(telemetry.fastBasketInitialRisk)}</dd></div>
          </dl>
          <div className={styles.safetyCallout}>
            <strong>Hybrid two-mode safety</strong>
            <p>Both profiles scan M1, M5, M15, H1, H4 and D1 closed-bar EMA context before any automatic entry. Fast opens five risk-sized positions on one qualified EMA reclaim, only if all five minimum lots fit inside 0.5% planned SL risk. It may close early when the scalp signal fades. At +1.5% of starting balance it starts trailing group profit instead of closing automatically; after five minutes it can keep holding while the short-term setup remains confirmed. The -0.5% loss trigger and individual broker stops remain, but gaps and slippage can exceed them. After a profitable close it can take the next fresh setup without a fixed cooldown; after a loss it pauses.</p>
          </div>
        </article>
      </section>

      <section className={styles.lowerGrid}>
        <article className={styles.panel}>
          <div className={styles.panelHeader}>
            <div>
              <p className={styles.eyebrow}>OPERATIONS</p>
              <h2>Recent control log</h2>
            </div>
            <span className={styles.revision}>rev {data.control.revision}</span>
          </div>
          <div className={styles.auditList}>
            {data.audit.slice(0, 6).map((item, index) => (
              <div key={`${item.time}-${index}`}>
                <span className={styles.auditDot} />
                <div><strong>{item.detail}</strong><small>{new Date(item.time).toLocaleString()}</small></div>
              </div>
            ))}
          </div>
        </article>

        <article className={styles.panel}>
          <div className={styles.panelHeader}>
            <div>
              <p className={styles.eyebrow}>DEMO PROMOTION</p>
              <h2>Evidence before real money</h2>
            </div>
          </div>
          <ol className={styles.checklist}>
            <li className={styles.complete}><span>1</span><div><strong>Safety architecture</strong><small>Protected orders, risk sizing, circuit breakers</small></div></li>
            <li><span>2</span><div><strong>MT5 real-tick backtest</strong><small>Multiple regimes with spread and commission</small></div></li>
            <li><span>3</span><div><strong>MT5 demo forward test</strong><small>Minimum 100 trades and 4 weeks</small></div></li>
            <li><span>4</span><div><strong>Manual real-mode review</strong><small>No automatic promotion to live funds</small></div></li>
          </ol>
        </article>
      </section>

      <footer className={styles.footer}>
        <span>Polling every 2 seconds · Control revision {data.control.revision}</span>
        <span>Autonomous does not mean risk-free. Keep MT5 and the control service monitored.</span>
      </footer>
    </main>
  );
}
