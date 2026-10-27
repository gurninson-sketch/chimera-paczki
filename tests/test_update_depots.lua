-- Pure core regression with the production postal registry and selector.
-- Parcel, reward, inventory and navigation acknowledgements are controlled.
local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tests/test_update_depots%.lua$") or "."
package.path=root.."/chimera_wtyczki/?.lua;"..package.path
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/core.lua")
local createOffices=require("chimera_paczki.offices")
local postal=require("chimera_paczki.postal")
local data=dofile(root.."/chimera_wtyczki/chimera_paczki/routes.lua")
local cases,checks=0,0
local function check(value,message) checks=checks+1;assert(value,message or "check failed") end
local function eq(actual,wanted,message)
  check(actual==wanted,(message or "different values")..": expected "..tostring(wanted)..", got "..tostring(actual))
end
local function clone(value)
  if type(value)~="table" then return value end
  local result={};for k,v in pairs(value) do result[k]=clone(v) end;return result
end
local NULN="6f2c03461c2f1438"
local KZ="907327356ecc2f87"
local BISSINGEN="200aff4d957642cd"
local EBINO="d69d73a15fc1b87d"
local DYNAMIC="0123456789abcdef"
local MAPS={[NULN]=101,[KZ]=102,[BISSINGEN]=103,[EBINO]=104,[DYNAMIC]=105}
local function office(id)
  for _,record in ipairs(postal.catalogue()) do
    if record.id==id then record.map=MAPS[id];return record end
  end
  return {id=id,map=MAPS[id],name="Nieznana placowka kurierska",staticNuln=false}
end
local function fresh(options)
  options=options or {}
  local e={time=1000,sequence=0,timers={},sends={},messages={},events={},navs={},inventory={},resolved={},routeChecks={},
    current=office(options.current or KZ),capabilities=clone(options.capabilities),capabilityWrites=0,marks=0,nextCalls=0}
  _G.getRoomIDbyHash=function(id) return MAPS[id] end
  local navigator={current=function() return clone(e.current) end,
    safeCost=function(from,to)
      e.routeChecks[#e.routeChecks+1]={from=from,to=to}
      if options.noPaths then return nil end
      return math.abs(from-to)+1
    end}
  local offices=createOffices({},navigator,{
    loadCapabilities=function() return clone(e.capabilities) end,
    saveCapabilities=function(snapshot) e.capabilityWrites=e.capabilityWrites+1;e.capabilities=clone(snapshot);return true end,
  },function() return e.time end)
  e.offices=offices
  local function event(kind,value) e.events[#e.events+1]={kind=kind,value=value} end
  local function schedule(delay,fn)
    e.sequence=e.sequence+1;e.timers[e.sequence]={at=e.time+delay,fn=fn};return e.sequence
  end
  local function currentOffice()
    for _,known in ipairs(offices.catalogue()) do
      if known.id==e.current.id and MAPS[known.id]==e.current.map then known.map=e.current.map;return known end
    end
  end
  local b
  local api={now=function() return e.time end,schedule=schedule,cancel=function(id) e.timers[id]=nil end,
    say=function(message) e.messages[#e.messages+1]=message;event("say",message) end,
    send=function(command) e.sends[#e.sends+1]={command=command,id=e.current.id};event("send",command) end,
    position=navigator.current,source=currentOffice,currentOffice=currentOffice,
    canDispatch=offices.canDispatch,
    markNoDispatch=function(source) e.marks=e.marks+1;return offices.markNoDispatch(source) end,
    resolveOffice=offices.resolve,officeWorking=offices.clear,resetOffices=offices.clearAll,
    resolveRoute=function(name)
      e.resolved[#e.resolved+1]=name;event("resolveRoute",name)
      local target=postal.resolve(name)
      if target then
        target.map=MAPS[target.id]
        return {native=true,postal=true,name=name,commands={},cost=20,targetId=target.id,targetName=target.name,
          roomIds={[target.map]=target.id},destination=target}
      end
    end,
    nextOffice=function(source)
      e.nextCalls=e.nextCalls+1;event("nextOffice",source.id)
      offices.markEmpty(source)
      return offices.next(source)
    end,
    inventoryState=function() return {state="hands",coinsUncertain=false} end,
    inventory=function(action,done)
      local operation={action=action,done=done};e.inventory[#e.inventory+1]=operation;event("inventory",action)
      if action=="stowCoins" then e.pendingCoins=operation else done({ok=true}) end
      return function() operation.cancelled=true end
    end,
    navigate=function(route,returning,done)
      local operation={route=clone(route),returning=returning,done=done};e.navs[#e.navs+1]=operation
      event("navigate",returning and route.id or route.targetId)
      return function() operation.cancelled=true end
    end,
  }
  if options.asyncPlanning then
    api.planWork=function(work,done,alive)
      local id=schedule(.001,function()
        local valid,why=alive();if not valid then done(false,nil,why);return end
        local first,second,third,fourth=work();done(true,first,second,third,fourth)
      end)
      return function() e.timers[id]=nil end
    end
  end
  b=create(data,api)
  b.source=clone(e.current);b.staticSource=false;b.mode="running"
  if options.roam~=nil then b.config.roam=options.roam end
  function e:advance(seconds)
    local finish=self.time+seconds
    for _=1,1000 do
      local id,at
      for key,timer in pairs(self.timers) do
        if timer.at<=finish and (not at or timer.at<at or timer.at==at and key<id) then id,at=key,timer.at end
      end
      if not id then self.time=finish;return end
      local timer=self.timers[id];self.timers[id]=nil;self.time=at;timer.fn()
    end
    error("timer storm")
  end
  function e:untilTrue(predicate)
    for _=1,100 do if predicate() then return end;self:advance(.05) end
    error("condition timeout: "..table.concat(self.messages,"\n"))
  end
  function e:arrive(operation)
    operation=operation or self.navs[#self.navs]
    self.current=clone(operation.returning and operation.route or operation.route.destination)
    operation.done(true);self:advance(.5)
  end
  function e:count(command,id)
    local total=0
    for _,sent in ipairs(self.sends) do if sent.command==command and (not id or sent.id==id) then total=total+1 end end
    return total
  end
  return b,e
end
local function board(b,rows)
  b:onLine("Przesylki dostepne dla kuriera:")
  for _,row in ipairs(rows or {}) do b:onLine(row) end
  b:onLine("Naraz mozna niesc tylko jedna przesylke.")
end
local function test(name,body) body();cases=cases+1;print("PASS "..name) end

test("confirmed delivery and reward at Ebino wait for coin stow then choose a dispatch office without reading its board",function()
  local b,e=fresh();b:readBoard()
  board(b,{"1. Poczta w Ebino miedzymiastowa 2.00 kg 1 zlota moneta [x1]"})
  e:untilTrue(function() return e:count("wybierz paczke 1")==1 end)
  b:onLine("Bierzesz paczke przeznaczona dla: Poczta w Ebino.")
  e:untilTrue(function() return #e.navs==1 end)
  eq(e.navs[1].route.targetId,EBINO);eq(b.job.delivered,false);eq(e.nextCalls,0)
  e:arrive();eq(e:count("oddaj paczke",EBINO),1)
  b:onLine("Zostawiasz przesylke w okienku urzedu pocztowego.")
  eq(b.stats.delivered,1);eq(e.nextCalls,0);eq(#e.navs,1)
  b:onLine("Urzednik wyplaca ci 1 zlota monete za trud.")
  e:untilTrue(function() return e.pendingCoins~=nil end)
  eq(b.job.coinsPending,true);eq(e.nextCalls,0);eq(#e.navs,1)
  eq(e:count("przeczytaj tablice",EBINO),0);eq(e:count("wybierz paczke 1",EBINO),0)
  e.pendingCoins.done({ok=true,moved=true})
  eq(b.job,nil);eq(b.source.id,EBINO);eq(b.phase,"relocating");eq(e.nextCalls,1)
  eq(#e.navs,2);eq(e.navs[2].returning,true);eq(e.navs[2].route.id,NULN)
  eq(e:count("przeczytaj tablice",EBINO),0);eq(e:count("wybierz paczke 1",EBINO),0)
  eq(b.stats.delivered,1);eq(b.stats.gold,1);eq(e.marks,0,"known Ebino needs no failed board request")
  e:arrive();eq(b.source.id,NULN);eq(b.phase,"board")
  eq(e:count("przeczytaj tablice",NULN),1);eq(e:count("przeczytaj tablice",KZ),1)
end)

test("manual poczta tutaj rejects the delivery-only Ebino counter before adopting or moving",function()
  local b,e=fresh({current=EBINO});local original=office(KZ)
  b.source=original;b.mode="stopped";b:command("poczta tutaj")
  eq(b.mode,"stopped");eq(b.source,original);eq(#e.sends,0);eq(#e.navs,0);eq(e.nextCalls,0)
  check(e.messages[#e.messages]:find("Nie wybieram tej placowki do nadawania",1,true)~=nil)
end)

test("an unknown counter's exact no-board response persists no-dispatch and future refreshes do not reread",function()
  local b,e=fresh({current=DYNAMIC,noPaths=true});b:readBoard()
  eq(e:count("przeczytaj tablice",DYNAMIC),1);local watchdog=b.timers.watchdog
  b:onLine("Kobieta mowi: Nie masz zadnej poczty.")
  eq(e.marks,0);eq(b.timers.watchdog,watchdog);eq(b.phase,"board")
  b:onLine("Nie masz zadnej poczty.")
  eq(e.marks,1);eq(e.capabilityWrites,1);eq(e.capabilities.noDispatch[DYNAMIC],true)
  eq(e.offices.canDispatch(DYNAMIC),false);eq(b.timers.watchdog,nil)
  e:advance(.5);eq(b.mode,"running");eq(b.phase,"waiting");eq(e.nextCalls,1)
  e:advance(2*b.config.refresh)
  eq(e:count("przeczytaj tablice",DYNAMIC),1);eq(e.marks,1);eq(#e.navs,0)
  eq(b.mode,"running");eq(b.phase,"waiting");check(b.timers.refresh~=nil)
  local resumed,again=fresh({current=DYNAMIC,noPaths=true,capabilities=e.capabilities})
  resumed:readBoard();eq(#again.sends,0);eq(resumed.phase,"waiting");eq(again.marks,0)
end)

test("roaming off at a known delivery-only counter waits without board requests or relocation",function()
  local b,e=fresh({current=EBINO,roam=false});b:readBoard()
  eq(b.phase,"waiting");eq(b.mode,"running");eq(#e.sends,0);eq(#e.navs,0);eq(e.nextCalls,0)
  eq(b.timers.watchdog,nil);check(b.timers.refresh~=nil)
  e:advance(2*b.config.refresh)
  eq(b.phase,"waiting");eq(#e.sends,0);eq(#e.navs,0);eq(e.nextCalls,0)
  check(table.concat(e.messages,"\n"):find("Odswiezanie za",1,true)~=nil)
end)

test("a complete empty board never becomes a permanent no-dispatch observation",function()
  local b,e=fresh({roam=false});b:readBoard();board(b);e:advance(.5)
  eq(b.phase,"waiting");eq(e.marks,0);eq(e.capabilityWrites,0);eq(e.offices.canDispatch(KZ),true)
  e:advance(b.config.refresh);eq(e:count("przeczytaj tablice",KZ),2)
end)

test("only excluded interdomain types report their summary before office planning without resolving any recipient",function()
  local b,e=fresh({asyncPlanning=true});b:readBoard()
  board(b,{"1. Nieznany Adresat miedzydomenowa 1.00 kg 5 zlotych monet [x1]",
    "2. Poczta w Nuln miedzykrainowa 1.00 kg 2 zlote monety [x1]"})
  e:untilTrue(function() return e.nextCalls==1 end)
  eq(#e.resolved,0);eq(#b.offerDiagnostics,2)
  eq(b.offerDiagnostics[1].category,"kind");eq(b.offerDiagnostics[2].category,"kind")
  eq(e:count("wybierz paczke 1"),0);eq(e:count("wybierz paczke 2"),0)
  local summaryAt,nextAt,total
  total=0
  for index,item in ipairs(e.events) do
    if item.kind=="say" and item.value:find("Ocena ofert:",1,true) then summaryAt=index;total=total+1 end
    if item.kind=="nextOffice" then nextAt=index end
  end
  check(summaryAt~=nil);check(nextAt~=nil);check(summaryAt<nextAt,"show exclusion reasons before searching other offices")
  eq(total,1);check(e.events[summaryAt].value:find("0 z 2 spelnia warunki",1,true)~=nil)
  check(table.concat(e.messages,"\n"):find("rodzaj doreczenia: 2",1,true)~=nil)
  eq(b.phase,"relocating");eq(b.relocation.to.id,NULN)
end)

print(string.format("Delivery-only depots: %d tests, %d assertions passed",cases,checks))
