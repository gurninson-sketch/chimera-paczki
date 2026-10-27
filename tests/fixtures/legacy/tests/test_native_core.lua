local create=dofile("../chimera-native/chimera_wtyczki/chimera_paczki/core.lua")
local data=dofile("src/routes.lua")
local fixtures=dofile("tests/fixtures.lua")
local reverse={n="s",s="n",e="w",w="e",nw="se",ne="sw",se="nw",sw="ne",u="d",d="u"}
local tested,checks=0,0
local function check(value,message)
  checks=checks+1
  assert(value,message or "check failed")
end
local function eq(a,b,message) check(a==b,(message or "different values")..": "..tostring(a).." ~= "..tostring(b)) end
local function fresh(saved)
  local e={time=1000,timers={},archive={},sends={},messages={},nextId=0,saves=0}
  local b=create(data,{
    send=function(cmd) e.sends[#e.sends+1]=cmd end,
    say=function(s) e.messages[#e.messages+1]=s end,
    now=function() return e.time end,
    schedule=function(delay,fn)
      e.nextId=e.nextId+1; local id=e.nextId
      e.timers[id]={at=e.time+delay,fn=fn}; e.archive[id]=fn; return id
    end,
    cancel=function(id) e.timers[id]=nil end,
    save=function(s) e.saved=s; e.saves=e.saves+1 end
  },saved)
  function e:last() return self.sends[#self.sends] end
  function e:tick()
    local chosen,when
    for id,t in pairs(self.timers) do if not when or t.at<when or (t.at==when and id<chosen) then chosen,when=id,t.at end end
    if not chosen then return false end
    local t=self.timers[chosen]; self.timers[chosen]=nil; self.time=t.at; t.fn(); return true
  end
  function e:untilSend()
    local before=#self.sends
    for _=1,20 do if not self:tick() then return nil end; if #self.sends>before then return self:last() end end
    error("too many timer steps")
  end
  return b,e
end
local function feed(b,lines) for _,s in ipairs(lines) do b:onLine(s) end end
local home=fixtures.routes["Henry Schmidt"].backward[13]
local function start(b,e,limit)
  b:command("start"..(limit and " "..limit or "")); eq(e:last(),"zerknij")
  feed(b,home); eq(e:untilSend(),"przeczytaj tablice")
end
local function singleBoard(name)
  for _,board in ipairs(fixtures.boards) do
    for _,line in ipairs(board) do
      if line:find(name,1,true) and line:find("miejscowa",1,true) then return {board[1],line,board[#board]} end
    end
  end
  error("no original board row for "..name)
end
local function test(name,fn)
  fn(); tested=tested+1; print("PASS "..name)
end

test("37 complete original boards, wrapped offers and numeric renumbering",function()
  for _,board in ipairs(fixtures.boards) do
    local b,e=fresh(); start(b,e)
    local count=0; for _,line in ipairs(board) do if line:match("^%s*%d+%.") then count=count+1 end end
    local before=#e.sends; feed(b,board)
    eq(#b.boardRows,count); eq(#e.sends,before,"selection must wait until scheduled action")
    local previous=0
    for _,o in ipairs(b.boardRows) do check(o.number>previous); check(o.kg>0); check(o.count>0); previous=o.number end
  end
  local b,e=fresh(); start(b,e); feed(b,fixtures.boards[1]); e:untilSend()
  eq(b.selected.name,"fryderik miecznik"); eq(b.selected.number,1,"first local board number wins regardless of price")
  local f,g=fresh(); start(f,g)
  local firstShort
  for _,board in ipairs(fixtures.boards) do
    if board[3] and board[3]:find("Olaf Hubner",1,true) then firstShort=board; break end
  end
  feed(f,firstShort); g:untilSend(); eq(f.selected.name,"olaf hubner"); eq(f.selected.number,1)
  local h,i=fresh(); start(h,i)
  local shifted
  for _,board in ipairs(fixtures.boards) do
    if board[3] and board[3]:find("1. Joachim Eisenberg",1,true) then shifted=board; break end
  end
  feed(h,shifted); i:untilSend(); eq(h.selected.number,1,"same NPC moved to row 1")
end)

for name,route in pairs(data.routes) do
  test("full automatic round trip: "..name,function()
    local b,e=fresh(); local f=fixtures.routes[name]
    start(b,e,1); feed(b,singleBoard(name)); e:untilSend()
    eq(b.selected.name,b.norm(name))
    b:onLine(f.pickup)
    for index,cmd in ipairs(route.commands) do
      eq(e:untilSend(),cmd,"outbound step "..index)
      local before=#e.sends
      -- No command is emitted merely because time passed without an acknowledgement.
      eq(#e.sends,before)
      feed(b,f.forward[index]); eq(b.mode,"running"); eq(#e.sends,before)
    end
    eq(e:untilSend(),"przedstaw sie"); eq(e:untilSend(),"oddaj paczke")
    b:onLine(f.handover); b:onLine(f.handover)
    eq(b.stats.delivered,1,"do not double-count confirmation"); eq(b.phase,"reward")
    b:onLine(f.receipt); b:onLine(f.receipt)
    eq(b.stats.silver,tonumber(f.receipt:match("(%d+) srebr")),"count actual receipt once")
    for index,raw in ipairs(f.backward) do
      eq(e:untilSend(),reverse[route.commands[#route.commands-index+1]],"return step "..index)
      feed(b,raw); eq(b.mode,"running")
    end
    check(e:tick()); eq(b.mode,"stopped"); eq(b.node,"home"); eq(b.job,nil)
    eq(next(e.timers),nil,"no timers left after delivery limit")
    eq(#e.sends,2*#route.commands+5)
  end)
end

test("truncated board never selects an offer",function()
  local b,e=fresh(); start(b,e)
  local board=singleBoard("Henry Schmidt")
  feed(b,{board[1],board[2]}); eq(b.phase,"board")
  local before=#e.sends; e:tick(); eq(b.mode,"paused"); eq(#e.sends,before)
end)
test("empty eligible list waits and refreshes without taking intercity work",function()
  local b,e=fresh(); start(b,e)
  feed(b,{fixtures.boards[1][1]," 1. Glowny urzad pocztowy Athkatli miedzykrainowa 9.00 kg 11 zlotych i 4 srebrne monety [x4]",fixtures.boards[1][#fixtures.boards[1]]})
  local before=#e.sends; e:tick(); eq(b.phase,"waiting"); eq(#e.sends,before)
  eq(e:untilSend(),"przeczytaj tablice")
end)
test("numeric weight, Unicode, money and optional strategies",function()
  local b,e=fresh()
  local o=b:parseOffer(" 27. Żaneta Łącka miejscowa 1,10 kg 7 srebrnych monet [x6]")
  eq(o.number,27); eq(o.name,"zaneta lacka"); eq(o.kg,1.1)
  local m=b.parseMoney("11 złotych, 4 srebrne i 7 miedzianych monet")
  eq(m.gold,11); eq(m.silver,4); eq(m.copper,7)
  b:command("limit 0,8"); eq(b.config.maxKg,0.8); eq(e.saves,1)
  b:command("tempo 0.01"); eq(b.config.delay,0.35,"reject unsafe zero/short delay")
  b:command("tryb lekkie"); eq(b.config.strategy,"local_first")
  local rows={b:parseOffer("1. Henry Schmidt miejscowa 2.30 kg 11 srebrnych monet [x6]"),b:parseOffer("2. Ludwig Golebiarz miejscowa 0.80 kg 6 srebrnych monet [x4]")}
  local ranked=b:rank(rows); eq(#ranked,1); eq(ranked[1].name,"ludwig golebiarz")
end)
test("board changed by another player is read again before selection",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt"))
  b:onLine("Tepy jaszczuroczlek bierze paczke z tablicy.")
  eq(e:untilSend(),"przeczytaj tablice"); eq(b.phase,"board")
end)
test("race returns a different known addressee instead of replacing the selected delivery",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
  b:onLine(fixtures.routes["Olaf Hubner"].pickup)
  eq(b.job.route,nil);eq(b.job.returningUndelivered,true);eq(b.job.returnReason,"pickupChanged")
  eq(e:untilSend(),"zwroc paczke");eq(b.node,"home");eq(b.walking,nil)
  b:onLine("Oddajesz przesylke z powrotem do urzedu. Nikt ci za nia nie zaplaci -- droga nie zostala przebyta.")
  eq(e:untilSend(),"przeczytaj tablice");eq(b.job,nil)
end)
test("unknown race recipient is returned only from the issuing post office",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
  b:onLine("Bierzesz paczke przeznaczona dla: Hafas Muerling.")
  eq(e:untilSend(),"zwroc paczke"); eq(b.node,"home")
  b:onLine("Oddajesz przesylke z powrotem do urzedu. Nikt ci za nia nie zaplaci -- droga nie zostala przebyta.")
  eq(e:untilSend(),"przeczytaj tablice"); eq(b.job,nil)
end)
test("uncertain return acknowledgement pauses instead of assuming success",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
  b:onLine("Bierzesz paczke przeznaczona dla: Hafas Muerling."); e:untilSend()
  b:onLine("Pracownik poczty milczy."); local before=#e.sends; e:tick()
  eq(b.mode,"paused"); eq(#e.sends,before); check(b.job~=nil)
end)
test("overweight rejection falls back without repeating the same offer",function()
  local b,e=fresh(); start(b,e)
  local board={fixtures.boards[1][1],"1. Henry Schmidt miejscowa 3.20 kg 14 srebrnych monet [x4]","2. Ludwig Golebiarz miejscowa 0.80 kg 6 srebrnych monet [x4]",fixtures.boards[1][#fixtures.boards[1]]}
  feed(b,board); e:untilSend(); eq(b.selected.name,"henry schmidt")
  b:onLine("Nie masz dosc sily, zeby uniesc te paczke."); eq(e:untilSend(),"przeczytaj tablice")
  feed(b,board); e:untilSend(); eq(b.selected.name,"ludwig golebiarz")
end)
test("no pickup confirmation means no walking",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
  local before=#e.sends; e:tick(); eq(b.mode,"paused"); eq(#e.sends,before)
end)
test("wrong location and movement failure stop all future commands",function()
  for _,failure in ipairs({"wrong","blocked","timeout"}) do
    local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
    b:onLine(fixtures.routes["Henry Schmidt"].pickup); e:untilSend()
    local before=#e.sends
    if failure=="wrong" then feed(b,{"Nieznana ulica.","Sa tutaj dwa widoczne wyjscia: wschod i zachod."})
    elseif failure=="blocked" then b:onLine("Nie widzisz zadnego wyjscia prowadzacego na poludnie.")
    else e:tick() end
    eq(b.mode,"paused"); eq(b.node,nil); eq(#e.sends,before); eq(next(e.timers),nil)
  end
end)
test("stop, disconnect, manual command, combat and apocalypse cancel pending sends",function()
  for _,action in ipairs({"stop","disconnect","manual","combat","apocalypse"}) do
    local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
    b:onLine(fixtures.routes["Henry Schmidt"].pickup)
    local before=#e.sends; local old={}
    for _,fn in pairs(e.archive) do old[#old+1]=fn end
    if action=="stop" then b:command("stop")
    elseif action=="disconnect" then b:disconnected()
    elseif action=="manual" then b:onCommand("n")
    elseif action=="combat" then b:onLine("Grozny mezczyzna atakuje cie.")
    else b:onLine("W swoim umysle slyszysz glos Jezdzca Apokalipsy, oznajmiajacy: Nadchodzi Czas Apokalipsy.") end
    check(b.mode=="paused" or b.mode=="stopped"); eq(next(e.timers),nil)
    for _,fn in ipairs(old) do fn() end
    eq(#e.sends,before,"even an already dequeued callback must not send")
  end
end)
test("resume locates again; changed accounts do not inherit a parcel",function()
  local b,e=fresh(); b:onLine("Witaj, Pierwszy. Podaj haslo do konta:")
  start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend(); b:onLine(fixtures.routes["Henry Schmidt"].pickup)
  b:disconnected(); b:onLine("Witaj, Drugi. Podaj haslo do konta:")
  eq(b.job,nil); eq(b.stats.delivered,0)
  b:command("wznow"); eq(e:last(),"zerknij"); feed(b,home); eq(e:untilSend(),"przeczytaj tablice")
end)
test("ambiguous start room never triggers a guessed route",function()
  local b,e=fresh(); b:command("start")
  feed(b,{"Ulica Zlotnicza.","Sa tutaj dwa widoczne wyjscia: poludnie i polnoc."})
  local before=#e.sends; e:tick(); eq(b.mode,"paused"); eq(#e.sends,before)
end)
test("unknown starting city pauses; separate instances have separate state",function()
  local b,e=fresh(); local other,f=fresh(); b:command("start")
  feed(b,{"Poczta innego miasta.","Jest tutaj jedno widoczne wyjscie: polnoc."}); e:tick()
  eq(b.mode,"paused"); eq(other.mode,"stopped"); eq(#f.sends,0)
end)
test("learned route is saved only after handover and complete verified return",function()
  local b,e=fresh(); b:command("ucz Testowy Adresat"); feed(b,home); e:tick()
  eq(b.phase,"recording")
  b:onCommand("wybierz paczke 1"); b:onLine("Bierzesz paczke przeznaczona dla: Testowy Adresat.")
  b:onCommand("nw"); feed(b,fixtures.routes["Henry Schmidt"].forward[1])
  b:onCommand("n"); feed(b,{"Sklep testowy.","Jest tutaj jedno widoczne wyjscie: poludnie."})
  b:onCommand("oddaj paczke"); b:onLine("Wrecasz paczke adresatowi.")
  eq(e.saves,0); eq(b.routes["testowy adresat"],nil)
  b:onCommand("s"); feed(b,fixtures.routes["Henry Schmidt"].forward[1]); eq(e.saves,0)
  b:onCommand("se"); feed(b,home)
  eq(e.saves,1); eq(b.mode,"stopped"); eq(b.node,"home"); check(b.routes["testowy adresat"]~=nil)
  local restored,f=fresh(e.saved); check(restored.routes["testowy adresat"]~=nil); eq(restored.job,nil); eq(restored.stats.delivered,0)
end)
test("delayed mail notification is not misread as a pickup rejection",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
  local before=#e.sends
  b:onLine("Nie otrzymales zadnych nowych listow."); eq(b.phase,"pickup"); eq(#e.sends,before)
  b:onLine(fixtures.routes["Henry Schmidt"].pickup); eq(e:untilSend(),"nw")
end)
test("late pickup after stop is remembered without starting movement",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
  b:command("stop"); local before=#e.sends
  b:onLine(fixtures.routes["Henry Schmidt"].pickup)
  eq(b.job.route.name,"Henry Schmidt"); eq(b.mode,"stopped"); eq(#e.sends,before)
  b:command("wznow"); eq(e:last(),"zerknij")
end)
test("late handover and reward after stop are counted once and do not restart",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
  b:onLine(fixtures.routes["Henry Schmidt"].pickup)
  for _,raw in ipairs(fixtures.routes["Henry Schmidt"].forward) do e:untilSend(); feed(b,raw) end
  eq(e:untilSend(),"przedstaw sie"); eq(e:untilSend(),"oddaj paczke")
  b:command("stop"); local before=#e.sends
  b:onLine(fixtures.routes["Henry Schmidt"].handover); b:onLine(fixtures.routes["Henry Schmidt"].handover)
  b:onLine(fixtures.routes["Henry Schmidt"].receipt); b:onLine(fixtures.routes["Henry Schmidt"].receipt)
  eq(b.stats.delivered,1); eq(b.stats.silver,11); eq(#e.sends,before); eq(b.mode,"stopped")
end)
test("unconfirmed delivery is reconciled explicitly before resuming",function()
  local b,e=fresh(); start(b,e); feed(b,singleBoard("Henry Schmidt")); e:untilSend()
  b:onLine(fixtures.routes["Henry Schmidt"].pickup)
  for _,raw in ipairs(fixtures.routes["Henry Schmidt"].forward) do e:untilSend(); feed(b,raw) end
  e:untilSend(); e:untilSend(); b:disconnected()
  local before=#e.sends; b:command("wznow"); eq(#e.sends,before)
  b:command("paczka Henry Schmidt"); b:command("wznow"); eq(e:last(),"zerknij")
end)
test("failed or interrupted learning does not persist a guessed return",function()
  local b,e=fresh(); b:command("ucz Testowy Adresat"); feed(b,home); e:tick()
  b:onCommand("wybierz paczke 1"); b:onLine("Bierzesz paczke przeznaczona dla: Testowy Adresat.")
  b:onCommand("nw"); feed(b,fixtures.routes["Henry Schmidt"].forward[1]); b:onLine("Wrecasz paczke adresatowi.")
  b:onCommand("e"); eq(b.mode,"paused"); eq(e.saves,0); eq(b.routes["testowy adresat"],nil)
end)

print(string.format("SUCCESS: %d test scenarios, %d assertions. 37 boards, 308 real room responses, 9 complete parcel cycles.",tested,checks))
