-- Returning an undeliverable parcel requires source, extraction and server ACK.
package.path="chimera_wtyczki/?.lua;"..package.path
local create=dofile("chimera_wtyczki/chimera_paczki/core.lua")
local data=dofile("chimera_wtyczki/chimera_paczki/routes.lua")
local cases,checks=0,0
local function ok(v,m) checks=checks+1;assert(v,m or "check failed") end
local function eq(a,b,m) ok(a==b,(m or "different")..": expected "..tostring(b)..", got "..tostring(a)) end
local function clone(v) if type(v)~="table" then return v end;local o={};for k,x in pairs(v) do o[k]=clone(x) end;return o end
local HOME={id="315106e45b840273",map=101,name="Poczta miasta Kreutzhofen",city="Kreutzhofen"}
local STREET={id="a000000000000202",map=202,name="Ulica",city="Kreutzhofen"}
local ACK="Oddajesz przesylke z powrotem do urzedu. Nikt ci za nia nie zaplaci -- droga nie zostala przebyta."
local TIMEOUT="limit czasu szukania adresata w miescie"
local function fresh(saved)
 local e={time=100,seq=0,timers={},sends={},logs={},navs={},inv={},current=clone(STREET),pending=false,held="bag",saved=saved}
 local b
 local api={now=function() return e.time end,send=function(c) e.sends[#e.sends+1]=c end,say=function(s) e.logs[#e.logs+1]=s end,
  schedule=function(seconds,fn) e.seq=e.seq+1;e.timers[e.seq]={at=e.time+seconds,fn=fn};return e.seq end,
  cancel=function(id) e.timers[id]=nil end,save=function(s) e.saved=clone(s) end,
  saveRun=function(actor,s) e.run=clone(s);return true end,loadRun=function() return e.run end,position=function() return clone(e.current) end,
  source=function() return clone(HOME) end,currentOffice=function() return e.current.id==HOME.id and clone(HOME) or nil end,
  travelPending=function() return e.pending end,inventoryState=function() return {state=e.held,coinsUncertain=false} end,
  parcelState=function(state) e.held=state end,
  inventory=function(action,done) local op={action=action,done=done};e.inv[#e.inv+1]=op;return function() op.cancelled=true;done({ok=false,reason="cancelled"}) end end,
  navigate=function(route,returning,done) local op={route=clone(route),returning=returning,done=done};e.navs[#e.navs+1]=op;return function() op.cancelled=true;done(false,"przerwane") end end,
  resolveRoute=function(name) return {native=true,name=name,commands={},cost=10,postal=false,destination=clone(STREET),targetId=STREET.id,roomIds={[202]=STREET.id}} end}
 b=create(data,api,saved);b.actor="groro";b.source=clone(HOME);b.staticSource=false;b.mode="running";b.config.roam=false
 function e:advance(seconds)
  local last=self.time+seconds
  for _=1,1000 do
   local key,at;for id,t in pairs(self.timers) do if t.at<=last and (not at or t.at<at or t.at==at and id<key) then key,at=id,t.at end end
   if not key then self.time=last;return end
   local t=self.timers[key];self.timers[key]=nil;self.time=at;t.fn()
  end;error("timer storm")
 end
 function e:untilTrue(fn) for _=1,100 do if fn() then return end;self:advance(.05) end;error("condition timeout: "..table.concat(self.logs,"\n")) end
 function e:arrive(op,place) op=op or self.navs[#self.navs];self.current=clone(place or op.route);op.done(true);self:advance(.5) end
 function e:completeInventory()
  local op=self.inv[#self.inv];ok(op,"missing inventory operation");ok(not op.cancelled,"inventory cancelled")
  if op.action=="takeParcel" then self.held="hands" elseif op.action=="stowParcel" then self.held="bag" end
  op.done({ok=true,moved=true});self:advance(.5)
 end
 function e:count(command) local n=0;for _,s in ipairs(self.sends) do if s==command then n=n+1 end end;return n end
 function e:job() local route=api.resolveRoute("Bruno Rottel");b.job={name="Bruno Rottel",route=route,source=clone(HOME),actor=b.actor,recipientConfirmed=true,delivered=false};return b.job end
 function e:timeout() self:job();b:navigate(b.job.route,function() error("recipient not found") end);self.navs[1].done(false,TIMEOUT);self:advance(.5) end
 return b,e,api
end
local function row(b,n,name,kg,pay) return assert(b:parseOffer(n..". "..name.." miejscowa "..(kg or 1).." kg "..(pay or 10).." srebrnych monet [x1]")) end
local function test(name,fn) fn();cases=cases+1;print("PASS "..name) end
local function reachReturn(b,e)
 e:timeout();e:untilTrue(function() return #e.navs==2 end);eq(e.navs[2].returning,true);eq(e.navs[2].route.id,HOME.id)
 e:arrive(e.navs[2]);e:untilTrue(function() return #e.inv>0 end);eq(e.inv[#e.inv].action,"takeParcel")
 eq(e:count("zwroc paczke"),0,"wait for parcel extraction ACK");e:completeInventory();e:untilTrue(function() return e:count("zwroc paczke")==1 end)
end

test("timeout returns to source and waits for extraction and real ACK before new board",function()
 local b,e=fresh();reachReturn(b,e);ok(b.job and b.job.returningUndelivered);eq(b.awaitingReturn,true);eq(e:count("przeczytaj tablice"),0)
 b:onLine(ACK);e:advance(.5);eq(b.job,nil);eq(b.awaitingReturn,false);eq(e:count("zwroc paczke"),1);eq(e:count("przeczytaj tablice"),1)
 eq(b.stats.delivered,0);eq(b.stats.gold,0);eq(b.stats.silver,0);eq(b.stats.copper,0)
end)
test("last sent step settles before any return movement starts",function()
 local b,e=fresh();e.pending=true;e:timeout();eq(#e.navs,1);eq(e:count("zwroc paczke"),0);e:advance(2);eq(#e.navs,1)
 e.pending=false;e:untilTrue(function() return #e.navs==2 end);eq(e.navs[2].returning,true)
end)
test("STOP during return prevents a late navigation callback from extracting or returning",function()
 local b,e=fresh();e:timeout();e:untilTrue(function() return #e.navs==2 end);local op=e.navs[2];b:stop("manual stop");op.done(true);e:advance(1)
 eq(#e.inv,0);eq(e:count("zwroc paczke"),0);ok(b.job and b.job.returningUndelivered);eq(b.mode,"stopped")
end)
test("late return ACK clears stopped course without restarting",function()
 local b,e=fresh();reachReturn(b,e);b:stop("manual stop");b:onLine(ACK);e:advance(1)
 eq(b.job,nil);eq(b.awaitingReturn,false);eq(b.mode,"stopped");eq(e:count("przeczytaj tablice"),0)
end)
test("missing return ACK preserves intent and never repeats command",function()
 local b,e=fresh();reachReturn(b,e);e:advance(b.config.timeout+1)
 ok(b.job and b.job.returningUndelivered);eq(b.awaitingReturn,true);eq(b.mode,"paused");eq(e:count("zwroc paczke"),1);eq(e:count("przeczytaj tablice"),0)
end)
test("wrong confirmed office position prevents the return command",function()
 local b,e=fresh();e:timeout();e:untilTrue(function() return #e.navs==2 end)
 e:arrive(e.navs[2],{id="a000000000000333",map=333,name="Inna poczta"});e:advance(1)
 eq(e:count("zwroc paczke"),0);ok(b.job);eq(b.mode,"paused")
end)
test("manual return and exact log ACK settle remembered stopped job",function()
 local b,e=fresh();e:job();b.mode="stopped";e.current=clone(HOME);e.held="hands";b.awaitingDelivery=true;b.manualDelivery=true;b:onCommand("zwroc paczke");eq(b.awaitingReturn,true)
 b:onLine(ACK);e:advance(.5);eq(b.job,nil);eq(b.awaitingReturn,false);eq(b.mode,"stopped");eq(e:count("przeczytaj tablice"),0);eq(b.awaitingDelivery,false);eq(b.manualDelivery,false)
end)
test("cooldown ignores changed mass or price while permitting another recipient",function()
 local b,e=fresh();e:timeout();e.current=clone(HOME)
 local offers={row(b,1,"Bruno Rottel",1,10),row(b,2,"Bruno Rottel",2,99),row(b,3,"Franz Eisen",1,1)}
 local ranked=b:rank(offers);eq(#ranked,1);eq(ranked[1].name,"franz eisen");eq(b.offerDiagnostics[1].eligible,false);eq(b.offerDiagnostics[2].eligible,false)
 e.time=e.time+1801;ranked=b:rank(offers);eq(#ranked,3);eq(ranked[1].number,1)
end)
test("cooldown survives reload and is scoped to character and issuing office",function()
 local b,e=fresh();e:timeout();ok(e.saved,"suppression must persist");local reloaded,r=fresh(e.saved);r.current=clone(HOME)
 eq(#reloaded:rank({row(reloaded,1,"Bruno Rottel")}),0);reloaded.actor="yarrim";eq(#reloaded:rank({row(reloaded,1,"Bruno Rottel")}),1)
 reloaded.actor="groro";reloaded.source={map=303,id="a000000000000303",name="Poczta innego miasta"};eq(#reloaded:rank({row(reloaded,1,"Bruno Rottel")}),1)
end)
test("resuming return intent goes home instead of searching again",function()
 local b,e=fresh();e:job();b.job.returningUndelivered=true;b.mode="paused";b:begin(true);e:advance(.5)
 eq(#e.navs,1);eq(e.navs[1].returning,true);eq(e.navs[1].route.id,HOME.id);eq(#e.inv,0,"do not replay outbound stowing")
end)
test("search budget checkpoints active time and excludes paused or disconnected wall time",function()
 local b,e=fresh();e:job();b:startRecipientSearch(b.job.route);e.time=e.time+37;b:pause("pause")
 eq(b.job.searchElapsed,37);eq(e.run.job.searchElapsed,37);eq(b.job.searchStartedAt,nil)
 e.time=e.time+500;eq(b:searchRemaining(),263)
 b.mode="running";b:startRecipientSearch(b.job.route);e.time=e.time+21;b:checkpoint()
 eq(e.run.job.searchElapsed,58);b:disconnected();eq(e.run.job.searchElapsed,58)
 e.time=e.time+900;eq(b:searchElapsed(),58)
 local loaded,r=fresh();r.time=e.time;r.run=clone(e.run);ok(loaded:restoreRun());eq(loaded.job.searchElapsed,58)
 eq(loaded:searchRemaining(),242);eq(loaded.job.searchStartedAt,nil)
end)
test("STOP during parcel extraction prevents its late ACK from sending return",function()
 local b,e=fresh();e:timeout();e:untilTrue(function() return #e.navs==2 end);e:arrive(e.navs[2])
 e:untilTrue(function() return #e.inv>0 end);local op=e.inv[#e.inv];eq(op.action,"takeParcel")
 b:stop("manual stop");op.done({ok=true,moved=true});e:advance(1)
 eq(e:count("zwroc paczke"),0);ok(b.job and b.job.returningUndelivered);eq(b.mode,"stopped")
end)
test("failed parcel extraction preserves course and never issues return",function()
 local b,e=fresh();e:timeout();e:untilTrue(function() return #e.navs==2 end);e:arrive(e.navs[2])
 e:untilTrue(function() return #e.inv>0 end);e.inv[#e.inv].done({ok=false,reason="no extraction acknowledgement"});e:advance(1)
 eq(e:count("zwroc paczke"),0);ok(b.job and b.job.returningUndelivered);eq(b.mode,"paused")
end)
print("RETURN: "..cases.." scenarios, "..checks.." assertions passed")
