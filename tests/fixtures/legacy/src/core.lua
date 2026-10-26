-- Chimera Kurier 1.0.0. Pure Lua core; all transport and timers are injected.
return function(data, api, saved)
  local K = {version = "1.0.0", mode = "stopped", phase = "idle", timers = {}, epoch = 0,
    ownSend = false, routes = {}, nodes = {}, titles = {}, rejected = {}, customRoutes = {},
    stats = {delivered = 0, gold = 0, silver = 0, copper = 0, started = nil},
    config = {delay = 0.35, timeout = 10, refresh = 30, maxKg = 3.2, strategy = "rate"}}
  local reverse = {n="s", s="n", e="w", w="e", ne="sw", nw="se", se="nw", sw="ne", u="d", d="u"}
  local directionNames = {polnoc="n", poludnie="s", wschod="e", zachod="w", gora="u", dol="d",
    ["polnocny-wschod"]="ne", ["polnocny-zachod"]="nw", ["poludniowy-wschod"]="se", ["poludniowy-zachod"]="sw"}
  local accents = {["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z",
    ["Ą"]="a",["Ć"]="c",["Ę"]="e",["Ł"]="l",["Ń"]="n",["Ó"]="o",["Ś"]="s",["Ź"]="z",["Ż"]="z"}

  local function norm(s)
    s = tostring(s or ""):gsub("\27%[[%d;]*[mK]", ""):gsub(" ", " ")
    for a,b in pairs(accents) do s = s:gsub(a, b) end
    return (s:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
  end
  K.norm = norm
  local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  local function same(a,b) return a and b and norm(a.title)==norm(b.title) and a.exits==b.exits end
  local function hasExit(room, cmd) return room and (","..room.exits..","):find(","..cmd..",", 1, true) ~= nil end
  local function money(text)
    text = norm(text)
    return {gold=tonumber(text:match("(%d+)%s+zlot%a*")) or 0,
      silver=tonumber(text:match("(%d+)%s+srebr%a*")) or 0,
      copper=tonumber(text:match("(%d+)%s+miedz%a*")) or 0}
  end
  K.parseMoney = money
  function K:parseOffer(text)
    local n,name,kind,kg,pay,count = norm(text):match("^(%d+)%.%s+(.-)%s+(%a+)%s+([%d%.,]+)%s+kg%s+(.-)%s*%[x(%d+)%]$")
    if not n or not ({miejscowa=true,miedzymiastowa=true,miedzykrainowa=true})[kind] then return nil end
    return {number=tonumber(n), name=name, kind=kind, kg=tonumber((kg:gsub(",", "."))),
      pay=money(pay), count=tonumber(count), raw=trim(text)}
  end
  function K:say(s) if api.say then api.say(s) end end
  function K:cancel(name)
    local id = self.timers[name]
    if id then api.cancel(id); self.timers[name] = nil end
  end
  function K:later(name, delay, fn)
    self:cancel(name)
    local epoch, id = self.epoch
    id = api.schedule(delay, function()
      if self.epoch ~= epoch or self.timers[name] ~= id then return end
      self.timers[name] = nil
      local ok,err = pcall(fn)
      if not ok then self:pause("Blad skryptu: "..tostring(err)) end
    end)
    self.timers[name] = id
  end
  function K:clearTimers()
    self.epoch = self.epoch + 1
    for _,id in pairs(self.timers) do api.cancel(id) end
    self.timers = {}
  end
  function K:pause(reason)
    if self.pending and self.pending.kind == "move" then self.node = nil end
    self:clearTimers()
    self.pending, self.walking, self.boardRows, self.exitCapture = nil,nil,nil,nil
    self.mode, self.phase, self.lastPause = "paused", "idle", reason or "Pauza."
    if self.learning then self.learning = nil end
    self:say(self.lastPause.."  /kurier wznow, aby kontynuowac.")
  end
  function K:stop(reason)
    self:pause(reason or "Zatrzymano.")
    self.mode = "stopped"
  end
  function K:sendCommand(cmd)
    self.ownSend = true
    local ok,err = pcall(api.send, cmd)
    self.ownSend = false
    if not ok then self:pause("Nie udalo sie wyslac komendy: "..tostring(err)); return false end
    return true
  end
  function K:watch(label)
    self:later("watchdog", self.config.timeout, function()
      self:pause("Brak potwierdzenia: "..label..". Sprawdz polaczenie i pozycje; nie powtarzam ruchu.")
    end)
  end
  function K:save()
    if api.save then
      local ok = pcall(api.save, {config=self.config,customRoutes=self.customRoutes})
      if not ok then self:say("Nie udalo sie zapisac ustawien/trasy w profilu.") end
    end
  end
  function K:addRoute(route)
    if type(route) ~= "table" or type(route.name)~="string" or type(route.commands)~="table" or type(route.rooms)~="table" then return false end
    if #route.commands<1 or #route.commands>300 or #route.rooms~=#route.commands+1 or not same(route.rooms[1],data.office) then return false end
    -- Validate the whole route before changing the graph.
    local key = "home"
    for i,cmd in ipairs(route.commands) do
      if not reverse[cmd] or not hasExit(route.rooms[i],cmd) or not hasExit(route.rooms[i+1],reverse[cmd]) then return false end
      if self.nodes[key] and self.nodes[key].edges[cmd] and self.nodes[key].edges[cmd]~=key.."/"..cmd then return false end
      key = key.."/"..cmd
      if self.nodes[key] and not same(self.nodes[key].room,route.rooms[i+1]) then return false end
    end
    key = "home"
    for i,cmd in ipairs(route.commands) do
      local child = key.."/"..cmd
      self.nodes[child] = self.nodes[child] or {room=route.rooms[i+1],edges={}}
      self.nodes[key].edges[cmd], self.nodes[child].edges[reverse[cmd]] = child, key
      self.titles[norm(route.rooms[i+1].title)] = true
      key = child
    end
    self.routes[norm(route.name)] = {name=route.name, commands=route.commands,rooms=route.rooms,target=key}
    return true
  end
  function K:localize(room)
    if self.node and self.nodes[self.node] and same(self.nodes[self.node].room,room) then return self.node end
    local matches = {}
    for id,n in pairs(self.nodes) do if same(n.room,room) then matches[#matches+1]=id end end
    if #matches==1 then return matches[1] end
    return nil,#matches
  end
  function K:path(from,to)
    local q,seen,previous = {from},{[from]=true},{}
    local head=1
    while q[head] do
      local id=q[head]; head=head+1
      if id==to then break end
      for cmd,nextId in pairs(self.nodes[id].edges) do
        if not seen[nextId] then
          seen[nextId]=true; previous[nextId]={id=id,cmd=cmd}; q[#q+1]=nextId
        end
      end
    end
    if not seen[to] then return nil end
    local reversed,id={},to
    while id~=from do
      local p=previous[id]; reversed[#reversed+1]={cmd=p.cmd,target=id}; id=p.id
    end
    local out={}
    for i=#reversed,1,-1 do out[#out+1]=reversed[i] end
    return out
  end
  function K:look(fn)
    self.pending={kind="look",callback=fn}; self.lastPlain=nil; self.exitCapture=nil
    self:watch("zerknij"); self:sendCommand("zerknij")
  end
  function K:onRoom(room)
    self.lastRoom=room
    local p=self.pending
    if not p then
      if self.mode=="running" and self.phase~="waiting" then
        self.node=nil; self:pause("Dodatkowy opis lokacji poza oczekiwanym ruchem. Sprawdz pozycje.")
      end
      return
    end
    if p.kind=="look" then
      self.pending=nil; self:cancel("watchdog")
      self:later("action",self.config.delay,function() p.callback(room) end)
    elseif p.kind=="move" then
      if not same(room,p.expected) then
        self.node=nil
        self:pause("Trasa sie nie zgadza. Oczekiwano: "..p.expected.title.." / "..p.expected.exits.."; otrzymano: "..room.title.." / "..room.exits)
        return
      end
      self.node=p.target; self.pending=nil; self:cancel("watchdog")
      self:later("action",self.config.delay,function() self:walkNext() end)
    elseif p.kind=="learnMove" then
      self.pending=nil; self:cancel("watchdog")
      local l=self.learning
      if not l or not hasExit(room,reverse[p.cmd]) then self:pause("Nie potwierdzono mozliwosci powrotu. Nagrywanie przerwane."); return end
      l.commands[#l.commands+1]=p.cmd; l.rooms[#l.rooms+1]=room
    elseif p.kind=="learnReturn" then
      self.pending=nil; self:cancel("watchdog")
      if not same(room,p.expected) then self:pause("Powrot nie potwierdzil nagranej trasy. Trasa nie zostala zapisana."); return end
      self.learning.returnIndex=self.learning.returnIndex-1
      if self.learning.returnIndex==0 then self:finishLearning() end
    end
  end
  function K:walk(target,callback,label)
    if not self.node then self:pause("Brak potwierdzonej pozycji."); return end
    local path=self:path(self.node,target)
    if not path then self:pause("Brak znanej drogi do celu."); return end
    self.phase=label or "walking"; self.walking={steps=path,index=1,callback=callback}
    self:walkNext()
  end
  function K:walkNext()
    if self.mode~="running" or not self.walking then return end
    local w=self.walking
    local step=w.steps[w.index]
    if not step then self.walking=nil; w.callback(); return end
    if not hasExit(self.lastRoom,step.cmd) then self:pause("Brak oczekiwanego wyjscia: "..step.cmd); return end
    w.index=w.index+1
    self.pending={kind="move",expected=self.nodes[step.target].room,target=step.target}
    self.lastPlain=nil; self.exitCapture=nil
    self:watch("ruch "..step.cmd); self:sendCommand(step.cmd)
  end
  function K:readBoard()
    if self.mode~="running" then return end
    if self.node~="home" or not same(self.lastRoom,data.office) then self:pause("Tablice czytam dopiero na rozpoznanej poczcie w Nuln."); return end
    self.phase="board"; self.boardRows={}; self.rowBuffer=nil; self.boardHeader=false; self.boardStale=false
    self:watch("pelna tablica paczek"); self:sendCommand("przeczytaj tablice")
  end
  function K:offerKey(o) return o.name.."|"..o.kg.."|"..o.pay.silver end
  function K:rank(rows)
    local eligible,unknown={},{}
    for _,o in ipairs(rows) do
      local route=self.routes[o.name]
      if o.kind=="miejscowa" and not route then unknown[#unknown+1]=o.name end
      if route and o.kind=="miejscowa" and o.kg and o.kg<=self.config.maxKg and o.count>0 and
          o.pay.gold==0 and o.pay.copper==0 and o.pay.silver>0 and not self.rejected[self:offerKey(o)] then
        o.route=route
        o.score=o.pay.silver/(2*#route.commands+4)
        eligible[#eligible+1]=o
      end
    end
    table.sort(eligible,function(a,b)
      if self.config.strategy=="light" and a.kg~=b.kg then return a.kg<b.kg end
      if self.config.strategy=="pay" and a.pay.silver~=b.pay.silver then return a.pay.silver>b.pay.silver end
      if a.score~=b.score then return a.score>b.score end
      if a.kg~=b.kg then return a.kg<b.kg end
      return a.number<b.number
    end)
    return eligible,unknown
  end
  function K:choose()
    if self.mode~="running" then return end
    if self.boardStale then self:readBoard(); return end
    local eligible,unknown=self:rank(self.boardRows or {})
    if not eligible[1] then
      local names=table.concat(unknown,", ")
      self.phase="waiting"
      self:say("Brak dostepnej znanej paczki do "..self.config.maxKg.." kg. Odswiezanie za "..self.config.refresh.." s."..
        (names~="" and " Nieznane trasy: "..names..". /kurier ucz <adresat>" or ""))
      self:later("refresh",self.config.refresh,function() self:readBoard() end)
      return
    end
    local o=eligible[1]
    self.selected=o; self.phase="pickup"
    self:say("Wybieram #"..o.number..": "..o.route.name..", "..o.kg.." kg, "..o.pay.silver.." srebrnych, "..
      (2*#o.route.commands).." krokow tam i z powrotem.")
    self.awaitingPickup=true
    self:watch("odbior paczki"); self:sendCommand("wybierz paczke "..o.number)
  end
  function K:accepted(name)
    self:cancel("watchdog")
    self.awaitingPickup=false
    local route=self.routes[norm(name)]
    self.job={name=name,route=route,actor=self.actor,delivered=false}
    if not route then
      self.phase="returnUnknown"
      self:say("Gra wydala paczke dla nieznanego adresata: "..name..". Zwracam ja w urzedzie nadania.")
      self:later("action",self.config.delay,function()
        self.awaitingReturn=true; self:watch("zwrot nieznanej paczki"); self:sendCommand("zwroc paczke")
      end)
      return
    end
    if self.selected and norm(name)~=self.selected.name then self:say("Zmiana numeracji ofert. Potwierdzony adresat: "..route.name..".") end
    self:later("action",self.config.delay,function()
      self:walk(route.target,function() self:deliver() end,"outbound")
    end)
  end
  function K:deliver()
    self.phase="introduce"
    self:sendCommand("przedstaw sie")
    self:later("action",math.max(self.config.delay,0.5),function()
      self.phase="delivery"; self.awaitingDelivery=true; self:watch("doreczenie paczki"); self:sendCommand("oddaj paczke")
    end)
  end
  function K:goHome()
    self:walk("home",function()
      self.job=nil; self.selected=nil
      if self.stopAt and self.stats.delivered>=self.stopAt then
        self:stop("Wykonano limit doreczen; postac wrocila na poczte."); self:status()
      else self:readBoard() end
    end,"inbound")
  end
  function K:begin(resume,limit)
    if self.mode=="running" or self.mode=="learning" then self:say("Automat juz pracuje. /kurier stop"); return end
    if self.awaitingPickup or self.awaitingDelivery or self.awaitingReturn then
      self:say("Wynik ostatniego odbioru/oddania/zwrotu nie zostal potwierdzony. Sprawdz paczke: /kurier paczka <adresat>, jesli ja masz; /kurier reset po jej rozliczeniu."); return
    end
    if not resume and self.job then self:say("Pamietam rozpoczęte doreczenie. Uzyj /kurier wznow albo /kurier reset po recznym rozliczeniu paczki."); return end
    if self.job and self.job.actor and self.actor and self.job.actor~=self.actor then self:say("Zmieniono postac. Uzyj /kurier reset przed nowym uruchomieniem."); return end
    self:clearTimers(); self.pending=nil; self.mode="running"; self.phase="locating"
    if not resume then
      self.rejected={}
      if limit then self.stopAt=self.stats.delivered+limit else self.stopAt=nil end
    end
    self.stats.started=self.stats.started or api.now()
    self:look(function(room)
      local id,count=self:localize(room)
      if not id then
        self:pause((count and count>1) and "Opis pasuje do kilku miejsc. Zacznij na poczcie Nuln lub w lokacji o jednoznacznej nazwie." or
          "Ta lokacja nie nalezy do znanych tras. Przejdz na poczte w Nuln i wpisz /kurier start.")
        return
      end
      self.node=id
      if self.job and not self.job.delivered then
        if not self.job.route then self:pause("Nieznany adresat zapamietanej paczki. Zwroc ja recznie albo naucz trase."); return end
        self:walk(self.job.route.target,function() self:deliver() end,"outbound")
      else self:goHome() end
    end)
  end
  function K:learn(name)
    if not name or #norm(name)<3 then self:say("Uzycie: /kurier ucz Imie Nazwisko (zacznij na poczcie w Nuln, przed odebraniem paczki)."); return end
    if self.job then self:say("Najpierw dokoncz lub recznie rozlicz zapamietana paczke."); return end
    self:stop("Przygotowuje nauke trasy."); self.mode="learning"; self.phase="locating"; self.node=nil
    self:look(function(room)
      if not same(room,data.office) then self:pause("Nauke rozpocznij na poczcie w Nuln."); return end
      self.node="home"; self.phase="recording"
      self.learning={name=name,commands={},rooms={room},picked=false}
      self:say("Nagrywanie: wybierz paczke dla "..name..", idz recznie (n/s/e/w/ne/nw/se/sw/u/d), potem oddaj paczke. Sukces zapisze trase.")
    end)
  end
  function K:finishLearning()
    local l=self.learning
    if self.pending or not l or not l.picked or not l.delivered or l.returnIndex~=0 or #l.commands<1 then self:pause("Niepelny zapis ruchow i powrotu; trasa nie zostala dodana."); return end
    local route={name=l.name,commands=l.commands,rooms=l.rooms}
    if not self:addRoute(route) then self:pause("Trasa nie ma potwierdzonego powrotu lub jest sprzeczna z zapisana mapa."); return end
    self.customRoutes[norm(l.name)]=route; self.learning=nil; self.node="home"; self:save()
    self:stop("Zapamietano doreczenie i powrot dla "..l.name.." ("..#l.commands.." krokow w jedna strone). /kurier start")
  end
  function K:onCommand(cmd)
    if self.ownSend then return end
    cmd=norm(cmd)
    if cmd=="" then return end
    if self.mode=="learning" and self.learning then
      if reverse[cmd] then
        if self.pending or not hasExit(self.lastRoom,cmd) then self:pause("Niepotwierdzony lub niedostepny krok. Nagrywanie przerwane."); self.node=nil; return end
        local l=self.learning
        if l.delivered then
          if cmd~=reverse[l.commands[l.returnIndex]] then self:pause("Wroc dokladnie ta sama trasa w odwrotnej kolejnosci. Nauka przerwana."); self.node=nil; return end
          self.pending={kind="learnReturn",expected=l.rooms[l.returnIndex]}
        else self.pending={kind="learnMove",cmd=cmd} end
        self.lastPlain=nil; self.exitCapture=nil
        self:watch("nagrywany krok "..cmd)
      elseif not cmd:match("^wybierz paczke %d+$") and cmd~="oddaj paczke" and cmd~="przedstaw sie" then
        self:pause("Nauka obsluguje tylko kierunki, odebranie i oddanie paczki oraz przedstawianie sie."); self.node=nil
      end
    elseif self.mode=="running" or self.mode=="learning" then
      self:pause("Reczna komenda lub inny skrypt przejal sterowanie."); self.node=nil
    elseif reverse[cmd] or cmd:find("wejdz",1,true) or cmd:find("wyjdz",1,true) then self.node=nil end
  end
  function K:disconnected()
    self:pause("Polaczenie z gra zostalo przerwane. Po zalogowaniu uzyj /kurier wznow."); self.node=nil
  end
  function K:rememberLateConfirmation(s,text)
    local picked=s:match("^bierzesz paczke przeznaczona dla: (.+)%.$")
    if picked and self.awaitingPickup then
      self.awaitingPickup=false
      local route=self.routes[picked]
      self.job={name=route and route.name or picked,route=route,actor=self.actor,delivered=false}
      self:say("Gra potwierdzila odbior paczki; automat pozostaje wstrzymany.")
    elseif self.awaitingDelivery and self.job and s:match("^wrecasz paczke adresatowi%.") then
      self.awaitingDelivery=false; self.awaitingReward=true; self.job.delivered=true
      self.stats.delivered=self.stats.delivered+1
      self:say("Gra potwierdzila doreczenie po zatrzymaniu automatu.")
    elseif self.awaitingReward and s:match("^adresat wrecza ci .- za trud%.") then
      self.awaitingReward=false
      local pay=money(s)
      self.stats.gold=self.stats.gold+pay.gold; self.stats.silver=self.stats.silver+pay.silver; self.stats.copper=self.stats.copper+pay.copper
    elseif self.awaitingReturn and (s:match("^zwracasz paczke") or s:match("^oddajesz paczke pracownikowi") or s:match("^zwrociles paczke") or s:match("^zwrocilas paczke")) then
      self.awaitingReturn=false; self.job=nil
    end
  end
  function K:onLine(raw)
    local text=trim(tostring(raw or "")); local s=norm(text)
    if s=="" then return end
    local actor=s:match("^witaj, (.-)[%.!] podaj haslo")
    if actor then
      if not self.actor or self.actor~=actor then
        self.job=nil; self.stats={delivered=0,gold=0,silver=0,copper=0,started=nil}; self.node=nil
        self.awaitingPickup,self.awaitingDelivery,self.awaitingReturn,self.awaitingReward=false,false,false,false
      end
      self.actor=actor
    end
    if self.mode~="running" and self.mode~="learning" then self:rememberLateConfirmation(s,text); return end
    if self.awaitingReward and self.phase~="reward" and s:match("^adresat wrecza ci .- za trud%.") then
      self:rememberLateConfirmation(s,text); return
    end
    if s:find("nadchodzi czas apokalipsy",1,true) or s:find("glos jezdzca apokalipsy",1,true) or
        s:match("^podaj swoje imie") or s:match("^witaj, .-podaj haslo") or
        s:match("^jestes w trakcie walki") or s:find("nie mozesz zakonczyc gry w takim pospiechu",1,true) or
        s:find("atakuje cie",1,true) or s:find("rzuca sie na ciebie",1,true) or s:match("^zostajesz zaatakowan") then
      self:pause("Gra wymaga uwagi: walka, apokalipsa lub ponowne logowanie."); return
    end
    if self.phase=="board" and s:find("przesylki dostepne dla kuriera",1,true) then
      self.boardHeader=true; self.rowBuffer=nil; return
    end
    if (self.phase=="board" or self.phase=="planning") and s:find("bierze paczke z tablicy",1,true) then self.boardStale=true end
    if self.phase=="board" and self.boardHeader then
      if s:match("^%d+%.") then self.rowBuffer=text
      elseif self.rowBuffer then self.rowBuffer=self.rowBuffer.." "..text end
      if self.rowBuffer and norm(self.rowBuffer):match("%[x%d+%]$") then
        local row=self:parseOffer(self.rowBuffer)
        if row then self.boardRows[#self.boardRows+1]=row end
        self.rowBuffer=nil
      end
      if s:find("naraz mozna niesc tylko jedna przesylke",1,true) then
        self:cancel("watchdog"); self.phase="planning"; self.boardHeader=false
        self:later("action",self.config.delay,function() self:choose() end)
      end
      return
    end
    local picked=text:match("^[Bb]ierzesz paczke przeznaczona dla: (.+)%.$")
    if not picked then picked=s:match("^bierzesz paczke przeznaczona dla: (.+)%.$") end
    if picked then
      if self.mode=="learning" and self.learning then
        if norm(picked)~=norm(self.learning.name) or #self.learning.commands>0 then self:pause("Odebrano paczke innego adresata lub poza punktem startu; nauka przerwana.")
        else self.learning.picked=true end
      elseif self.phase=="pickup" then self:accepted(picked) end
      return
    end
    if self.phase=="returnUnknown" and (s:match("^zwracasz paczke") or s:match("^oddajesz paczke pracownikowi") or s:match("^zwrociles paczke") or s:match("^zwrocilas paczke")) then
      self:cancel("watchdog"); self.job=nil; self.awaitingReturn=false
      self:later("action",self.config.delay,function() self:readBoard() end); return
    end
    if s:match("^wrecasz paczke adresatowi%.") then
      if self.mode=="learning" and self.learning then
        local l=self.learning
        if self.pending or not l.picked or #l.commands<1 then self:pause("Brak pelnej trasy do udanego doreczenia."); return end
        l.delivered=true; l.returnIndex=#l.commands
        self:say("Doreczenie potwierdzone. Wroc recznie dokladnie ta sama droga w odwrotnej kolejnosci; powrot na poczte zapisze trase.")
      elseif self.phase=="delivery" and self.job and not self.job.delivered then
        self.awaitingDelivery=false; self.awaitingReward=true
        self.job.delivered=true; self.stats.delivered=self.stats.delivered+1
        self.phase="reward"; self:watch("kwota nagrody po doreczeniu")
      end
      return
    end
    if self.phase=="reward" and s:match("^adresat wrecza ci .- za trud%.") then
      self:cancel("watchdog")
      self.awaitingReward=false
      local pay=money(s)
      self.stats.gold=self.stats.gold+pay.gold; self.stats.silver=self.stats.silver+pay.silver; self.stats.copper=self.stats.copper+pay.copper
      self.phase="rewardReceived"
      self:say("Doreczono: "..self.job.name..". Lacznie: "..self.stats.delivered.." paczek; "..
        self.stats.gold.." zlotych, "..self.stats.silver.." srebrnych, "..self.stats.copper.." miedzianych.")
      self:later("action",self.config.delay,function() self:goHome() end); return
    end
    local packageContext=s:find("pacz",1,true) or s:find("przesyl",1,true) or s:find("zlecen",1,true) or s:find("numer",1,true)
    if self.phase=="pickup" and (((s:match("^nie ") or s:match("^to zlecenie ") or s:match("^ta paczka ") or s:match("^masz juz ") or s:match("^niesiesz juz ")) and packageContext) or s:match("^nie masz dosc sily") or s:match("^jestes zbyt obciazon")) then
      self.awaitingPickup=false
      if s:find("pacz",1,true) and (s:find("juz",1,true) or s:find("niesiesz",1,true)) and not s:find("nie ma juz",1,true) then
        self:pause("Gra informuje o niesionej paczce. Ustal adresata i uzyj /kurier paczka <adresat>.")
      else
        self:cancel("watchdog")
        if self.selected then self.rejected[self:offerKey(self.selected)]=true end
        self.phase="rejected"
        self:later("action",self.config.delay,function() self:readBoard() end)
      end
      return
    end
    if self.phase=="delivery" and (s:match("^nie masz ") or s:match("^nie niesiesz ") or s:match("^nie ma tu ") or s:match("^nie widzisz ")) then
      self.awaitingDelivery=false
      self:pause("Gra nie potwierdzila doreczenia. Sprawdz paczke i adresata."); return
    end
    if self.pending and self.pending.kind=="move" and (s:match("^nie widzisz zadnego wyjscia") or s:match("^nie mozesz ") or s:match("^drzwi sa zamkniete") or s:match("^jestes zbyt ") or s:match("^nie masz dosc ")) then
      self.node=nil; self:pause("Ruch zablokowany przez gre. Sprawdz postac i droge."); return
    end
    -- A room consists of its short title and the complete (possibly wrapped) exit list.
    if s:match("^sa tutaj .-widocz.-wyjsc") or s:match("^jest tutaj .-widocz.-wyjsc") then
      local exits=text:match(":%s*(.*)$")
      if exits then self.exitCapture={title=self.lastPlain or "",text=exits} end
    elseif self.exitCapture then
      self.exitCapture.text=self.exitCapture.text.." "..text
    else
      -- Full descriptions are deliberately rejected: `zerknij` must provide the short title.
      if text:sub(-1)=="." and text:sub(1,1)~="[" and text:sub(1,1)~="(" then self.lastPlain=text end
    end
    local c=self.exitCapture
    if c and c.text:sub(-1)=="." then
      self.exitCapture=nil
      local names=norm(c.text):gsub("%-%s+","-"):gsub("%.$", ""):gsub(" i ", ", ")
      local exits={}
      for name in names:gmatch("[^,]+") do exits[#exits+1]=directionNames[trim(name)] or trim(name) end
      table.sort(exits)
      self:onRoom({title=c.title,exits=table.concat(exits,",")})
    end
  end
  function K:status()
    local elapsed=self.stats.started and math.max(1,api.now()-self.stats.started) or 0
    self:say("Kurier "..self.version.." | "..self.mode.." / "..self.phase.." | doreczono: "..self.stats.delivered..
      " | zarobek: "..self.stats.gold.." zl, "..self.stats.silver.." sr, "..self.stats.copper.." md"..
      (elapsed>0 and string.format(" | %.1f sr/min (czas od pierwszego startu)",self.stats.silver*60/elapsed) or "")..
      " | limit wagi: "..self.config.maxKg.." kg | strategia: "..self.config.strategy..
      (self.job and " | paczka: "..self.job.name..(self.job.delivered and " (oddana)" or " (w drodze)") or ""))
  end
  function K:help()
    self:say("/kurier start [liczba] | stop | wznow | status | trasy | limit <kg> | tempo <sekundy> | odswiezanie <sekundy> | tryb zarobek/zaplata/lekkie | paczka <adresat> | ucz <adresat> | reset")
    self:say("Pierwszy start: bez paczki, na poczcie w Nuln. Zwykle opisy lokacji musza zawierac nazwe i wyjscia, jak w logach. Reczna komenda wstrzymuje bota.")
  end
  function K:command(input)
    local verb,arg=trim(input or ""):match("^(%S+)%s*(.-)$")
    verb=norm(verb or "pomoc")
    if verb=="start" then
      local n=arg~="" and tonumber(arg) or nil
      if arg~="" and (not n or n<1 or n~=math.floor(n)) then self:say("Limit musi byc dodatnia liczba calkowita."); return end
      self:begin(false,n)
    elseif verb=="stop" or verb=="pauza" then self:stop("Zatrzymano recznie.")
    elseif verb=="wznow" or verb=="resume" then self:begin(true)
    elseif verb=="status" then self:status()
    elseif verb=="trasy" then
      local names={}; for _,r in pairs(self.routes) do names[#names+1]=r.name.." ("..#r.commands.." krokow)" end
      table.sort(names); self:say("Znane trasy z poczty Nuln: "..table.concat(names, "; "))
    elseif verb=="ucz" then self:learn(arg)
    elseif verb=="paczka" then
      if self.mode=="running" or self.mode=="learning" then self:say("Najpierw /kurier stop."); return end
      local r=self.routes[norm(arg)]
      if not r then self:say("Nieznany adresat. /kurier trasy"); return end
      self.awaitingPickup,self.awaitingDelivery,self.awaitingReturn,self.awaitingReward=false,false,false,false
      self.job={name=r.name,route=r,actor=self.actor,delivered=false}; self:say("Ustawiono niesiona paczke dla "..r.name..". /kurier wznow")
    elseif verb=="reset" then
      self:stop("Wyczyszczono pamiec sesji; paczka w grze wymaga osobnego rozliczenia.")
      self.job=nil; self.node=nil; self.rejected={}; self.stopAt=nil
      self.awaitingPickup,self.awaitingDelivery,self.awaitingReturn,self.awaitingReward=false,false,false,false
      self.stats={delivered=0,gold=0,silver=0,copper=0,started=nil}
    elseif verb=="limit" or verb=="tempo" or verb=="odswiezanie" then
      local n=tonumber(((arg or ""):gsub(",",".")))
      local key,min,max="maxKg",0.1,100
      if verb=="tempo" then key,min,max="delay",0.15,10 elseif verb=="odswiezanie" then key,min,max="refresh",5,600 end
      if not n or n<min or n>max then self:say("Podaj liczbe od "..min.." do "..max.."."); return end
      self.config[key]=n; self.rejected={}; self:save(); self:say("Ustawiono "..key.." = "..n)
    elseif verb=="tryb" then
      local strategy=({zarobek="rate",zaplata="pay",lekkie="light"})[norm(arg)]
      if not strategy then self:say("Tryby: zarobek, zaplata, lekkie."); return end
      self.config.strategy=strategy; self:save(); self:say("Ustawiono tryb "..norm(arg))
    else self:help() end
  end
  -- Only configuration and successfully recorded routes survive profile reloads.
  K.nodes.home={room=data.office,edges={}}; K.titles[norm(data.office.title)]=true
  for _,r in pairs(data.routes) do assert(K:addRoute(r),"Invalid bundled route: "..tostring(r.name)) end
  if type(saved)=="table" then
    if type(saved.config)=="table" then
      local c=saved.config
      for _,key in ipairs({"delay","timeout","refresh","maxKg"}) do
        local n=tonumber(c[key]); if n and n>0 and n<1000 then K.config[key]=n end
      end
      K.config.delay=math.max(0.15,K.config.delay); K.config.refresh=math.max(5,K.config.refresh)
      if ({rate=true,pay=true,light=true})[c.strategy] then K.config.strategy=c.strategy end
    end
    if type(saved.customRoutes)=="table" then
      for key,r in pairs(saved.customRoutes) do if K:addRoute(r) then K.customRoutes[key]=r end end
    end
  end
  return K
end
