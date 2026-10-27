-- A shared board can be renumbered after choosing and before the pickup ACK.
-- Exercise real core/checkpoint logic without a live character or profile.
package.path="chimera_wtyczki/?.lua;"..package.path
local create=dofile("chimera_wtyczki/chimera_paczki/core.lua")
local checkpointFactory=dofile("chimera_wtyczki/chimera_paczki/checkpoint.lua")
local data=dofile("chimera_wtyczki/chimera_paczki/routes.lua")
local cases,checks=0,0
local function ok(v,m) checks=checks+1;assert(v,m or "check failed") end
local function eq(a,b,m) ok(a==b,(m or "different")..": expected "..tostring(b)..", got "..tostring(a)) end
local function clone(v) if type(v)~="table" then return v end;local out={};for k,x in pairs(v) do out[k]=clone(x) end;return out end
local HOME={id="6f2c03461c2f1438",map=101,name="Poczta",city="Nuln",staticNuln=false}
local STREET={id="a000000000000202",map=202,name="Ulica",city="Nuln",staticNuln=false}
local CRIMMOR="Urzad pocztowy w Crimmor"
local PICKUP="Bierzesz paczke przeznaczona dla: "..CRIMMOR.."."
local RETURN_ACK="Oddajesz przesylke z powrotem do urzedu. Nikt ci za nia nie zaplaci -- droga nie zostala przebyta."
local function fresh(options)
 options=options or {}
 local e={time=options.time or 100,seq=0,timers={},sends={},logs={},navs={},inv={},resolves={},plans=0,
  current=clone(options.current or HOME),held=options.held or "hands",pending=false,persist=clone(options.persist),settings=clone(options.settings)}
 local cp=checkpointFactory(e.persist,{now=function() return e.time end,save=function(s) e.persist=clone(s);return true end})
 e.checkpoint=cp
 local api={
  now=function() return e.time end,send=function(command) e.sends[#e.sends+1]=command end,say=function(s) e.logs[#e.logs+1]=s end,
  schedule=function(seconds,fn) e.seq=e.seq+1;e.timers[e.seq]={at=e.time+seconds,fn=fn};return e.seq end,
  cancel=function(id) e.timers[id]=nil end,save=function(s) e.settings=clone(s) end,
  saveRun=function(actor,s) return cp.put(actor,s) end,loadRun=cp.get,forgetRun=cp.forget,
  sessionReady=function() return true end,
  position=function() return clone(e.current) end,source=function() return clone(HOME) end,
  currentOffice=function() if e.current.id==HOME.id and e.current.map==HOME.map then return clone(HOME) end end,
  restorePlace=function(place) if place.id==HOME.id then return clone(HOME) end end,
  travelPending=function() return e.pending end,
  inventoryState=function() return {state=e.held,coinsUncertain=false} end,
  restoreInventory=function(state) if state then e.held=state.state end end,
  parcelState=function(state) e.held=state end,
  inventory=function(action,done)
   local op={action=action,done=done};e.inv[#e.inv+1]=op
   return function() op.cancelled=true;done({ok=false,reason="cancelled inventory operation"}) end
  end,
  navigate=function(route,returning,done)
   local op={route=clone(route),returning=returning,done=done};e.navs[#e.navs+1]=op
   return function() op.cancelled=true;done(false,"przerwane") end
  end,
  resolveRoute=function(name)
   e.resolves[#e.resolves+1]=name
   if name:lower()=="giacomo" or options.crimmorKnown and name:lower()==CRIMMOR:lower() then
    return {native=true,name=name,commands={},cost=2,postal=name:lower()==CRIMMOR:lower(),destination=clone(STREET)}
   end
   return nil,"nieznany adresat"
  end,
 }
 if options.forbidPlanning then api.planWork=function() e.plans=e.plans+1;error("return intent must not plan a recipient route") end end
 local b=create(data,api,e.settings)
 b:identifyActor("groro",true);b.source=b.source or clone(HOME);b.staticSource=false;b.config.roam=false;b.config.refresh=60
 b.mode=options.mode or (options.persist and b.mode or "running")
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
 function e:count(command) local n=0;for _,s in ipairs(self.sends) do if s==command then n=n+1 end end;return n end
 function e:resolved(name) local n=0;for _,s in ipairs(self.resolves) do if s:lower()==name:lower() then n=n+1 end end;return n end
 function e:arrive(op,place) op=op or self.navs[#self.navs];self.current=clone(place or op.route);op.done(true);self:advance(.5) end
 function e:completeInventory()
  local op=self.inv[#self.inv];ok(op,"missing inventory operation");ok(not op.cancelled,"inventory operation cancelled")
  if op.action=="takeParcel" then self.held="hands" elseif op.action=="stowParcel" then self.held="bag" end
  op.done({ok=true,moved=true});self:advance(.5)
 end
 function e:board(rows)
  b:onLine("Przesylki dostepne dla Grora:")
  for _,line in ipairs(rows or {}) do b:onLine(line) end
  b:onLine("Naraz mozna niesc tylko jedna przesylke.")
  self:advance(.5)
 end
 function e:chooseGiacomo()
  b:readBoard();self:board({"1. Giacomo miejscowa 1.00 kg 8 srebrnych monet [x1]"})
  self:untilTrue(function() return self:count("wybierz paczke 1")==1 end)
  eq(b.phase,"pickup");eq(b.awaitingPickup,true);eq(b.selected.name,"giacomo")
 end
 return b,e,api
end
local function test(name,fn) fn();cases=cases+1;print("PASS "..name) end
local function receiveChanged(b,e)
 e:chooseGiacomo()
 b:onLine("Gror bierze paczke z tablicy przeznaczona dla: Giacomo.")
 eq(b.job,nil);eq(b.awaitingPickup,true,"another player's pickup is not our ACK")
 b:onLine(PICKUP)
 ok(b.job);eq(b.job.name,CRIMMOR);eq(b.job.route,nil);eq(b.job.returningUndelivered,true)
 eq(b.job.returnReason,"pickupChanged");eq(b.awaitingPickup,false);eq(e.held,"hands")
 eq(e:resolved(CRIMMOR),0,"changed recipient must never trigger route resolution")
 local saved=e.checkpoint.get("groro");ok(saved);eq(saved.job.returningUndelivered,true);eq(saved.job.returnReason,"pickupChanged")
 return b.job
end
local function reachReturn(b,e)
 e:untilTrue(function() return #e.inv==1 end)
 eq(#e.navs,0,"a verified issuing-office pickup needs no movement before return")
 eq(e.inv[1].action,"takeParcel");eq(e:count("zwroc paczke"),0,"return waits for inventory confirmation")
 e:completeInventory();e:untilTrue(function() return e:count("zwroc paczke")==1 end)
 eq(b.awaitingReturn,true);eq(e:count("przeczytaj tablice"),1)
end
local function unchangedStats(b)
 eq(b.stats.delivered,0);eq(b.stats.gold,0);eq(b.stats.silver,0);eq(b.stats.copper,0)
end

test("renumbered pickup returns Crimmor without resolving it even when its address is known",function()
 local b,e=fresh({crimmorKnown=true});receiveChanged(b,e);reachReturn(b,e)
 eq(e:resolved(CRIMMOR),0);eq(next(b.unavailableRecipients),nil)
 b:onLine(RETURN_ACK);e:advance(.5)
 eq(b.job,nil);eq(b.selected,nil);eq(b.awaitingPickup,false);eq(b.awaitingDelivery,false);eq(b.awaitingReturn,false);eq(b.awaitingReward,false)
 eq(e:count("zwroc paczke"),1);eq(e:count("przeczytaj tablice"),2);eq(next(b.unavailableRecipients),nil);unchangedStats(b)
 e:board();eq(b.phase,"waiting");eq(b.timers.watchdog,nil)
 e:advance(b.config.timeout+1);eq(b.mode,"running","the completed return must not leave a stale watchdog")
end)
test("renumbered pickup also returns an unknown Crimmor without trying its resolver",function()
 local b,e=fresh();receiveChanged(b,e);reachReturn(b,e);b:onLine(RETURN_ACK);e:advance(.5)
 eq(e:resolved(CRIMMOR),0);eq(next(b.unavailableRecipients),nil);eq(b.job,nil);eq(e:count("przeczytaj tablice"),2);unchangedStats(b)
end)
test("an unknown recipient uses the verified return flow without a recipient cooldown",function()
 local b,e=fresh();b.phase="pickup";b.awaitingPickup=true;b:watch("odbior paczki");b:onLine(PICKUP)
 ok(b.job);eq(b.job.returnReason,"unknownRecipient");eq(b.job.returningUndelivered,true);eq(b.job.route,nil);eq(e:resolved(CRIMMOR),1)
 e:untilTrue(function() return #e.inv==1 end);eq(#e.navs,0);eq(e.inv[1].action,"takeParcel");e:completeInventory()
 eq(e:count("zwroc paczke"),1);b:onLine(RETURN_ACK);e:advance(.5)
 eq(b.job,nil);eq(next(b.unavailableRecipients),nil);unchangedStats(b)
end)
test("foreign pickup and return messages cannot settle our pending operation",function()
 local b,e=fresh();local job=receiveChanged(b,e);reachReturn(b,e)
 b:onLine("Gror bierze paczke przeznaczona dla: Giacomo.")
 b:onLine("Gror oddaje przesylke z powrotem do urzedu. Nikt mu za nia nie zaplaci -- droga nie zostala przebyta.")
 e:advance(.5);eq(b.job,job);eq(b.awaitingReturn,true);eq(e:count("przeczytaj tablice"),1)
 b:onLine(RETURN_ACK);e:advance(.5);eq(b.job,nil);eq(b.awaitingReturn,false)
end)
test("STOP immediately after a changed pickup prevents the scheduled return",function()
 local b,e=fresh();local job=receiveChanged(b,e);b:stop("user STOP before return");e:advance(2)
 eq(b.mode,"stopped");eq(b.job,job);eq(#e.navs,0);eq(#e.inv,0);eq(e:count("zwroc paczke"),0);eq(e:count("przeczytaj tablice"),1)
end)
test("STOP before pickup ACK records a late changed recipient for return without resolving its known address",function()
 local b,e=fresh({crimmorKnown=true});e:chooseGiacomo();b:stop("user STOP before pickup ACK")
 local sent=#e.sends;b:onLine(PICKUP);e:advance(1)
 eq(b.mode,"stopped");eq(b.awaitingPickup,false);ok(b.job);eq(b.job.name:lower(),CRIMMOR:lower())
 eq(b.job.route,nil);eq(b.job.returningUndelivered,true);eq(b.job.returnReason,"pickupChanged")
 eq(e:resolved(CRIMMOR),0);eq(#e.sends,sent);eq(#e.navs,0);eq(#e.inv,0)
 local saved=e.checkpoint.get("groro");eq(saved.job.returningUndelivered,true);eq(saved.job.returnReason,"pickupChanged");eq(saved.flags.awaitingPickup,false)
 b:begin(true);e:untilTrue(function() return #e.inv==1 end)
 eq(e.inv[1].action,"takeParcel");eq(e:resolved(CRIMMOR),0);eq(#e.navs,0)
 e:completeInventory();eq(e:count("zwroc paczke"),1);b:onLine(RETURN_ACK);e:advance(.5)
 eq(b.job,nil);eq(next(b.unavailableRecipients),nil);eq(e:count("przeczytaj tablice"),2)
end)
test("reload between choosing and pickup ACK retains the selected name and marks a late mismatch for return",function()
 local b,e=fresh({crimmorKnown=true});e:chooseGiacomo()
 local saved=e.checkpoint.get("groro");eq(saved.selectedName,"giacomo");eq(saved.flags.awaitingPickup,true)
 local restored,r=fresh({persist=e.persist,time=200,crimmorKnown=true,forbidPlanning=true})
 eq(restored.mode,"paused");eq(restored.selected.name,"giacomo");eq(restored.awaitingPickup,true)
 restored:onLine(PICKUP);r:advance(1)
 eq(restored.mode,"paused");ok(restored.job);eq(restored.job.returningUndelivered,true);eq(restored.job.returnReason,"pickupChanged")
 eq(restored.job.route,nil);eq(restored.awaitingPickup,false);eq(r:resolved(CRIMMOR),0);eq(#r.sends,0);eq(#r.inv,0);eq(#r.navs,0)
 eq(r.checkpoint.get("groro").job.returnReason,"pickupChanged")
 restored:begin(true);r:untilTrue(function() return #r.inv==1 end)
 eq(r.inv[1].action,"takeParcel");eq(r:resolved(CRIMMOR),0);eq(r.plans,0);eq(#r.navs,0)
 r:completeInventory();eq(r:count("zwroc paczke"),1)
end)
test("an intentional manual pickup can replace a stale automatic selection without forcing a return",function()
 local b,e=fresh({crimmorKnown=true});e:chooseGiacomo();b:stop("user takes over")
 b:onCommand("wybierz paczke 1");eq(b.manualPickup,true);eq(b.awaitingPickup,true)
 b:onLine(PICKUP);e:advance(1)
 ok(b.job);ok(not b.job.returningUndelivered);eq(b.job.returnReason,nil);eq(b.manualPickup,false);eq(b.awaitingPickup,false)
 eq(e:resolved(CRIMMOR),0);eq(#e.inv,0);eq(#e.navs,0);eq(e:count("zwroc paczke"),0)
 b:begin(true);e:untilTrue(function() return #e.inv==1 end)
 eq(e:resolved(CRIMMOR),1);eq(e.inv[1].action,"stowParcel");eq(b.mode,"running");eq(e:count("zwroc paczke"),0)
end)
test("STOP while return is awaiting ACK accepts its late result without restarting",function()
 local b,e=fresh();receiveChanged(b,e);reachReturn(b,e);b:stop("user STOP after sending return")
 b:onLine(RETURN_ACK);e:advance(b.config.timeout+1)
 eq(b.mode,"stopped");eq(b.job,nil);eq(b.awaitingReturn,false);eq(e:count("przeczytaj tablice"),1);eq(e:count("zwroc paczke"),1)
 eq(next(b.unavailableRecipients),nil);unchangedStats(b)
end)
test("STOP after return ACK cancels the delayed next board request",function()
 local b,e=fresh();receiveChanged(b,e);reachReturn(b,e);b:onLine(RETURN_ACK);b:stop("user STOP after ACK");e:advance(2)
 eq(b.mode,"stopped");eq(b.job,nil);eq(e:count("przeczytaj tablice"),1);eq(e:count("zwroc paczke"),1)
end)
test("reload before return preserves the unknown semantic job and never plans a Crimmor route",function()
 local b,e=fresh();receiveChanged(b,e)
 local restored,r=fresh({persist=e.persist,time=200,current=STREET,forbidPlanning=true});ok(restored.job);eq(restored.job.route,nil)
 eq(restored.job.returnReason,"pickupChanged");eq(restored.job.returningUndelivered,true);eq(restored.mode,"paused")
 restored:begin(true);r:untilTrue(function() return #r.navs==1 end)
 eq(r.plans,0);eq(r:resolved(CRIMMOR),0);eq(r.navs[1].route.id,HOME.id);eq(r.navs[1].returning,true)
 r:arrive();r:untilTrue(function() return #r.inv==1 end);eq(r.inv[1].action,"takeParcel");r:completeInventory()
 eq(r:count("zwroc paczke"),1);restored:onLine(RETURN_ACK);r:advance(.5);eq(restored.job,nil);eq(next(restored.unavailableRecipients),nil)
end)
test("reload of an unknown-recipient return goes to its issuing office without route planning",function()
 local b,e=fresh();b.phase="pickup";b.awaitingPickup=true;b:onLine(PICKUP)
 eq(b.job.returnReason,"unknownRecipient")
 local restored,r=fresh({persist=e.persist,time=200,current=STREET,forbidPlanning=true})
 eq(restored.job.returnReason,"unknownRecipient");eq(restored.job.returningUndelivered,true)
 restored:begin(true);r:untilTrue(function() return #r.navs==1 end)
 eq(r.plans,0);eq(r:resolved(CRIMMOR),0);eq(r.navs[1].route.id,HOME.id);eq(r.navs[1].returning,true)
end)
test("reload after sending return preserves awaiting ACK and cannot blindly resend",function()
 local b,e=fresh();receiveChanged(b,e);reachReturn(b,e)
 local saved=e.checkpoint.get("groro");eq(saved.flags.awaitingReturn,true);eq(saved.job.returnReason,"pickupChanged");eq(saved.job.route,nil)
 local restored,r=fresh({persist=e.persist,time=200,forbidPlanning=true});eq(restored.awaitingReturn,true)
 restored:begin(true);r:advance(2);eq(restored.mode,"paused");eq(#r.navs,0);eq(#r.inv,0);eq(#r.sends,0);eq(r.plans,0)
 restored:onLine(RETURN_ACK);r:advance(2)
 eq(restored.job,nil);eq(restored.awaitingReturn,false);eq(restored.mode,"paused");eq(#r.sends,0);eq(next(restored.unavailableRecipients),nil)
end)
test("a false source arrival never returns the changed parcel in an unverified room",function()
 for _,place in ipairs({STREET,{id=HOME.id,map=HOME.map+1}}) do
  local b,e=fresh();receiveChanged(b,e);e.current=clone(STREET);e:untilTrue(function() return #e.navs==1 end);e:arrive(nil,place);e:advance(1)
  eq(b.mode,"paused");ok(b.job and b.job.returningUndelivered);eq(#e.inv,0);eq(e:count("zwroc paczke"),0)
 end
end)
test("checkpoint accepts only the defined optional return reasons",function()
 local cp=checkpointFactory()
 for _,reason in ipairs({"pickupChanged","unknownRecipient"}) do
  ok(cp.put("groro",{job={name=CRIMMOR,returningUndelivered=true,returnReason=reason}}));eq(cp.get("groro").job.returnReason,reason)
 end
 ok(cp.put("groro",{job={name="Bruno Rottel",returningUndelivered=true}}));eq(cp.get("groro").job.returnReason,nil)
 for _,reason in ipairs({"search",false,123,{}}) do eq(cp.put("groro",{job={name=CRIMMOR,returnReason=reason}}),false) end
end)
print("PICKUP: "..cases.." scenarios, "..checks.." assertions passed")
