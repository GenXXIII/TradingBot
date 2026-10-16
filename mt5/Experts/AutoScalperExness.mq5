#property copyright "AutoScalpingTrading"
#property version   "1.04"
#property strict
#property description "Deterministic MT5 scalper with demo-first safety gates. No AI."

#include <Trade/Trade.mqh>

input group "Safety - keep these conservative"
input bool   InpAllowRealAccount         = false;
input double InpRiskPerTradePercent      = 0.25;
input double InpMaximumDailyLossPercent  = 1.50;
input double InpMaximumDrawdownPercent   = 5.00;
input int    InpMaximumSpreadPoints      = 35;
input long   InpMagicNumber              = 26101401;
input int    InpSlippagePoints           = 10;

input group "Deterministic strategy"
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M1;
input ENUM_TIMEFRAMES InpTrendTimeframe  = PERIOD_M5;
input int    InpFastEmaPeriod            = 20;
input int    InpSlowEmaPeriod            = 50;
input int    InpRsiPeriod                = 14;
input int    InpAtrPeriod                = 14;
input int    InpAdxPeriod                = 14;
input double InpMinimumAdx               = 18.0;
input double InpStopAtrMultiple          = 1.30;
input double InpTargetAtrMultiple        = 1.80;
input int    InpCooldownBars             = 5;
input bool   InpEnableLong               = true;
input bool   InpEnableShort              = true;
input int    InpSessionStartHour         = 7;
input int    InpSessionEndHour           = 20;
input bool   InpAutoRunInStrategyTester  = true;
input int    InpMinimumOptimizationTrades = 100;

input group "Instant demo market scalping"
input bool   InpTestInstantScalp          = false;
input int    InpInstantBasketPositions    = 5;
input double InpInstantFixedLotSize       = 0.01;
input double InpInstantBasketRiskPercent  = 0.50;
input double InpInstantMaximumDailyLossPercent = 0.10;
input int    InpInstantMaximumSpreadPoints = 25;
input double InpInstantMinimumAdx         = 22.0;
input double InpInstantMaximumEmaDistanceAtr = 0.35;
input int    InpInstantMinimumHoldSeconds = 1;
input int    InpInstantProfitWindowSeconds = 5;
input int    InpInstantMaximumHoldSeconds = 300;
input int    InpInstantCooldownSeconds    = 30;
input int    InpInstantLossCooldownSeconds = 180;
input double InpInstantBasketProfitMoney  = 0.50;
input double InpInstantBasketLossMoney    = 5.00;
input double InpInstantExpectedMoveAtr    = 0.35;
input double InpInstantRewardSpreadRatio  = 1.25;
input double InpInstantEmergencyStopAtr   = 1.00;

input group "Local dashboard bridge"
input string InpControlPlaneUrl          = "http://127.0.0.1:5182";
input string InpBridgeKey                = "local-demo-key-change-me";
input string InpTerminalId               = "mt5-demo-01";
input int    InpBridgeTimeoutMs          = 1200;

CTrade g_trade;
int g_fastHandle = INVALID_HANDLE;
int g_slowHandle = INVALID_HANDLE;
int g_trendFastHandle = INVALID_HANDLE;
int g_trendSlowHandle = INVALID_HANDLE;
int g_rsiHandle = INVALID_HANDLE;
int g_atrHandle = INVALID_HANDLE;
int g_adxHandle = INVALID_HANDLE;

string g_mode = "paused";
string g_profile = "normal";
string g_lastReason = "Initialized in safe paused mode";
long g_lastCommandRevision = 0;
datetime g_lastSignalBar = 0;
datetime g_lastEntryBar = 0;
datetime g_lastExitTime = 0;
datetime g_lastInstantAttemptTime = 0;
datetime g_lastInstantEntryBar = 0;
datetime g_lastInstantLossTime = 0;
double g_peakEquity = 0.0;
bool g_localRiskLock = false;
bool g_isTester = false;

int OnInit()
  {
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippagePoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   g_isTester=(bool)MQLInfoInteger(MQL_TESTER);

   g_fastHandle=iMA(_Symbol,InpSignalTimeframe,InpFastEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_slowHandle=iMA(_Symbol,InpSignalTimeframe,InpSlowEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_trendFastHandle=iMA(_Symbol,InpTrendTimeframe,InpFastEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_trendSlowHandle=iMA(_Symbol,InpTrendTimeframe,InpSlowEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_rsiHandle=iRSI(_Symbol,InpSignalTimeframe,InpRsiPeriod,PRICE_CLOSE);
   g_atrHandle=iATR(_Symbol,InpSignalTimeframe,InpAtrPeriod);
   g_adxHandle=iADX(_Symbol,InpSignalTimeframe,InpAdxPeriod);

   if(g_fastHandle==INVALID_HANDLE || g_slowHandle==INVALID_HANDLE ||
      g_trendFastHandle==INVALID_HANDLE || g_trendSlowHandle==INVALID_HANDLE ||
      g_rsiHandle==INVALID_HANDLE || g_atrHandle==INVALID_HANDLE || g_adxHandle==INVALID_HANDLE)
     {
      Print("Indicator handle initialization failed. Error=",GetLastError());
      return INIT_FAILED;
     }

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_isTester && InpAutoRunInStrategyTester)
     {
      g_mode="running";
      g_profile=(InpTestInstantScalp ? "instantscalp" : "normal");
      g_lastReason="MT5 Strategy Tester mode: autonomous execution enabled";
     }
   else if(IsRealAccount() && !InpAllowRealAccount)
     {
      g_mode="locked";
      g_lastReason="REAL ACCOUNT BLOCKED: InpAllowRealAccount is false";
      Print(g_lastReason);
     }

   EventSetTimer(2);
   SendTelemetry();
   UpdateChartComment();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ReleaseHandle(g_fastHandle);
   ReleaseHandle(g_slowHandle);
   ReleaseHandle(g_trendFastHandle);
   ReleaseHandle(g_trendSlowHandle);
   ReleaseHandle(g_rsiHandle);
   ReleaseHandle(g_atrHandle);
   ReleaseHandle(g_adxHandle);
   Comment("");
  }

void OnTimer()
  {
   if(g_isTester)
      return;
   PollControlPlane();
   SendTelemetry();
   UpdateChartComment();
  }

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(transaction.type!=TRADE_TRANSACTION_DEAL_ADD || transaction.deal==0 ||
      !HistoryDealSelect(transaction.deal))
      return;
   if(HistoryDealGetInteger(transaction.deal,DEAL_MAGIC)!=InpMagicNumber ||
      HistoryDealGetString(transaction.deal,DEAL_SYMBOL)!=_Symbol)
      return;
   long entry=HistoryDealGetInteger(transaction.deal,DEAL_ENTRY);
   if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT || entry==DEAL_ENTRY_OUT_BY)
     {
      g_lastExitTime=TimeTradeServer();
      if(g_profile=="instantscalp" &&
         HistoryDealGetDouble(transaction.deal,DEAL_PROFIT)+
         HistoryDealGetDouble(transaction.deal,DEAL_COMMISSION)+
         HistoryDealGetDouble(transaction.deal,DEAL_FEE)<0.0)
         g_lastInstantLossTime=g_lastExitTime;
     }
  }

double OnTester()
  {
   double trades=TesterStatistics(STAT_TRADES);
   if(trades<InpMinimumOptimizationTrades)
      return 0.0;
   double profitFactor=TesterStatistics(STAT_PROFIT_FACTOR);
   double drawdownPercent=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double expectedPayoff=TesterStatistics(STAT_EXPECTED_PAYOFF);
   if(profitFactor<=0 || expectedPayoff<=0)
      return 0.0;
   return (profitFactor*MathSqrt(trades)*expectedPayoff)/(1.0+drawdownPercent);
  }

void OnTick()
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>g_peakEquity)
      g_peakEquity=equity;

   EnforceCircuitBreakers();
   if(g_profile=="instantscalp")
      ManageInstantBasket();
   else
      ManageOpenPosition();

   if(g_mode!="running" || g_localRiskLock)
      return;

   if(g_profile=="instantscalp")
     {
      int instantPositions=CountBotPositions();
      if(instantPositions>0)
         return;

      string instantGate="";
      if(!CanOpenTrade(instantGate,true))
        {
         g_lastReason="Fast scalp waiting: "+instantGate;
         return;
        }
      string instantReason="";
      int instantDirection=EvaluateInstantDirection(instantReason);
      g_lastReason=instantReason;
      if(instantDirection!=0)
         OpenInstantBasket(instantDirection);
      return;
     }

   datetime currentBar=iTime(_Symbol,InpSignalTimeframe,0);
   if(currentBar<=0 || currentBar==g_lastSignalBar)
      return;

   g_lastSignalBar=currentBar;
   string reason="";
   if(!CanOpenTrade(reason,false))
     {
      g_lastReason=reason;
      return;
     }

   int direction=EvaluateClosedBarSignal(reason);
   g_lastReason=reason;
   if(direction!=0)
      OpenRiskSizedPosition(direction,false);
  }

bool ValidateInputs()
  {
   if(InpRiskPerTradePercent<=0 || InpRiskPerTradePercent>2.0)
     {
      Print("Risk per trade must be greater than 0 and no more than 2%.");
      return false;
     }
   if(InpMaximumDailyLossPercent<=0 || InpMaximumDrawdownPercent<=0 ||
      InpFastEmaPeriod<2 || InpSlowEmaPeriod<=InpFastEmaPeriod ||
      InpStopAtrMultiple<=0 || InpTargetAtrMultiple<=0 ||
      InpInstantBasketPositions<2 || InpInstantBasketPositions>10 ||
      InpInstantFixedLotSize<=0 ||
      InpInstantBasketRiskPercent<=0 || InpInstantBasketRiskPercent>0.50 ||
      InpInstantMaximumDailyLossPercent<=0 ||
      InpInstantMaximumDailyLossPercent>InpMaximumDailyLossPercent ||
      InpInstantMaximumSpreadPoints<1 ||
      InpInstantMaximumSpreadPoints>InpMaximumSpreadPoints ||
      InpInstantMinimumAdx<InpMinimumAdx ||
      InpInstantMaximumEmaDistanceAtr<=0 ||
      InpInstantMinimumHoldSeconds<1 ||
      InpInstantProfitWindowSeconds<InpInstantMinimumHoldSeconds ||
      InpInstantMaximumHoldSeconds<=InpInstantProfitWindowSeconds ||
      InpInstantCooldownSeconds<0 || InpInstantLossCooldownSeconds<0 ||
      InpInstantBasketProfitMoney<=0 || InpInstantBasketLossMoney<=0 ||
      InpInstantExpectedMoveAtr<=0 || InpInstantRewardSpreadRatio<1.0 ||
      InpInstantEmergencyStopAtr<=0)
     {
      Print("One or more safety/strategy inputs are invalid.");
      return false;
     }
   return true;
  }

int EvaluateClosedBarSignal(string &reason)
  {
   double fast=BufferValue(g_fastHandle,1);
   double previousFast=BufferValue(g_fastHandle,2);
   double slow=BufferValue(g_slowHandle,1);
   double trendFast=BufferValue(g_trendFastHandle,1);
   double trendSlow=BufferValue(g_trendSlowHandle,1);
   double rsi=BufferValue(g_rsiHandle,1);
   double atr=BufferValue(g_atrHandle,1);
   double adx=BufferValue(g_adxHandle,1);
   double previousClose=iClose(_Symbol,InpSignalTimeframe,2);
   double close=iClose(_Symbol,InpSignalTimeframe,1);
   double open=iOpen(_Symbol,InpSignalTimeframe,1);

   if(fast==EMPTY_VALUE || previousFast==EMPTY_VALUE || slow==EMPTY_VALUE ||
      trendFast==EMPTY_VALUE || trendSlow==EMPTY_VALUE || rsi==EMPTY_VALUE ||
      atr==EMPTY_VALUE || adx==EMPTY_VALUE || close<=0)
     {
      reason="Indicator warm-up is incomplete";
      return 0;
     }
   if(adx<InpMinimumAdx || atr<=0)
     {
      reason="ADX or volatility filter rejected the setup";
      return 0;
     }

   bool longTrend=(fast>slow && trendFast>trendSlow);
   bool shortTrend=(fast<slow && trendFast<trendSlow);
   bool longRecovery=(previousClose<=previousFast && close>fast && close>open);
   bool shortRecovery=(previousClose>=previousFast && close<fast && close<open);

   if(InpEnableLong && longTrend && longRecovery && rsi>=52.0 && rsi<=68.0)
     {
      reason="BUY: M1/M5 EMA trend + pullback recovery + RSI/ADX confirmed";
      return 1;
     }
   if(InpEnableShort && shortTrend && shortRecovery && rsi>=32.0 && rsi<=48.0)
     {
      reason="SELL: M1/M5 EMA trend + pullback rejection + RSI/ADX confirmed";
      return -1;
     }

   reason="No fully confirmed closed-bar setup";
   return 0;
  }

int EvaluateInstantDirection(string &reason)
  {
   MqlTick tick={};
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<=0)
     {
      reason="Instant scalp waiting for the next usable market tick";
      return 0;
     }

   double fast=BufferValue(g_fastHandle,0);
   double previousFast=BufferValue(g_fastHandle,1);
   double slow=BufferValue(g_slowHandle,0);
   double trendFast=BufferValue(g_trendFastHandle,0);
   double previousTrendFast=BufferValue(g_trendFastHandle,1);
   double trendSlow=BufferValue(g_trendSlowHandle,0);
   double rsi=BufferValue(g_rsiHandle,0);
   double adx=BufferValue(g_adxHandle,0);
   double atr=BufferValue(g_atrHandle,0);
   double open=iOpen(_Symbol,InpSignalTimeframe,0);
   double previousOpen=iOpen(_Symbol,InpSignalTimeframe,1);
   double previousClose=iClose(_Symbol,InpSignalTimeframe,1);
   if(fast==EMPTY_VALUE || previousFast==EMPTY_VALUE || slow==EMPTY_VALUE ||
      trendFast==EMPTY_VALUE || previousTrendFast==EMPTY_VALUE ||
      trendSlow==EMPTY_VALUE || rsi==EMPTY_VALUE || adx==EMPTY_VALUE ||
      atr==EMPTY_VALUE || atr<=0 || open<=0 || previousOpen<=0 || previousClose<=0)
     {
      reason="Fast scalp waiting for live indicators";
      return 0;
     }
   if(adx<InpInstantMinimumAdx)
     {
      reason=StringFormat("Fast scalp waiting for stronger momentum: ADX %.1f < %.1f",adx,InpInstantMinimumAdx);
      return 0;
     }

   double midpoint=(tick.bid+tick.ask)/2.0;
   if(MathAbs(midpoint-fast)>atr*InpInstantMaximumEmaDistanceAtr)
     {
      reason="Fast scalp waiting: price is too far from the M1 EMA";
      return 0;
     }

   bool buySetup=(InpEnableLong && fast>slow && trendFast>trendSlow &&
                  fast>previousFast && trendFast>previousTrendFast &&
                  previousClose>previousOpen && midpoint>open && midpoint>fast &&
                  rsi>=52.0 && rsi<=68.0);
   bool sellSetup=(InpEnableShort && fast<slow && trendFast<trendSlow &&
                   fast<previousFast && trendFast<previousTrendFast &&
                   previousClose<previousOpen && midpoint<open && midpoint<fast &&
                   rsi>=32.0 && rsi<=48.0);
   if(!buySetup && !sellSetup)
     {
      reason="Fast scalp waiting for confirmed buy or sell alignment";
      return 0;
     }

   reason=(buySetup ? "Fast scalp confirmed BUY" : "Fast scalp confirmed SELL");
   return (buySetup ? 1 : -1);
  }

bool CanOpenTrade(string &reason,const bool instantMode=false)
  {
   if(instantMode && !g_isTester && AccountModeName()!="demo")
     {
      reason="instant scalp is demo-only";
      return false;
     }
   if(IsRealAccount() && !InpAllowRealAccount)
     {
      reason="Real-account safety gate blocked entry";
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      reason="MT5 is disconnected";
      return false;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      reason="Algo Trading is disabled in MT5 or for this EA";
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      reason="Expert trading is not allowed by terminal/account";
      return false;
     }
   if(instantMode &&
      (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      reason="instant position baskets require an MT5 hedging account";
      return false;
     }
   if(CountBotPositions()>0)
     {
      reason=(instantMode ? "instant scalp basket is already active" : "One-position limit is active");
      return false;
     }
   double maximumSpread=(instantMode ? InpInstantMaximumSpreadPoints : InpMaximumSpreadPoints);
   if(CurrentSpreadPoints()>maximumSpread)
     {
      reason=(instantMode ? "fast scalp spread is above configured maximum" : "Spread is above configured maximum");
      return false;
     }
   double maximumDailyLossPercent=(instantMode ? InpInstantMaximumDailyLossPercent : InpMaximumDailyLossPercent);
   if(DailyRealizedPnl()<=-(AccountInfoDouble(ACCOUNT_BALANCE)*maximumDailyLossPercent/100.0))
     {
      reason="Daily-loss circuit breaker is active";
      return false;
     }

   if(!instantMode)
     {
      MqlDateTime now={};
      TimeToStruct(TimeTradeServer(),now);
      bool inSession=(InpSessionStartHour<InpSessionEndHour)
         ? (now.hour>=InpSessionStartHour && now.hour<InpSessionEndHour)
         : (now.hour>=InpSessionStartHour || now.hour<InpSessionEndHour);
      if(!inSession)
        {
         reason="Outside configured broker-server session";
         return false;
        }
     }

   if(instantMode)
     {
      datetime currentBar=iTime(_Symbol,InpSignalTimeframe,0);
      if(currentBar<=0 || currentBar==g_lastInstantEntryBar)
        {
         reason="Fast scalp already entered this M1 candle";
         return false;
        }
      if(g_lastInstantLossTime>0 &&
         TimeTradeServer()-g_lastInstantLossTime<InpInstantLossCooldownSeconds)
        {
         reason="Fast scalp recovery pause after a loss";
         return false;
        }
      datetime lastActivity=(g_lastExitTime>g_lastInstantAttemptTime ? g_lastExitTime : g_lastInstantAttemptTime);
      if(lastActivity>0 && TimeTradeServer()-lastActivity<InpInstantCooldownSeconds)
        {
         reason="fast scalp cooldown is active";
         return false;
        }
     }
   else
     {
      int barsSinceEntry=(g_lastEntryBar==0) ? 100000 : iBarShift(_Symbol,InpSignalTimeframe,g_lastEntryBar,false);
      if(barsSinceEntry>=0 && barsSinceEntry<InpCooldownBars)
        {
         reason="Post-trade cooldown is active";
         return false;
        }
     }
   return true;
  }

bool OpenInstantBasket(const int direction)
  {
   string gateReason="";
   if(!CanOpenTrade(gateReason,true))
     {
      g_lastReason="Instant basket rejected: "+gateReason;
      return false;
     }

   MqlTick tick={};
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<=0)
     {
      g_lastReason="Instant basket rejected: no current market tick";
      return false;
     }
   double atr=BufferValue(g_atrHandle,0);
   if(atr==EMPTY_VALUE || atr<=0)
     {
      g_lastReason="Instant basket rejected: ATR is unavailable";
      return false;
     }

   double spreadPrice=tick.ask-tick.bid;
   double plannedMove=atr*InpInstantExpectedMoveAtr;
   if(plannedMove<spreadPrice*InpInstantRewardSpreadRatio)
     {
      g_lastReason="Fast scalp waiting: expected movement does not cover spread cost";
      return false;
     }

   double entry=(direction>0 ? tick.ask : tick.bid);
   double minimumDistance=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double stopDistance=MathMax(atr*InpInstantEmergencyStopAtr,spreadPrice+minimumDistance+_Point);
   double stop=NormalizeDouble(direction>0 ? entry-stopDistance : entry+stopDistance,_Digits);

   double minimumVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maximumVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volumeStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(volumeStep<=0)
     {
      g_lastReason="Instant basket rejected: broker volume step is unavailable";
      return false;
     }
   double volume=MathFloor(InpInstantFixedLotSize/volumeStep)*volumeStep;
   volume=NormalizeDouble(MathMin(volume,maximumVolume),VolumeDigits(volumeStep));
   if(volume<minimumVolume)
     {
      g_lastReason="Instant basket rejected: 0.01 lot is below the broker minimum";
      return false;
     }

   double lossPerPosition=0.0;
   ENUM_ORDER_TYPE orderType=(direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcProfit(orderType,_Symbol,volume,entry,stop,lossPerPosition) || lossPerPosition==0.0)
     {
      g_lastReason="Instant basket rejected: emergency risk could not be calculated";
      return false;
     }
   double maximumBasketLoss=AccountInfoDouble(ACCOUNT_BALANCE)*InpInstantBasketRiskPercent/100.0;
   int positionsAllowedByRisk=(int)MathFloor(maximumBasketLoss/MathAbs(lossPerPosition));
   int requestedPositions=(int)MathMin(InpInstantBasketPositions,positionsAllowedByRisk);
   if(requestedPositions<=0)
     {
      g_lastReason="Instant basket blocked: 0.01 lot exceeds the emergency basket-risk limit";
      return false;
     }

   g_lastInstantAttemptTime=TimeTradeServer();
   int opened=0;
   for(int i=0;i<requestedPositions;i++)
     {
      bool submitted=(direction>0)
         ? g_trade.Buy(volume,_Symbol,0.0,stop,0.0,"AutoScalper instant demo")
         : g_trade.Sell(volume,_Symbol,0.0,stop,0.0,"AutoScalper instant demo");
      if(!submitted || !TradeResultAccepted())
        {
         PrintFormat("Instant basket order %d/%d rejected: %d %s",i+1,requestedPositions,
                     g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
         break;
        }
      opened++;
     }

   if(opened==0)
     {
      g_lastReason="Fast scalp basket was rejected by the trade server; retry delayed";
      return false;
     }

   g_lastEntryBar=iTime(_Symbol,InpSignalTimeframe,0);
   g_lastInstantEntryBar=g_lastEntryBar;
   g_lastReason=StringFormat("Fast quality %s basket opened: %d positions x %.2f lots",
                             direction>0 ? "BUY" : "SELL",opened,volume);
   return true;
  }

bool OpenRiskSizedPosition(const int direction,const bool manualEntry)
  {
   string gateReason="";
   if(!CanOpenTrade(gateReason,false))
     {
      g_lastReason=(manualEntry ? "Manual entry rejected: " : "Entry rejected: ")+gateReason;
      return false;
     }

   MqlTick tick={};
   if(!SymbolInfoTick(_Symbol,tick))
     {
      g_lastReason="No current market tick available";
      return false;
     }

   double atr=BufferValue(g_atrHandle,1);
   if(atr==EMPTY_VALUE || atr<=0)
     {
      g_lastReason="ATR is unavailable for protected entry";
      return false;
     }

   double entry=(direction>0 ? tick.ask : tick.bid);
   double stopDistance=atr*InpStopAtrMultiple;
   double targetDistance=atr*InpTargetAtrMultiple;
   double minimumDistance=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   stopDistance=MathMax(stopDistance,minimumDistance+_Point);
   double stop=NormalizeDouble(direction>0 ? entry-stopDistance : entry+stopDistance,_Digits);
   targetDistance=MathMax(targetDistance,minimumDistance+_Point);
   double target=NormalizeDouble(direction>0 ? entry+targetDistance : entry-targetDistance,_Digits);
   double volume=CalculateRiskVolume(direction,entry,stop,InpRiskPerTradePercent);
   if(volume<=0)
     {
      g_lastReason="Risk sizing produced no valid broker volume";
      return false;
     }

   string comment=manualEntry ? "AutoScalper manual" : "AutoScalper deterministic";
   bool submitted=(direction>0)
      ? g_trade.Buy(volume,_Symbol,0.0,stop,target,comment)
      : g_trade.Sell(volume,_Symbol,0.0,stop,target,comment);
   if(!submitted || (g_trade.ResultRetcode()!=TRADE_RETCODE_DONE &&
                     g_trade.ResultRetcode()!=TRADE_RETCODE_PLACED &&
                     g_trade.ResultRetcode()!=TRADE_RETCODE_DONE_PARTIAL))
     {
      g_lastReason=StringFormat("Order rejected: %d %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      Print(g_lastReason);
      return false;
     }

   g_lastEntryBar=iTime(_Symbol,InpSignalTimeframe,0);
   g_lastReason=StringFormat("%s %s %.2f lots with SL/TP",manualEntry ? "Manual" : "Automatic",direction>0 ? "BUY" : "SELL",volume);
   return true;
  }

double CalculateRiskVolume(const int direction,const double entry,const double stop,const double riskPercent)
  {
   double lossPerLot=0.0;
   ENUM_ORDER_TYPE orderType=(direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcProfit(orderType,_Symbol,1.0,entry,stop,lossPerLot) || lossPerLot==0.0)
      return 0.0;

   double riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*riskPercent/100.0;
   double rawVolume=riskMoney/MathAbs(lossPerLot);
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maximum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0)
      return 0.0;
   double volume=MathFloor(rawVolume/step)*step;
   if(volume<minimum)
      return 0.0;
   volume=MathMin(volume,maximum);
   return NormalizeDouble(volume,VolumeDigits(step));
  }

void ManageInstantBasket()
  {
   int positions=CountBotPositions();
   if(positions<=0)
      return;

   double totalVolume=0.0;
   double basketPnl=0.0;
   datetime openedAt=OldestBotPositionTime();
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket) ||
         PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;
      double volume=PositionGetDouble(POSITION_VOLUME);
      totalVolume+=volume;
      basketPnl+=PositionGetDouble(POSITION_PROFIT);
     }
   if(totalVolume<=0 || openedAt<=0)
      return;

   if(TimeTradeServer()-openedAt>=InpInstantMinimumHoldSeconds &&
      basketPnl>=InpInstantBasketProfitMoney)
     {
      CloseInstantBasket("Instant scalp basket closed at market with positive basket P/L");
      return;
     }
   if(TimeTradeServer()-openedAt>=InpInstantProfitWindowSeconds && basketPnl>0.0)
     {
      CloseInstantBasket("Fast scalp basket closed at market with available positive P/L");
      return;
     }
   if(basketPnl<=-InpInstantBasketLossMoney)
     {
      CloseInstantBasket("Fast scalp basket closed at market on emergency basket loss cutoff");
      return;
     }
   if(TimeTradeServer()-openedAt>=InpInstantMaximumHoldSeconds)
      CloseInstantBasket("Fast scalp basket closed at market after five-minute hard maximum");
  }

void ManageOpenPosition()
  {
   ulong ticket=FindBotPosition();
   if(ticket==0 || !PositionSelectByTicket(ticket))
      return;

   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double stop=PositionGetDouble(POSITION_SL);
   double target=PositionGetDouble(POSITION_TP);
   long type=PositionGetInteger(POSITION_TYPE);
   MqlTick tick={};
   if(!SymbolInfoTick(_Symbol,tick) || stop<=0)
      return;

   double current=(type==POSITION_TYPE_BUY ? tick.bid : tick.ask);
   double initialRisk=MathAbs(entry-stop);
   if(initialRisk<=0)
      return;
   double favorable=(type==POSITION_TYPE_BUY ? current-entry : entry-current);

   if(target<=0 || favorable<initialRisk)
      return;

   double breakEven=NormalizeDouble(type==POSITION_TYPE_BUY ? entry+_Point : entry-_Point,_Digits);
   bool improves=(type==POSITION_TYPE_BUY ? breakEven>stop : breakEven<stop);
   if(improves)
     {
      bool modified=g_trade.PositionModify(ticket,breakEven,target);
      if(!modified || !TradeResultAccepted())
         Print("Break-even modification failed: ",g_trade.ResultRetcodeDescription());
     }
  }

bool CloseBotPosition(const ulong ticket,const string reason)
  {
   bool submitted=g_trade.PositionClose(ticket);
   if(!submitted || !TradeResultAccepted())
     {
      g_lastReason=StringFormat("Market close rejected: %d %s",g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
      Print(g_lastReason);
      return false;
     }
   g_lastExitTime=TimeTradeServer();
   g_lastReason=reason;
   return true;
  }

bool CloseInstantBasket(const string reason)
  {
   int closed=0;
   int failed=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket) ||
         PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;
      bool submitted=g_trade.PositionClose(ticket);
      if(submitted && TradeResultAccepted())
         closed++;
      else
        {
         failed++;
         PrintFormat("Instant basket close failed for %I64u: %d %s",ticket,
                     g_trade.ResultRetcode(),g_trade.ResultRetcodeDescription());
        }
     }
   if(closed>0)
      g_lastExitTime=TimeTradeServer();
   g_lastReason=StringFormat("%s (%d closed, %d failed)",reason,closed,failed);
   return closed>0 && failed==0;
  }

bool TradeResultAccepted()
  {
   uint code=g_trade.ResultRetcode();
   return code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_PLACED ||
          code==TRADE_RETCODE_DONE_PARTIAL || code==TRADE_RETCODE_NO_CHANGES;
  }

void EnforceCircuitBreakers()
  {
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdown=(g_peakEquity>0 ? 100.0*(g_peakEquity-equity)/g_peakEquity : 0.0);
   double maximumDailyLossPercent=(g_profile=="instantscalp" ?
                                   InpInstantMaximumDailyLossPercent : InpMaximumDailyLossPercent);
   bool dailyBreach=(DailyRealizedPnl()<=-(balance*maximumDailyLossPercent/100.0));
   bool drawdownBreach=(drawdown>=InpMaximumDrawdownPercent);
   if(!dailyBreach && !drawdownBreach)
      return;

   if(!g_localRiskLock)
     {
      g_localRiskLock=true;
      g_mode="locked";
      g_lastReason=(drawdownBreach ? "Maximum drawdown" : "Daily loss")+" circuit breaker locked the bot";
      FlattenBotExposure();
      Print(g_lastReason);
     }
  }

void FlattenBotExposure()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)
         g_trade.PositionClose(ticket);
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)==InpMagicNumber)
         g_trade.OrderDelete(ticket);
     }
  }

void PollControlPlane()
  {
   if(g_isTester)
      return;
   char requestData[];
   char responseData[];
   string responseHeaders="";
   ArrayResize(requestData,0);
   string headers="X-Bot-Key: "+InpBridgeKey+"\r\n";
   ResetLastError();
   int status=WebRequest("GET",InpControlPlaneUrl+"/api/mt5/command",headers,InpBridgeTimeoutMs,requestData,responseData,responseHeaders);
   if(status!=200)
     {
      if(status==-1)
         g_lastReason=StringFormat("Dashboard bridge unavailable (error %d); local safety remains active",GetLastError());
      return;
     }

   string response=CharArrayToString(responseData,0,-1,CP_UTF8);
   long revision=(long)StringToInteger(ResponseValue(response,"revision"));
   if(revision<=g_lastCommandRevision)
      return;

   string requestedMode=ResponseValue(response,"mode");
   string requestedProfile=ResponseValue(response,"profile");
   string action=ResponseValue(response,"action");
   bool hybridRequested=(requestedProfile=="hybrid");
   if(hybridRequested)
     {
      g_mode="paused";
      g_profile="normal";
      if(action=="flatten")
        {
         FlattenBotExposure();
         g_lastReason=(requestedMode=="locked" ? "Emergency stop also flattened the original EA" : "Original EA exposure closed by operator");
        }
      else
         g_lastReason="Original EA paused: Nyao Hybrid profile is selected";
     }
   else if(action=="resetlock")
     {
      g_localRiskLock=false;
      g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      g_mode="paused";
      g_profile="normal";
      g_lastReason="Risk lock reset; bot remains paused";
     }
   else
     {
      bool instantRequested=(requestedProfile=="instantscalp");
      if(requestedMode=="running" && instantRequested && AccountModeName()!="demo")
        {
         g_mode="locked";
         g_profile="normal";
         g_lastReason="Instant scalp rejected: MT5 demo account required";
        }
      else if(requestedMode=="running" && IsRealAccount() && !InpAllowRealAccount)
        {
         g_mode="locked";
         g_profile="normal";
         g_lastReason="Dashboard start rejected by real-account safety gate";
        }
      else if(!g_localRiskLock)
        {
         g_mode=requestedMode;
         g_profile=(instantRequested ? "instantscalp" : "normal");
        }

      if(action=="flatten")
        {
         FlattenBotExposure();
         g_lastReason=(requestedMode=="locked" ? "Emergency stop applied" : "Bot position closed by operator");
        }
      else if(action=="manualbuy")
         OpenRiskSizedPosition(1,true);
      else if(action=="manualsell")
         OpenRiskSizedPosition(-1,true);
      else if(action=="none")
         g_lastReason="Operator changed bot mode to "+g_mode+" / "+g_profile;
     }

   g_lastCommandRevision=revision;
   SendTelemetry();
  }

void SendTelemetry()
  {
   if(g_isTester)
      return;
   MqlTick tick={};
   SymbolInfoTick(_Symbol,tick);
   int positionCount=0;
   string side="flat";
   double volume=0.0,weightedEntry=0.0,entry=0.0,pnl=0.0;
   long firstType=-1;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket) ||
         PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;
      double positionVolume=PositionGetDouble(POSITION_VOLUME);
      if(firstType<0)
         firstType=PositionGetInteger(POSITION_TYPE);
      positionCount++;
      volume+=positionVolume;
      weightedEntry+=PositionGetDouble(POSITION_PRICE_OPEN)*positionVolume;
      pnl+=PositionGetDouble(POSITION_PROFIT);
     }
   if(positionCount>0 && volume>0)
     {
      side=(firstType==POSITION_TYPE_BUY ? "long" : "short");
      entry=weightedEntry/volume;
     }

   string body="terminal_id="+UrlEncode(InpTerminalId)+
      "&account_mode="+AccountModeName()+
      "&broker="+UrlEncode(AccountInfoString(ACCOUNT_COMPANY))+
      "&symbol="+UrlEncode(_Symbol)+
      "&balance="+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+
      "&equity="+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+
      "&daily_pnl="+DoubleToString(DailyRealizedPnl(),2)+
      "&bid="+DoubleToString(tick.bid,_Digits)+
      "&ask="+DoubleToString(tick.ask,_Digits)+
      "&spread_points="+DoubleToString(CurrentSpreadPoints(),1)+
      "&position_side="+side+
      "&position_count="+IntegerToString(positionCount)+
      "&position_volume="+DoubleToString(volume,2)+
      "&position_entry="+DoubleToString(entry,_Digits)+
      "&position_pnl="+DoubleToString(pnl,2)+
      "&bot_mode="+g_mode+
      "&strategy_profile="+g_profile+
      "&last_reason="+UrlEncode(g_lastReason)+
      "&last_command_revision="+IntegerToString(g_lastCommandRevision);

   char data[];
   char result[];
   string resultHeaders="";
   StringToCharArray(body,data,0,WHOLE_ARRAY,CP_UTF8);
   if(ArraySize(data)>0)
      ArrayResize(data,ArraySize(data)-1);
   string headers="Content-Type: application/x-www-form-urlencoded\r\nX-Bot-Key: "+InpBridgeKey+"\r\n";
   WebRequest("POST",InpControlPlaneUrl+"/api/mt5/telemetry",headers,InpBridgeTimeoutMs,data,result,resultHeaders);
  }

ulong FindBotPosition()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)
         return ticket;
     }
   return 0;
  }

int CountBotPositions()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)
         count++;
     }
   return count;
  }

datetime OldestBotPositionTime()
  {
   datetime oldest=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket) ||
         PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;
      datetime openedAt=(datetime)PositionGetInteger(POSITION_TIME);
      if(oldest==0 || openedAt<oldest)
         oldest=openedAt;
     }
   return oldest;
  }

long FirstBotPositionType()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==InpMagicNumber)
         return PositionGetInteger(POSITION_TYPE);
     }
   return -1;
  }

double DailyRealizedPnl()
  {
   datetime start=StartOfServerDay();
   if(!HistorySelect(start,TimeTradeServer()))
      return 0.0;
   double total=0.0;
   int count=HistoryDealsTotal();
   for(int i=0;i<count;i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0 || HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber ||
         HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol)
         continue;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT || entry==DEAL_ENTRY_OUT_BY)
         total+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+
                HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
                HistoryDealGetDouble(ticket,DEAL_SWAP)+
                HistoryDealGetDouble(ticket,DEAL_FEE);
     }
   return total;
  }

int TradesToday()
  {
   if(!HistorySelect(StartOfServerDay(),TimeTradeServer()))
      return 0;
   int trades=0;
   int count=HistoryDealsTotal();
   for(int i=0;i<count;i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket>0 && HistoryDealGetInteger(ticket,DEAL_MAGIC)==InpMagicNumber &&
         HistoryDealGetString(ticket,DEAL_SYMBOL)==_Symbol &&
         HistoryDealGetInteger(ticket,DEAL_ENTRY)==DEAL_ENTRY_IN)
         trades++;
     }
   return trades;
  }

datetime StartOfServerDay()
  {
   MqlDateTime parts={};
   TimeToStruct(TimeTradeServer(),parts);
   parts.hour=0;
   parts.min=0;
   parts.sec=0;
   return StructToTime(parts);
  }

double CurrentSpreadPoints()
  {
   MqlTick tick={};
   if(!SymbolInfoTick(_Symbol,tick) || _Point<=0)
      return 999999.0;
   return (tick.ask-tick.bid)/_Point;
  }

double BufferValue(const int handle,const int shift)
  {
   double value[1];
   if(CopyBuffer(handle,0,shift,1,value)!=1)
      return EMPTY_VALUE;
   return value[0];
  }

void ReleaseHandle(int &handle)
  {
   if(handle!=INVALID_HANDLE)
     {
      IndicatorRelease(handle);
      handle=INVALID_HANDLE;
     }
  }

bool IsRealAccount()
  {
   return ((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL);
  }

string AccountModeName()
  {
   ENUM_ACCOUNT_TRADE_MODE mode=(ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode==ACCOUNT_TRADE_MODE_DEMO)
      return "demo";
   if(mode==ACCOUNT_TRADE_MODE_CONTEST)
      return "contest";
   return "real";
  }

int VolumeDigits(const double step)
  {
   int digits=0;
   double value=step;
   while(digits<8 && MathAbs(value-MathRound(value))>0.00000001)
     {
      value*=10.0;
      digits++;
     }
   return digits;
  }

string ResponseValue(const string response,const string key)
  {
   string lines[];
   int count=StringSplit(response,'\n',lines);
   for(int i=0;i<count;i++)
     {
      string line=lines[i];
      StringReplace(line,"\r","");
      int separator=StringFind(line,"=");
      if(separator>0 && StringSubstr(line,0,separator)==key)
         return StringSubstr(line,separator+1);
     }
   return "";
  }

string UrlEncode(const string value)
  {
   string encoded="";
   for(int i=0;i<StringLen(value);i++)
     {
      ushort code=StringGetCharacter(value,i);
      bool safe=(code>='a' && code<='z') || (code>='A' && code<='Z') ||
                (code>='0' && code<='9') || code=='-' || code=='_' || code=='.';
      if(safe)
         encoded+=ShortToString(code);
      else if(code==' ')
         encoded+="+";
      else if(code<128)
         encoded+=StringFormat("%%%02X",code);
      else
         encoded+="?";
     }
   return encoded;
  }

void UpdateChartComment()
  {
   string accountGate=(IsRealAccount() && !InpAllowRealAccount) ? "BLOCKED REAL" : AccountModeName();
   if(!(IsRealAccount() && !InpAllowRealAccount))
     {
      accountGate=AccountModeName();
      StringToUpper(accountGate);
     }
   string displayMode=g_mode;
   StringToUpper(displayMode);
   string displayProfile=g_profile;
   StringToUpper(displayProfile);
   Comment(
      "AutoScalper MT5 | deterministic / no AI\n",
      "Mode: ",displayMode," | Profile: ",displayProfile," | Account: ",accountGate,"\n",
      "Symbol: ",_Symbol," | Spread: ",DoubleToString(CurrentSpreadPoints(),1)," pts\n",
      "Positions: ",CountBotPositions()," | Daily P/L: ",DoubleToString(DailyRealizedPnl(),2)," | Trades: ",TradesToday(),"\n",
      "Last: ",g_lastReason);
  }
