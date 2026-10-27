-- Pure core + real checkpoint regression for scheduled Nuln bank visits.
-- Synthetic navigation and exchange acknowledgements; no live account.
package.path="chimera_wtyczki/?.lua;"..package.path
local create=dofile("chimera_wtyczki/chimera_paczki/core.lua")
local checkpointFactory=dofile("chimera_wtyczki/chimera_paczki/checkpoint.lua")
local data=dofile("chimera_wtyczki/chimera_paczki/routes.lua")
local cases,checks=0,0
local function ok(v,m) checks=checks+1;assert(v,m or "check failed") end
local function eq(a,b,m) ok(a==b,(m or "different")..": expected "..tostring(b)..", got "..tostring(a)) end
local function clone(v) if type(v)~="table" then return v end;local out={};for k,x in pairs(v) do out[k]=clone(x) end;return out end
local HOME={id="315106e45b840273",map=101,name="Poczta miasta Kreutzhofen",city="Kreutzhofen",staticNuln=false}
local BANK={id="a000000000000500",map=500,name="Bank w Nuln",city="Nuln",staticNuln=false}
local POST={id="6f2c03461c2f1438",map=501,name="Poczta",city="Nuln",staticNuln=false}
local function fresh(options)
 options=options or {}
 local e={time=options.time or 100,seq=0,timers={},sends={},logs={},navs={},exchanges={},inv={},current=clone(options.current or HOME),
  pending=false,coinsUncertain=false,settings=clone(options.settings),persist=clone(options.persist),missingBank=false}
 local cp=checkpointFactory(e.persist,{now=function() return e.time end,save=function(s) e.persist=clone(s);return true end})
 e.checkpoint=cp
 local api={
  now=function() return e.time end,send=function(command) e.sends[#e.sends+1]=command end,say=function(s) e.logs[#e.logs+1]=s end,
  schedule=function(seconds,fn) e.seq=e.seq+1;e.timers[e.seq]={at=e.time+seconds,fn=fn};return e.seq end,
  cancel=function(id) e.timers[id]=nil end,save=function(s) e.settings=clone(s) end,
  saveRun=function(actor,s) return cp.put(actor,s) end,loadRun=cp.get,forgetRun=cp.forget,
  position=function() return clone(e.current) end,source=function() return clone(HOME) end,
  currentOffice=function() if e.current.id==HOME.id then return clone(HOME) elseif e.current.id==POST.id then return clone(POST) end end,
  restorePlace=function(place) for _,known in ipairs({HOME,BANK,POST}) do if place.id==known.id then return clone(known) end end end,
  inventoryState=function() return {state="hands",coinsUncertain=e.coinsUncertain} end,
  travelPending=function() return e.pending end,
  navigate=function(route,returning,done)
   local op={route=clone(route),returning=returning,done=done};e.navs[#e.navs+1]=op
   return function() op.cancelled=true;done(false,"przerwane") end
  end,
  bankPlace=function(kind) if e.missingBank then return nil,"bank missing from current profile map" end;return clone(kind=="bank" and BANK or POST) end,
  bankExchange=function(done)
   local op={done=done};e.exchanges[#e.exchanges+1]=op
   return function() op.cancelled=true;done({ok=false,reason="cancelled bank exchange"}) end
  end,
  inventory=function(action,done) local op={action=action,done=done};e.inv[#e.inv+1]=op;return function() op.cancelled=true end end,
 }
 local b=create(data,api,e.settings)
 b:identifyActor(options.actor or "groro",true)
 b.source=b.source or clone(HOME);b.staticSource=false;b.config.roam=false
 b.mode=options.mode or (options.persist and b.mode or "running")
 -- Tests deliberately control the saved deadline, not any running timer.
 b.bank=b.bank or {nextAt=e.time+1800}
 function e:advance(seconds)
  local finish=self.time+seconds
  for _=1,1000 do
   local id,at;for key,t in pairs(self.timers) do if t.at<=finish and (not at or t.at<at or t.at==at and key<id) then id,at=key,t.at end end
   if not id then self.time=finish;return end
   local t=self.timers[id];self.timers[id]=nil;self.time=at;t.fn()
  end;error("timer storm")
 end
 function e:untilTrue(fn)
  for _=1,100 do if fn() then return end;self:advance(.05) end
  error("condition timeout: "..table.concat(self.logs,"\n"))
 end
 function e:arrive(op,place) op=op or self.navs[#self.navs];self.current=clone(place or op.route);op.done(true);self:advance(.5) end
 function e:count(command) local total=0;for _,s in ipairs(self.sends) do if s==command then total=total+1 end end;return total end
 function e:job()
  b.job={name="Bruno Rottel",route={native=true,name="Bruno Rottel",postal=false,commands={},cost=5},
   source=clone(HOME),actor=b.actor,recipientConfirmed=true,delivered=false,coinsPending=false}
  return b.job
 end
 return b,e,api
end
local function test(name,fn) fn();cases=cases+1;print("PASS "..name) end
local function due(b,e) b.bank.nextAt=e.time-1;b:readBoard();e:untilTrue(function() return #e.navs>0 end) end
local function reachExchange(b,e)
 due(b,e);eq(e.navs[#e.navs].route.id,BANK.id);eq(e.navs[#e.navs].returning,true);eq(e:count("przeczytaj tablice"),0)
 e:arrive();e:untilTrue(function() return #e.exchanges>0 end);eq(b.bank.stage,"exchange")
end
local function completeVisit(b,e)
 reachExchange(b,e);e.exchanges[#e.exchanges].done({ok=true});e:advance(.5)
 e:untilTrue(function() return #e.navs==2 end);eq(e.navs[2].route.id,POST.id);eq(e.navs[2].returning,true)
 e:arrive(e.navs[2]);e:advance(.5)
end

test("bank defaults are enabled at thirty minutes and no visit happens before deadline",function()
 local b,e=fresh();eq(b.config.bankSeconds,1800);eq(b.config.bankEnabled,true)
 b.bank.nextAt=e.time+1800;b:readBoard();eq(e:count("przeczytaj tablice"),1);eq(#e.navs,0);eq(#e.exchanges,0)
end)
test("an overdue bank visit precedes board reading and completes only after exchange ACK and postal return",function()
 local b,e=fresh();local before=e.time;completeVisit(b,e)
 eq(#e.exchanges,1);eq(b.bank.stage,nil);eq(b.bank.requested,false)
 ok(b.bank.nextAt>=before+1800 and b.bank.nextAt<=e.time+1800,"deadline renewed only by successful visit")
 eq(e.current.id,POST.id);eq(b.source.id,POST.id);eq(e:count("przeczytaj tablice"),1)
 eq(b.stats.delivered,0);eq(b.stats.gold,0);eq(b.stats.silver,0);eq(b.stats.copper,0)
end)
test("active parcel queues manual bank request and settles before bank travel",function()
 local b,e=fresh();local job=e:job();b:command("bank teraz");eq(b.bank.requested,true);eq(#e.navs,0);eq(#e.exchanges,0);eq(b.job,job)
 job.delivered=true;job.coinsPending=false;b:afterDelivery();eq(#e.navs,1);eq(e.navs[1].route.id,HOME.id)
 e:arrive(e.navs[1]);e:untilTrue(function() return #e.navs==2 end)
 eq(b.job,nil);eq(e.navs[2].route.id,BANK.id);eq(e:count("przeczytaj tablice"),0)
end)
test("manual request from stopped courier is queued without any game command",function()
 local b,e=fresh({mode="stopped"});b:command("bank teraz");e:advance(2)
 eq(b.bank.requested,true);eq(b.mode,"stopped");eq(#e.navs,0);eq(#e.exchanges,0);eq(#e.sends,0)
end)
test("manual request replaces safe board wait and cancels stale planning before bank movement",function()
 local b,e=fresh();local cancelled=0;b.phase="ranking";b.planningToken={};b.cancelPlanning=function() cancelled=cancelled+1 end
 b:later("refresh",1,function() error("stale refresh fired during bank visit") end)
 b:watch("obsolete board timeout");b:command("bank teraz");e:advance(2)
 eq(cancelled,1);eq(#e.navs,1);eq(e.navs[1].route.id,BANK.id);eq(e:count("przeczytaj tablice"),0)
end)
test("STOP during bank travel ignores stale arrival callback",function()
 local b,e=fresh();due(b,e);local op=e.navs[1];b:stop("user STOP");op.done(true);e:advance(1)
 eq(#e.exchanges,0);eq(#e.navs,1);eq(#e.sends,0);eq(b.mode,"stopped");eq(b.bank.stage,"travel")
end)
test("STOP during exchange prevents late success from silently returning or starting another exchange",function()
 local b,e=fresh();reachExchange(b,e);local op=e.exchanges[1];b:stop("user STOP");op.done({ok=true});e:advance(1)
 eq(#e.exchanges,1);eq(#e.navs,1);eq(b.mode,"stopped");eq(b.bank.stage,"exchange")
 b:begin(true);e:advance(1);eq(#e.exchanges,1);eq(#e.navs,1);ok(b.mode~="running","unreconciled exchange must block automatic resume")
end)
test("interrupted exchange requires explicit reconciliation before safe return",function()
 local b,e=fresh();reachExchange(b,e);b:stop("disconnect during conversion")
 b:begin(true);eq(#e.exchanges,1);eq(#e.navs,1)
 b:command("bank rozliczone")
 if #e.navs==1 then b:begin(true) end
 e:untilTrue(function() return #e.navs==2 end)
 eq(e.navs[2].route.id,POST.id);eq(#e.exchanges,1,"reconciliation must never replay coin conversion")
 e:arrive(e.navs[2]);eq(b.bank.stage,nil)
end)
test("failed exchange preserves due intent and never schedules next successful deadline",function()
 local b,e=fresh();local original=e.time-1;b.bank.nextAt=original;reachExchange(b,e)
 e.exchanges[1].done({ok=false,reason="conversion not confirmed"});e:advance(1)
 eq(b.bank.stage,"exchange");eq(b.bank.nextAt,original);eq(#e.exchanges,1);eq(#e.navs,1);eq(b.mode,"paused")
end)
test("missing bank map pauses with no coin operation or guessed route",function()
 local b,e=fresh();e.missingBank=true;b.bank.nextAt=e.time-1;b:readBoard();e:advance(1)
 eq(#e.navs,0);eq(#e.exchanges,0);eq(#e.sends,0);eq(b.mode,"paused")
end)
test("unconfirmed parcel or coin operations prevent bank travel",function()
 for _,flag in ipairs({"awaitingPickup","awaitingDelivery","awaitingReturn","awaitingReward"}) do
  local b,e=fresh();b[flag]=true;b.bank.requested=true;b:bankVisit();e:advance(1);eq(#e.navs,0,flag);eq(#e.exchanges,0,flag)
 end
 local b,e=fresh();e.coinsUncertain=true;b.bank.requested=true;b:bankVisit();e:advance(1);eq(#e.navs,0);eq(#e.exchanges,0)
end)
test("an outstanding previous movement settles before the first bank navigation",function()
 local b,e=fresh();e.pending=true;b.bank.requested=true;b:bankVisit()
 eq(b.phase,"bankSettling");eq(#e.navs,0);eq(#e.exchanges,0)
 e:advance(2);eq(#e.navs,0,"do not overlap bank travel with the old unconfirmed step")
 e.pending=false;e:untilTrue(function() return #e.navs==1 end)
 eq(e.navs[1].route.id,BANK.id);eq(e.navs[1].returning,true)
end)
test("STOP while awaiting an old movement prevents a later settlement from starting bank travel",function()
 local b,e=fresh();e.pending=true;b.bank.requested=true;b:bankVisit();eq(b.phase,"bankSettling")
 b:stop("user STOP during pending step");e.pending=false;e:advance(2)
 eq(#e.navs,0);eq(#e.exchanges,0);eq(#e.sends,0);eq(b.mode,"stopped")
 ok(b.bank.requested,"STOP must preserve the queued visit for an explicit resume")
end)
test("bank OFF removes queued requests but an existing exchange is allowed to finish",function()
 local b,e=fresh({mode="stopped"});b:command("bank teraz");b:command("bank off");eq(b.config.bankEnabled,false);eq(b.bank.requested,false)
 local running,r=fresh();reachExchange(running,r);running:command("bank off");eq(running.config.bankEnabled,false)
 r.exchanges[1].done({ok=true});r:advance(.5);r:untilTrue(function() return #r.navs==2 end);r:arrive(r.navs[2])
 eq(running.bank.stage,nil);eq(#r.exchanges,1);eq(r:count("przeczytaj tablice"),1)
end)
test("bank interval settings persist and reject values outside one to1440 minutes",function()
 local b,e=fresh();b:command("bank 1");eq(b.config.bankSeconds,60);ok(e.settings)
 b:command("bank 1440");eq(b.config.bankSeconds,86400)
 for _,input in ipairs({"bank 0","bank -1","bank 1441","bank nope"}) do b:command(input);eq(b.config.bankSeconds,86400,input) end
 local restored=fresh({settings=e.settings});eq(restored.config.bankSeconds,86400)
end)
test("real checkpoint preserves bank intent by actor without persisting map IDs or executable data",function()
 local b,e=fresh();b.bank={nextAt=2000,requested=true,stage="return"};b:checkpoint()
 local saved=e.checkpoint.get("groro");ok(saved);eq(saved.bank.nextAt,2000);eq(saved.bank.requested,true);eq(saved.bank.stage,"return")
 local restored,r=fresh({persist=e.persist,current=BANK,time=500});eq(restored.bank.nextAt,2000);eq(restored.bank.stage,"return")
 restored:begin(true);r:untilTrue(function() return #r.navs==1 end);eq(r.navs[1].route.id,POST.id);eq(#r.exchanges,0)
 local other,o=fresh({persist=e.persist,actor="yarrim",time=500});eq(other.bank.stage,nil);ok(not other.bank.requested)
 eq(other.actor,"yarrim");eq(e.checkpoint.get("yarrim"),nil)
end)
test("switching actors never leaks a queued or interrupted bank visit into another character",function()
 local b,e=fresh();b.bank={nextAt=3000,requested=true,stage="travel"};b:checkpoint()
 b:identifyActor("yarrim");eq(b.actor,"yarrim");ok(not b.bank or not b.bank.stage);ok(not b.bank or not b.bank.requested)
 b:identifyActor("groro");eq(b.actor,"groro");ok(b.bank);eq(b.bank.stage,"travel");eq(b.bank.requested,true)
 eq(#e.navs,0);eq(#e.exchanges,0)
end)
test("real checkpoint rejects malformed bank deadline and unknown exchange stage",function()
 local cp=checkpointFactory()
 for _,bank in ipairs({{nextAt=-1},{nextAt=0/0},{nextAt=math.huge},{nextAt=100,stage="send all coins"},{nextAt=100,requested="yes"}}) do
  local good=cp.put("groro",{bank=bank});eq(good,false)
 end
end)
print("BANK: "..cases.." scenarios, "..checks.." assertions passed")
