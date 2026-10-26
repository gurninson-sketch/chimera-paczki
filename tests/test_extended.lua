-- Standalone Lua 5.1-compatible engine regression tests. Run from chimera-native.
package.path="chimera_wtyczki/?.lua;"..package.path
local create=dofile("chimera_wtyczki/chimera_paczki/core.lua")
local data=dofile("chimera_wtyczki/chimera_paczki/routes.lua")
local tested,checks=0,0
local function check(value,message) checks=checks+1;assert(value,message or "check failed") end
local function eq(a,b,message) check(a==b,(message or "different values")..": "..tostring(a).." ~= "..tostring(b)) end
local function copy(t) local r={};for k,v in pairs(t) do r[k]=v end;return r end
local office={map=101,id="kz-office",name="Glowna sala poczty w Krainie Zgromadzenia."}
local header="Przesylki dostepne dla kuriera:"
local footer="Naraz mozna niesc tylko jedna przesylke."
local function fresh(overrides,saved)
  local e={time=1000,timers={},archive={},sends={},messages={},nextId=0,navs={},resolved={},routes={},current=copy(office)}
  local b
  local api={
    send=function(cmd) e.sends[#e.sends+1]=cmd end,
    say=function(s) e.messages[#e.messages+1]=s end,
    now=function() return e.time end,
    schedule=function(delay,fn) e.nextId=e.nextId+1;local id=e.nextId;e.timers[id]={at=e.time+delay,fn=fn};e.archive[id]=fn;return id end,
    cancel=function(id) e.timers[id]=nil end,
    source=function() if e.current.name:lower():find("poczt",1,true) then return copy(e.current) end end,
    position=function() return copy(e.current) end,
    resolveRoute=function(name,source)
      e.resolved[#e.resolved+1]={name=name,source=source}
      return e.routes[b.norm(name)]
    end,
    nextOffice=function(source)
      e.officeChecks=(e.officeChecks or 0)+1
      if e.nextOffice then return e.nextOffice(source) end
    end,
    resetOffices=function() e.cooldownResets=(e.cooldownResets or 0)+1 end,
    navigate=function(route,returning,done)
      local n={route=route,returning=returning,done=done,cancelled=0}
      e.navs[#e.navs+1]=n
      if returning and route.map==e.current.map and route.id==e.current.id then n.finished=true;done(true) end
      return function() n.cancelled=n.cancelled+1;done(false,"przerwane") end
    end,
  }
  for key,value in pairs(overrides or {}) do api[key]=value end
  b=create(data,api,saved)
  function e:last() return self.sends[#self.sends] end
  function e:tick()
    local chosen,when
    for id,t in pairs(self.timers) do if not when or t.at<when or (t.at==when and id<chosen) then chosen,when=id,t.at end end
    if not chosen then return false end
    local t=self.timers[chosen];self.timers[chosen]=nil;self.time=t.at;t.fn();return true
  end
  function e:untilSend()
    local before=#self.sends
    for _=1,30 do if not self:tick() then return nil end;if #self.sends>before then return self:last() end end
    error("too many timer steps")
  end
  function e:route(name,cost,postal,map)
    local r={native=true,name=name,cost=cost,commands={},postal=postal,
      destination={map=map or 202,id="target-"..(map or 202),name=postal and name or "Sklep."}}
    self.routes[b.norm(name)]=r;return r
  end
  function e:arrive(n)
    n=n or self.navs[#self.navs]
    self.current=copy(n.returning and n.route or n.route.destination)
    n.finished=true;n.done(true)
  end
  return b,e
end
local function feed(b,lines) for _,s in ipairs(lines) do b:onLine(s) end end
local function start(b,e,limit)
  b:command("start"..(limit and " "..limit or ""))
  eq(e:untilSend(),"przeczytaj tablice")
  eq(b.source.id,office.id);eq(b.staticSource,false)
end
local function board(b,rows)
  b:onLine(header);for _,row in ipairs(rows) do b:onLine(row) end;b:onLine(footer)
end
local function pick(b,e,name,row)
  board(b,{row});eq(e:untilSend(),"wybierz paczke 1")
  b:onLine("Bierzesz paczke przeznaczona dla: "..name..".")
  check(e:tick());eq(b.externalNavigation,true);eq(b.phase,"outbound")
end
local function test(name,fn) fn();tested=tested+1;print("PASS "..name) end

test("KZ source without text exits starts by a complete board, never the Nuln graph",function()
  local b,e=fresh();start(b,e)
  eq(#e.sends,1);eq(b.phase,"board");eq(b.node,nil)
  b:onLine("Glowna sala poczty w Krainie Zgromadzenia.")
  b:onLine("Tu nie ma standardowej listy wyjsc.")
  board(b,{"1. Henry Schmidt miejscowa 1.00 kg 10 srebrnych monet [x1]"})
  check(e:tick());eq(b.phase,"waiting");eq(b.selected,nil)
  eq(e:last(),"przeczytaj tablice")
end)
test("new NPC uses resolved native route and returns to the actual issuing office",function()
  local b,e=fresh();e:route("Johan Kornwalz",14);start(b,e,1)
  pick(b,e,"Johan Kornwalz","1. Johan Kornwalz miejscowa 1.20 kg 8 srebrnych monet [x1]")
  eq(e.navs[#e.navs].route.name,"Johan Kornwalz")
  b:onRoom({title="Ulica.",exits="e,w"});eq(b.mode,"running")
  e:arrive();eq(e:untilSend(),"przedstaw sie");eq(e:untilSend(),"oddaj paczke")
  b:onLine("Wrecasz paczke adresatowi.");eq(b.stats.delivered,1)
  b:onLine("Adresat wrecza ci 8 srebrnych monet za trud.")
  check(e:tick());local n=e.navs[#e.navs]
  eq(n.returning,true);eq(n.route.map,office.map);eq(n.route.id,office.id)
  e:arrive(n);check(e:tick());eq(b.mode,"stopped");eq(b.job,nil);eq(b.stats.silver,8)
  eq(e.current.id,office.id);eq(next(e.timers),nil)
end)
test("postal handover and mixed reward are counted once before returning",function()
  local b,e=fresh();e:route("Poczta w Bissingen",150,true);start(b,e,1)
  pick(b,e,"Poczta w Bissingen","1. Poczta w Bissingen miedzymiastowa 2.00 kg 3 zlote, 14 srebrnych i 9 miedzianych monet [x1]")
  e:arrive();eq(e:untilSend(),"oddaj paczke")
  eq(e.sends[#e.sends-1],"wybierz paczke 1","postal delivery does not introduce to NPC")
  local success="Zostawiasz przesylke w okienku urzedu pocztowego."
  local receipt="Urzednik wyplaca ci 3 zlote, 14 srebrnych i 9 miedzianych monet za trud."
  b:onLine(success);b:onLine(success);eq(b.stats.delivered,1);eq(b.phase,"reward")
  eq(#e.navs,2,"do not return until a reward is confirmed")
  b:onLine(receipt);b:onLine(receipt)
  eq(b.stats.gold,3);eq(b.stats.silver,14);eq(b.stats.copper,9)
  eq(b.moneyValue(b.stats),897)
  check(e:tick());e:arrive();check(e:tick());eq(b.mode,"stopped")
end)
test("local board order ignores reward and distance while retaining weight cap",function()
  local b,e=fresh();e:route("Johan Kornwalz",10);e:route("Mortimer Blatterburn",100);e:route("Berta Leibentropp",2)
  b.source=copy(office);b.staticSource=false
  local rows={b:parseOffer("1. Johan Kornwalz miejscowa 1.00 kg 10 srebrnych monet [x1]"),
    b:parseOffer("2. Mortimer Blatterburn miejscowa 1.00 kg 1 zlota moneta [x1]"),
    b:parseOffer("3. Berta Leibentropp miejscowa 3.50 kg 15 srebrnych monet [x1]")}
  local ranked=b:rank(rows);eq(#ranked,2);eq(ranked[1].name,"johan kornwalz")
  b:command("tryb zaplata");ranked=b:rank(rows);eq(ranked[1].name,"johan kornwalz")
  b:command("limit 3.5");b:command("tryb zarobek");ranked=b:rank(rows)
  eq(#ranked,3);eq(ranked[1].name,"johan kornwalz")
end)
test("number vanished rejection rereads the board without moving",function()
  local b,e=fresh();e:route("Johan Kornwalz",14);start(b,e)
  board(b,{"6. Johan Kornwalz miejscowa 1.20 kg 8 srebrnych monet [x1]"});eq(e:untilSend(),"wybierz paczke 6")
  b:onLine("Nie ma przesylki o numerze 6.");eq(b.awaitingPickup,false)
  eq(e:untilSend(),"przeczytaj tablice");eq(#e.navs,1);eq(b.job,nil)
end)
test("STOP invalidates an external callback and cancels navigation exactly once",function()
  local b,e=fresh();e:route("Johan Kornwalz",14);start(b,e)
  pick(b,e,"Johan Kornwalz","1. Johan Kornwalz miejscowa 1.20 kg 8 srebrnych monet [x1]")
  local n=e.navs[#e.navs];local before=#e.sends;b:command("stop")
  eq(n.cancelled,1);eq(b.externalNavigation,nil);eq(b.cancelNavigation,nil);eq(next(e.timers),nil)
  n.done(true);n.done(false,"late failure");for _,fn in pairs(e.archive) do fn() end
  eq(#e.sends,before);eq(b.mode,"stopped");eq(next(e.timers),nil)
end)
test("late postal confirmations after STOP reconcile once without starting a return",function()
  local b,e=fresh();e:route("Poczta w Bissingen",150,true);start(b,e)
  pick(b,e,"Poczta w Bissingen","1. Poczta w Bissingen miedzymiastowa 2.00 kg 3 zlote, 14 srebrnych i 9 miedzianych monet [x1]")
  e:arrive();eq(e:untilSend(),"oddaj paczke");b:command("stop");local before=#e.sends
  for _=1,2 do
    b:onLine("Zostawiasz przesylke w okienku urzedu pocztowego.")
    b:onLine("Urzednik wyplaca ci 3 zlote, 14 srebrnych i 9 miedzianych monet za trud.")
  end
  eq(b.stats.delivered,1);eq(b.stats.gold,3);eq(b.stats.silver,14);eq(b.stats.copper,9)
  eq(b.mode,"stopped");eq(#e.sends,before);eq(next(e.timers),nil)
end)
test("missing addressee does not become a success or retry delivery",function()
  local b,e=fresh();e:route("Johan Kornwalz",14);start(b,e)
  pick(b,e,"Johan Kornwalz","1. Johan Kornwalz miejscowa 1.20 kg 8 srebrnych monet [x1]")
  e:arrive();e:untilSend();eq(e:untilSend(),"oddaj paczke");local before=#e.sends
  b:onLine("Adresat nie znajduje sie w tym miejscu.")
  b:onLine("Musisz odnalezc Johan Kornwalz i wreczyc mu paczke osobiscie.")
  eq(b.mode,"paused");eq(b.awaitingDelivery,false);eq(b.stats.delivered,0);eq(b.job.delivered,false)
  eq(#e.sends,before);eq(next(e.timers),nil)
end)
test("return cannot read a different office board",function()
  local b,e=fresh();start(b,e);e.current={map=999,id="another-office",name="Poczta."}
  local before=#e.sends;b:readBoard();eq(b.mode,"paused");eq(#e.sends,before)
end)
test("resume preserves KZ source while restarting a cancelled native search",function()
  local b,e=fresh();e:route("Johan Kornwalz",14);start(b,e)
  pick(b,e,"Johan Kornwalz","1. Johan Kornwalz miejscowa 1.20 kg 8 srebrnych monet [x1]")
  local old=e.navs[#e.navs];b:command("stop")
  e.current={map=303,id="intermediate-street",name="Ulica."}
  local before=#e.navs;b:command("wznow")
  eq(#e.navs,before+1);eq(b.mode,"running");eq(b.phase,"outbound")
  eq(b.source.id,office.id);eq(b.job.source.id,office.id)
  eq(old.cancelled,1);eq(e.navs[#e.navs].route.name,"Johan Kornwalz")
end)
test("resume native Nuln delivery outside the static graph uses mapped position",function()
  local b,e=fresh();local route=e:route("Johan Kornwalz",14)
  b.source={map=101,id="nuln-office",name="Poczta."};b.staticSource=true
  b.job={name="Johan Kornwalz",route=route,delivered=false,source=b.source}
  e.current={map=303,id="new-room-beyond-static-routes",name="Nowa pracownia."}
  b:command("wznow")
  eq(b.externalNavigation,true);eq(b.phase,"outbound");eq(#e.navs,1)
  eq(b.source.id,"nuln-office");eq(#e.sends,0,"no text localization on a mapped native route")
end)
test("fresh start refreshes the office and account switch forgets source IDs",function()
  local b,e=fresh();start(b,e);b:command("stop")
  e.current={map=404,id="kz-other-office",name="Urzad pocztowy."}
  b:command("start");eq(b.source.id,"kz-other-office");eq(b.source.map,404)
  eq(e:untilSend(),"przeczytaj tablice");b:command("stop")
  b:onLine("Witaj, Inny. Podaj haslo do konta:")
  eq(b.source,nil);eq(b.staticSource,nil);eq(b.job,nil)
end)

test("real Olaff sequence reconciles manual handover during navigation pause",function()
  local b,e=fresh();local r=e:route("Olaff Meier Mlodszy",60)
  b.source=copy(office);b.staticSource=false
  b.job={name=r.name,route=r,source=b.source,delivered=false}
  b.stats.delivered=6;b.stats.silver=60
  b:pause("Nawigacja: nie znaleziono adresata w znanych lokacjach")
  eq(b.awaitingDelivery,nil)
  b:onCommand("oddaj paczke");eq(b.awaitingDelivery,true)
  local count=#e.sends
  for _=1,2 do
    b:onLine("Wrecasz paczke adresatowi.")
    b:onLine("Adresat wrecza ci 8 srebrnych monet za trud.")
  end
  eq(b.stats.delivered,7);eq(b.stats.silver,68);eq(b.job.delivered,true)
  eq(b.mode,"paused");eq(#e.sends,count);eq(next(e.timers),nil)
  b:command("start")
  eq(b.mode,"running");eq(e.navs[#e.navs].returning,true)
  eq(e:untilSend(),"przeczytaj tablice");eq(b.job,nil)
end)
test("failed manual handover clears the attempt and retains the unfinished parcel",function()
  local b,e=fresh();local r=e:route("Olaff Meier Mlodszy",60)
  b.job={name=r.name,route=r,delivered=false};b:pause("brak adresata")
  b:onCommand("oddaj paczke");eq(b.awaitingDelivery,true)
  b:onLine("Adresat nie znajduje sie w tym miejscu.")
  eq(b.awaitingDelivery,false);eq(b.manualDelivery,false)
  eq(b.stats.delivered,0);eq(b.job.delivered,false);eq(next(e.timers),nil)
end)
test("manual delivery while running cancels future movement but observes its reply",function()
  local b,e=fresh();e:route("Johan Kornwalz",14);start(b,e)
  pick(b,e,"Johan Kornwalz","1. Johan Kornwalz miejscowa 1.20 kg 8 srebrnych monet [x1]")
  local nav=e.navs[#e.navs];b:onCommand("oddaj paczke")
  eq(nav.cancelled,1);eq(b.mode,"paused");eq(b.awaitingDelivery,true)
  b:onLine("Wrecasz paczke adresatowi.");b:onLine("Adresat wrecza ci 8 srebrnych monet za trud.")
  eq(b.stats.delivered,1);eq(b.stats.silver,8);eq(b.job.delivered,true)
  eq(next(e.timers),nil)
end)
test("refused restart reports the current reason instead of the preceding failure",function()
  local b,e=fresh();b.lastPause="stary blad";b.job={name="Olaff Meier Mlodszy",delivered=false}
  b:command("start");check(b.lastPause:find("Pamietam",1,true));check(not b.lastPause:find("stary blad",1,true))
  eq(b.mode,"stopped");eq(#e.sends,0)
end)
test("a truncated board never triggers automatic office relocation",function()
  local b,e=fresh();local destination={map=404,id="bissingen",name="Poczta Bissingen",cost=12}
  e.nextOffice=function() return destination end;start(b,e)
  b:onLine(header);local checksBefore=e.officeChecks or 0;local sends=#e.sends
  check(e:tick());eq(b.mode,"paused");eq(e.officeChecks or 0,checksBefore)
  eq(#e.sends,sends);eq(b.relocation,nil);eq(#e.navs,1)
end)
test("relocation pins new source only after both map and hash confirmation",function()
  local b,e=fresh();local destination={map=404,id="bissingen",name="Poczta Bissingen",cost=12}
  e.nextOffice=function() return destination end;start(b,e);board(b,{})
  check(e:tick());eq(b.phase,"relocating");eq(b.source.id,office.id)
  eq(b.relocation.to.id,"bissingen");local n=e.navs[#e.navs]
  e.current={map=404,id="wrong-hash",name="Poczta."};n.done(true);check(e:tick())
  eq(b.mode,"paused");eq(b.source.id,office.id);eq(e:last(),"przeczytaj tablice")
  eq(b.relocation.to.id,"bissingen");eq(next(e.timers),nil)
end)
test("unconfirmed package operations never permit relocation or another pickup",function()
  for _,field in ipairs({"awaitingPickup","awaitingDelivery","awaitingReturn","awaitingReward"}) do
    local b,e=fresh();start(b,e);b[field]=true
    e.nextOffice=function() error("must not search for another office") end
    local count=#e.sends;b:choose()
    eq(b.mode,"paused");eq(b.relocation,nil);eq(#e.sends,count);eq(e.officeChecks,nil)
  end
end)
test("weight changes and reset invalidate previously empty-office observations",function()
  local b,e=fresh();b:command("limit 6.7");eq(1,e.cooldownResets)
  b:command("tempo 0.7");eq(1,e.cooldownResets)
  b.relocation={to={id="somewhere"}};b:command("reset")
  eq(2,e.cooldownResets);eq(b.relocation,nil);eq(b.source,nil)
end)
test("durable Nuln intent restores its saved text route after map numbers change",function()
  local checkpoint=dofile("chimera_wtyczki/chimera_paczki/checkpoint.lua")({}, {now=function() return 1000 end})
  local nuln="6f2c03461c2f1438"
  local custom={name="Adresat recznej trasy",commands={"nw","s"},rooms={copy(data.office),
    copy(data.routes["Berta Leibentropp"].rooms[2]),{title="Kram recznie nauczonego adresata.",exits="n"}}}
  check(checkpoint.put("ActorA",{source={id=nuln,map=101,name="Poczta",staticNuln=true},
    job={name=custom.name,recipientConfirmed=true,delivered=false},flags={},stopAt=1,
    stats={delivered=0,gold=0,silver=0,copper=0},inventory={state="hands"}}))
  eq(checkpoint.get("ActorA").source.map,nil)
  eq(checkpoint.get("ActorA").job.route,nil,"checkpoint cannot carry executable route commands")
  local b,e=fresh({loadRun=checkpoint.get,saveRun=checkpoint.put,sessionReady=function() return true end,
    restorePlace=function(place)
      if place.id==nuln then return {id=nuln,map=777,name="Poczta",staticNuln=true} end
    end}, {customRoutes={custom=custom}})
  b:identifyActor("ActorA",true)
  eq(b.mode,"paused");eq(#e.sends,0,"restoring intent must not start the courier")
  eq(b.job.route,nil);eq(b.staticSource,true)
  b:command("wznow")
  eq(e:last(),"zerknij");eq(b.source.map,777);eq(b.staticSource,true)
  eq(b.job.route.name,custom.name);check(not b.job.route.native)
  check(#e.resolved>0,"native resolution must still be tried before the saved text route")
  b:onRoom(copy(custom.rooms[2]));eq(e:untilSend(),"s","resume localizes the current room instead of repeating nw")
  b:onRoom(copy(custom.rooms[3]));eq(e:untilSend(),"przedstaw sie");eq(e:untilSend(),"oddaj paczke")
  b:onLine("Wrecasz paczke adresatowi.");b:onLine("Adresat wrecza ci 8 srebrnych monet za trud.")
  eq(e:untilSend(),"n");b:onRoom(copy(custom.rooms[2]))
  eq(e:untilSend(),"se");b:onRoom(copy(data.office));check(e:tick())
  eq(b.mode,"stopped");eq(b.stats.delivered,1);eq(b.job,nil)
  eq(checkpoint.get("ActorA").job,nil);eq(checkpoint.get("ActorA").stats.silver,8)
end)
test("reset preserves both live and durable courses until their deletion is saved",function()
  for _,failure in ipairs({"false","throw"}) do
    local reject,stored,restores=nil,nil,0
    local checkpoint=dofile("chimera_wtyczki/chimera_paczki/checkpoint.lua")({}, {
      now=function() return 1000 end,
      save=function(state)
        if reject=="false" then return false end
        if reject=="throw" then error("profile storage unavailable") end
        stored=state
      end,
    })
    local held={state="bag",container={d="swojego plecaka",containerWord="plecaka"},coinsUncertain=false}
    local b,e=fresh({saveRun=checkpoint.put,loadRun=checkpoint.get,forgetRun=checkpoint.forget,
      inventoryState=function() return held end,
      restoreInventory=function(state) held=state;restores=restores+1 end})
    b:identifyActor("ActorA",true)
    b.source=copy(office);b.staticSource=false
    b.job={name="Johan Kornwalz",source=b.source,recipientConfirmed=true,delivered=false,actor=b.actor}
    b.stats={delivered=4,gold=2,silver=17,copper=3,started=900};b.stopAt=7
    b.awaitingDelivery=true;b:checkpoint()
    eq(checkpoint.get("ActorA").job.name,b.job.name)
    local before=#e.sends
    reject=failure;b:command("reset")
    eq(b.mode,"stopped");eq(#e.sends,before);eq(restores,0)
    eq(b.job.name,"Johan Kornwalz");eq(b.source.id,office.id)
    eq(b.stats.delivered,4);eq(b.stats.silver,17);eq(b.stopAt,7)
    eq(b.awaitingDelivery,true);eq(b.runCleared,nil);eq(held.state,"bag")
    check(b.lastPause:find("Nie usunieto zapisu kursu",1,true))
    eq(checkpoint.get("ActorA").job.name,"Johan Kornwalz")
    eq(checkpoint.get("ActorA").flags.awaitingDelivery,true)
    eq(stored.actors.actora.stats.silver,17)
    reject=nil;b:command("reset")
    eq(b.job,nil);eq(b.source,nil);eq(b.stopAt,nil);eq(b.stats.delivered,0)
    eq(b.awaitingDelivery,false);eq(b.runCleared,true);eq(restores,1)
    eq(held.state,"hands");eq(held.coinsUncertain,false)
    eq(checkpoint.get("ActorA"),nil);eq(stored.actors.actora,nil)
    b:disconnected()
    eq(checkpoint.get("ActorA"),nil,"a later disconnect cannot resurrect a successfully reset course")
    eq(#e.sends,before)
  end
end)
test("manual office selection cannot discard pending or uncertain coin storage",function()
  for _,uncertainty in ipairs({"job","inventory","saved"}) do
    local reads=0
    local b,e=fresh({currentOffice=function() reads=reads+1;return copy(office) end,
      inventoryState=function() return {state="hands",coinsUncertain=uncertainty=="inventory"} end})
    local original={name="Poczta w Bissingen",delivered=true,coinsPending=uncertainty=="job"}
    b.job=original;b.source=copy(office);b.savedInventoryUncertain=uncertainty=="saved"
    b.stats.delivered=3;b.stopAt=5
    b:command("poczta tutaj")
    eq(b.job,original);eq(b.job.delivered,true);eq(b.source.id,office.id)
    eq(b.stats.delivered,3);eq(b.stopAt,5);eq(b.mode,"stopped")
    eq(reads,0);eq(#e.sends,0);eq(#e.navs,0);eq(next(e.timers),nil)
    check(b.lastPause:find("Najpierw rozlicz",1,true))
  end
end)
test("office selection waits for fresh GMCP without replacing the saved relocation",function()
  local checkpoint=dofile("chimera_wtyczki/chimera_paczki/checkpoint.lua")({}, {now=function() return 1000 end})
  check(checkpoint.put("ActorA",{source={id="old-office",name="Stara poczta"},
    relocation={to={id="intended-office",name="Wybrana poczta"},manual=true},
    flags={},stats={delivered=3,silver=27},stopAt=6,inventory={state="hands"}}))
  local validations=0
  local b,e=fresh({loadRun=checkpoint.get,saveRun=checkpoint.put,
    sessionReady=function(actor) validations=validations+1;eq(actor,"actora");return false,"Brak aktualnego GMCP." end,
    currentOffice=function() error("must not choose an office before fresh identity and room data") end})
  b:identifyActor("ActorA",true);eq(b.mode,"paused")
  b:command("poczta tutaj")
  eq(validations,1);eq(b.mode,"paused");eq(b.needsResumeValidation,true)
  eq(b.source.id,"old-office");eq(b.relocation.to.id,"intended-office");eq(b.relocation.manual,true)
  eq(b.stats.delivered,3);eq(b.stopAt,6);eq(b.lastPause,"Brak aktualnego GMCP.")
  eq(checkpoint.get("ActorA").source.id,"old-office")
  eq(checkpoint.get("ActorA").relocation.to.id,"intended-office")
  eq(#e.sends,0);eq(#e.navs,0);eq(next(e.timers),nil)
end)
test("settled postal delivery recognizes an unregistered depot only at its exact route map and hash",function()
  local b,e=fresh({currentOffice=function() return nil end})
  local destination={map=602,id="ebino-depot",name="Ebinska placowka kurierska."}
  e.current=copy(destination);b.source=copy(office);b.staticSource=false
  local route=e:route("Poczta w Ebino",120,true,602)
  route.targetId=destination.id;route.roomIds={[602]=destination.id}
  b.job={name=route.name,route=route,source=b.source,delivered=true,coinsPending=false}
  b.mode="running";b.stats={delivered=9,gold=10,silver=98,copper=15};b.stopAt=12
  b:afterDelivery()
  eq(b.mode,"running");eq(b.phase,"board");eq(b.job,nil)
  eq(b.source.id,destination.id);eq(b.source.map,destination.map)
  eq(b.source.name,destination.name);eq(e:last(),"przeczytaj tablice")
  eq(#e.navs,0);eq(b.stats.delivered,9);eq(b.stats.gold,10);eq(b.stopAt,12)
end)

test("a manually moved settled postal job continues at the verified current office without returning",function()
  local current={map=704,id="campogrotta",name="Poczta w Campogrotta"}
  local b,e=fresh({currentOffice=function() return copy(current) end})
  e.current=copy(current);b.source=copy(office);b.staticSource=false
  local route=e:route("Poczta w Ebino",120,true,602)
  route.targetId="ebino-depot";route.roomIds={[602]=route.targetId}
  b.job={name=route.name,route=route,source=b.source,delivered=true,coinsPending=false}
  b.stats.delivered=9;b.stopAt=12
  b:command("wznow")
  eq(b.mode,"running");eq(b.phase,"board");eq(b.job,nil)
  eq(b.source.id,current.id);eq(b.source.map,current.map)
  eq(e:last(),"przeczytaj tablice");eq(#e.sends,1);eq(#e.navs,0)
  eq(b.stats.delivered,9);eq(b.stopAt,12)
end)

test("postal recovery on an unknown road or with a mismatched depot map keeps the completed job",function()
  for _,position in ipairs({{map=602,id="wrong-hash",name="Droga."},{map=603,id="ebino-depot",name="Placowka."}}) do
    local b,e=fresh({currentOffice=function() return nil end})
    e.current=position;b.source=copy(office);b.staticSource=false
    local route=e:route("Poczta w Ebino",120,true,602)
    route.targetId="ebino-depot";route.roomIds={[602]=route.targetId}
    local job={name=route.name,route=route,source=b.source,delivered=true,coinsPending=false}
    b.job=job;b.mode="running";b.stats.delivered=9;b.stopAt=12
    b:afterDelivery()
    eq(b.mode,"paused");eq(b.job,job);eq(b.source.id,office.id)
    eq(#e.sends,0);eq(#e.navs,0);eq(b.stats.delivered,9);eq(b.stopAt,12)
  end
end)

test("post-delivery adoption never discards an unconfirmed handover reward or coin transfer",function()
  for _,field in ipairs({"delivered","coinsPending","awaitingDelivery","awaitingReward","inventory"}) do
    local reads=0
    local b,e=fresh({currentOffice=function() reads=reads+1;return copy(office) end,
      inventoryState=function() return {state="hands",coinsUncertain=field=="inventory"} end})
    b.source=copy(office)
    local route=e:route("Poczta w Ebino",120,true,602)
    local job={name=route.name,route=route,source=b.source,delivered=field~="delivered",coinsPending=field=="coinsPending"}
    b.job=job;b.mode="running"
    if field=="awaitingDelivery" or field=="awaitingReward" then b[field]=true end
    b:afterDelivery()
    eq(b.mode,"paused");eq(b.job,job);eq(reads,0);eq(#e.sends,0);eq(#e.navs,0)
  end
end)

test("explicitly unavailable depot board follows normal nearest-office roaming instead of timing out",function()
  local b,e=fresh();e.current={map=602,id="ebino-depot",name="Ebinska placowka kurierska."}
  b.source=copy(e.current);b.staticSource=false;b.mode="running";b.stats.delivered=9;b.stopAt=12
  local nextOffice={map=704,id="campogrotta",name="Poczta w Campogrotta",cost=54}
  e.nextOffice=function(source) eq(source.id,"ebino-depot");return nextOffice end
  b:readBoard();eq(e:last(),"przeczytaj tablice")
  b:onLine("Nie masz zadnej poczty.")
  eq(b.timers.watchdog,nil);eq(b.phase,"planning");check(e:tick())
  eq(b.mode,"running");eq(b.phase,"relocating");eq(b.relocation.to.id,nextOffice.id)
  eq(e.officeChecks,1);eq(#e.navs,1);eq(#e.sends,1)
  e:arrive();eq(e:untilSend(),"przeczytaj tablice")
  eq(b.source.id,nextOffice.id);eq(b.job,nil);eq(b.stats.delivered,9);eq(b.stopAt,12)
end)

test("unavailable board with roaming off refreshes at the chosen interval and ignores foreign prose",function()
  local b,e=fresh();b.source=copy(office);b.staticSource=false;b.mode="running";b.config.roam=false
  b:readBoard();local watchdog=b.timers.watchdog
  b:onLine("Kobieta mowi: Nie masz zadnej poczty.")
  eq(b.phase,"board");eq(b.timers.watchdog,watchdog);eq(#e.sends,1)
  b:onLine("Nie masz zadnej poczty.");check(e:tick())
  eq(b.phase,"waiting");eq(b.mode,"running");eq(b.timers.watchdog,nil)
  eq(e.officeChecks,nil);eq(#e.navs,0);eq(#e.sends,1)
  local when=e.time;eq(e:untilSend(),"przeczytaj tablice")
  eq(e.time,when+b.config.refresh);eq(b.mode,"running")
end)
print(string.format("Extended engine: %d tests, %d assertions passed",tested,checks))
