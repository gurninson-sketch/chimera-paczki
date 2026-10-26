-- Chimera Paczki 1.5.14. Transport, navigation and timers are injected.
return function(data, api, saved)
  local K = {version = "1.5.14", mode = "stopped", phase = "idle", timers = {}, epoch = 0, sessionNonce=0,
    ownSend = false, routes = {}, nodes = {}, titles = {}, rejected = {}, customRoutes = {},
    stats = {delivered = 0, gold = 0, silver = 0, copper = 0, started = nil},
    config = {delay = 0.35, tempoSource = "walker", timeout = 10, refresh = 30, maxKg = 3.2, strategy = "local_first", roam = true, autoLearn=true, autoBackpack=true}}
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
  local function value(pay) return pay.gold*240+pay.silver*12+pay.copper end
  K.moneyValue = value
  local function handover(s) return s:match("^wrecasz paczke adresatowi%.") or s:match("^zostawiasz przesylke w okienku urzedu pocztowego%.") end
  local function reward(s) return s:match("^adresat wrecza ci .- za trud%.") or s:match("^urzednik wyplaca ci .- za trud%.") end
  function K:parseOffer(text)
    local n,name,kind,kg,pay,count = norm(text):match("^(%d+)%.%s+(.-)%s+(%a+)%s+([%d%.,]+)%s+kg%s+(.-)%s*%[x(%d+)%]$")
    if not n or not ({miejscowa=true,miedzymiastowa=true,miedzykrainowa=true,miedzydomenowa=true})[kind] then return nil end
    return {number=tonumber(n), name=name, kind=kind, kg=tonumber((kg:gsub(",", "."))),
      pay=money(pay), count=tonumber(count), raw=trim(text)}
  end
  function K:say(s) if api.say then api.say(s) end end
  function K:delay()
    local seconds=api.stepDelay and api.stepDelay(self.config.delay,self.config.tempoSource) or self.config.delay
    return math.max(0.15,math.min(60,tonumber(seconds) or 0.5))
  end
  function K:cancel(name)
    local id = self.timers[name]
    if id then api.cancel(id); self.timers[name] = nil end
  end
  function K:later(name, delay, fn)
    self:cancel(name)
    local epoch, id = self.epoch
    local minimumDelayUnit=name=="action" and self.phase=="introduce" and delay==math.max(self:delay(),0.5) and 1 or 0
    id = api.schedule(delay, function()
      if self.epoch ~= epoch or self.timers[name] ~= id then return end
      self.timers[name] = nil
      if api.timingDelay and (name=="action" or name=="restResume") then pcall(api.timingDelay,delay,minimumDelayUnit) end
      local ok,err = pcall(fn)
      if not ok then self:pause("Blad skryptu: "..tostring(err)) end
    end)
    self.timers[name] = id
  end
  function K:clearTimers()
    self.epoch = self.epoch + 1
    self.planningToken=nil
    local cancelPlanning=self.cancelPlanning;self.cancelPlanning=nil
    if cancelPlanning then cancelPlanning() end
    local cancelNavigation=self.cancelNavigation
    self.cancelNavigation=nil; self.externalNavigation=nil
    if cancelNavigation then cancelNavigation() end
    local cancelInventory=self.cancelInventory
    self.cancelInventory=nil
    if cancelInventory then cancelInventory() end
    for _,id in pairs(self.timers) do api.cancel(id) end
    self.timers = {}
  end
  function K:checkpoint()
    if not api.saveRun or not self.actor or self.suppressCheckpoint or self.runCleared then return end
    local job
    if self.job then
      local coinsPending=self.job.coinsPending==true
      if coinsPending and self.job.coinReceipt and api.coinReceipt and api.coinReceipt()>self.job.coinReceipt then coinsPending=false end
      job={name=self.job.name,recipientConfirmed=self.job.recipientConfirmed==true,delivered=self.job.delivered==true,
        coinsPending=coinsPending,source=self.job.source}
    end
    local state={source=self.source,job=job,relocation=self.relocation and {to=self.relocation.to,manual=self.relocation.manual==true},
      selectedName=self.selected and self.selected.name,pendingManualSource=self.pendingManualSource,
      flags={awaitingPickup=self.awaitingPickup==true,awaitingDelivery=self.awaitingDelivery==true,
        awaitingReturn=self.awaitingReturn==true,awaitingReward=self.awaitingReward==true,
        manualPickup=self.manualPickup==true,manualDelivery=self.manualDelivery==true},
      stats=self.stats,stopAt=self.stopAt,inventory=api.inventoryState and api.inventoryState() or {state="unknown"}}
    local ok,saved,why=pcall(api.saveRun,self.actor,state)
    if not ok or saved==false then self:say("Nie zapisano biezacego kursu: "..tostring(ok and why or saved)..".") end
  end
  function K:restoreRun()
    if not api.loadRun or not self.actor then return false end
    local state=api.loadRun(self.actor)
    if not state then return false end
    self.runCleared=nil
    self.suppressCheckpoint=true
    self.source=state.source or (state.job and state.job.source);self.staticSource=self.source and self.source.staticNuln==true or false;self.node=nil;self.lastRoom=nil
    self.job=state.job;self.relocation=state.relocation
    if self.job then self.job.actor=self.actor;self.job.source=self.job.source or self.source end
    self.stats=state.stats or {delivered=0,gold=0,silver=0,copper=0,started=nil}
    self.stopAt=state.stopAt
    for _,key in ipairs({"awaitingPickup","awaitingDelivery","awaitingReturn","awaitingReward","manualPickup","manualDelivery"}) do
      self[key]=state.flags and state.flags[key]==true or false
    end
    self.selected=state.selectedName and {name=state.selectedName} or nil;self.pendingManualSource=state.pendingManualSource
    self.savedInventoryUncertain=state.inventory and state.inventory.coinsUncertain==true or false
    if api.restoreInventory then api.restoreInventory(state.inventory or {state="unknown"}) end
    self.suppressCheckpoint=nil;self.needsResumeValidation=true
    if self.job or self.relocation or self.awaitingPickup or self.awaitingDelivery or self.awaitingReward then
      self.mode="paused";self.phase="idle"
      self.lastPause="Przywrocono zapisany kurs"..(self.job and ": "..self.job.name or "")..". Po polaczeniu uzyj /paczki wznow."
    end
    return true
  end
  function K:hydrateRun()
    if not api.restorePlace then return true end
    local function hydrate(place)
      if not place then return nil end
      return api.restorePlace(place)
    end
    local source=self.source and hydrate(self.source)
    if self.source and not source then return false,"zapisany urzad nadania nie jest dostepny na aktualnej mapie" end
    local destination=self.relocation and hydrate(self.relocation.to)
    if self.relocation and not destination then return false,"zapisany cel zmiany poczty nie jest dostepny na aktualnej mapie" end
    self.source=source or self.source
    if self.job then self.job.source=self.source end
    if self.relocation then self.relocation.to=destination end
    if self.pendingManualSource then self.pendingManualSource=hydrate(self.pendingManualSource) or self.pendingManualSource end
    if self.source then self.staticSource=self.source.staticNuln==true end
    return true
  end
  function K:resolveRoute(name)
    local why
    if api.resolveRoute and self.source then
      local route,reason=api.resolveRoute(name,self.source)
      if route then return route end
      why=reason
    end
    if self.staticSource~=false and self.routes[norm(name)] then return self.routes[norm(name)] end
    return nil,why or "nieznany adresat lub brak zapisanej trasy"
  end
  function K:captureSource()
    self.source=api.source and api.source() or nil
    if self.source and self.source.staticNuln~=nil then self.staticSource=self.source.staticNuln
    else self.staticSource=not self.source or norm(self.source.name):gsub("%.$","")=="poczta" end
  end
  function K:adoptOffice(office)
    if api.clearTravelIntent then api.clearTravelIntent() end
    self.source=office;self.staticSource=office.staticNuln==true
    self.node=self.staticSource and "home" or nil
    self.lastRoom=self.staticSource and data.office or nil
    self.relocation=nil;self.selected=nil;self.rejected={}
    self:checkpoint()
  end
  function K:navigate(route,callback,returning)
    self.phase=returning and "inbound" or "outbound"
    if not api.navigate then self:pause("Brak nawigacji /npc."); return end
    self.node=nil; self.pending=nil; self.lastPlain=nil; self.exitCapture=nil
    self.externalNavigation=true
    local epoch,finished=self.epoch,false
    local cancel=api.navigate(route,returning,function(ok,why)
      if finished or epoch~=self.epoch or self.mode~="running" then return end
      finished=true; self.cancelNavigation=nil
      self.lastPlain=nil; self.exitCapture=nil
      if not ok then
        if norm(why):find("zmeczenie; krok nie zostal wykonany",1,true) then self:rest("Gra odmowila kroku ze zmeczenia.")
        else self:pause("Nawigacja: "..tostring(why or "brak potwierdzenia celu")) end
        return
      end
      self:later("action",self:delay(),function()
        self.externalNavigation=nil
        if self.phase=="waitingNpc" or self.phase=="searchingCity" then self.lastPause=nil end
        callback()
      end)
    end)
    if not finished and epoch==self.epoch then self.cancelNavigation=cancel end
  end
  function K:relocate(office,manual)
    if self.mode~="running" then return end
    if self.job or self.awaitingPickup or self.awaitingDelivery or self.awaitingReturn or self.awaitingReward then
      self:pause("Najpierw rozlicz paczke; nie zmieniam urzedu nadania."); return
    end
    if not self.source or not office or not office.map or not office.id then
      self:pause("Brak rozpoznanej poczty lub celu przejscia."); return
    end
    self:cancel("refresh"); self:cancel("watchdog")
    self.relocation={from=self.source,to=office,manual=manual==true}
    self:checkpoint()
    if self:checkFatigue() then return end
    self:say((manual and "Przechodze do wybranej poczty: " or "Brak odpowiednich paczek. Przechodze do najblizszej dostepnej poczty: ")..office.name.." (koszt drogi: "..tostring(office.cost or "?")..").")
    self:navigate(office,function()
      local here=api.position and api.position()
      if not here or here.id~=office.id or here.map~=office.map then
        self:pause("Nie potwierdzono polozenia nowej poczty."); return
      end
      self:adoptOffice(office)
      self:say("Nowy urzad nadania: "..office.name..". Sprawdzam tablice.")
      self:readBoard()
    end,true)
    if self.mode=="running" then self.phase="relocating" end
  end
  function K:selectOffice(query)
    local held=api.inventoryState and api.inventoryState()
    if (self.job and (not self.job.delivered or self.job.coinsPending)) or
      (held and held.coinsUncertain) or self.savedInventoryUncertain or
      self.awaitingPickup or self.awaitingDelivery or self.awaitingReturn or self.awaitingReward then
      self.lastPause="Najpierw rozlicz niesiona paczke; nie zmieniam urzedu nadania."
      self:say(self.lastPause);return
    end
    if self.needsResumeValidation and api.sessionReady then
      local ready,why=api.sessionReady(self.actor)
      if not ready then self.lastPause=why or "Czekam na dane postaci i pozycji GMCP.";self:say(self.lastPause);return end
    end
    local office,why
    if norm(query)=="" or norm(query)=="tutaj" then
      office=api.currentOffice and api.currentOffice()
      why="Nie stoisz w rozpoznanym urzedzie pocztowym."
    elseif api.resolveOffice then office,why=api.resolveOffice(query)
    end
    if not office then self.lastPause=why or "Nie znaleziono wybranej poczty lub drogi.";self:say(self.lastPause);return end
    self.needsResumeValidation=false
    self:clearTimers();self.pending=nil;self.walking=nil;self.job=nil;self.selected=nil
    self.mode="running";self.phase="locating";self.lastPause=nil;self.stopAt=nil
    self.runCleared=nil
    self.stats.started=self.stats.started or api.now()
    local current=api.currentOffice and api.currentOffice()
    if current and current.id==office.id and current.map==office.map then
      self:adoptOffice(current);self:say("Pracuje w wybranej poczcie: "..current.name..".");self:readBoard()
    else
      self.source=current or (api.position and api.position()) or self.source
      self:relocate(office,true)
    end
  end
  function K:outbound()
    local route=self.job and self.job.route
    if not route then self:pause("Brak rozpoznanego adresata paczki."); return end
    self:inventory("stowParcel",function()
      if route.native then self:navigate(route,function() self:deliver() end)
      else self:walk(route.target,function() self:deliver() end,"outbound") end
    end)
  end
  function K:inventory(action,callback)
    if not api.inventory then callback();return end
    self.phase="inventory"
    local epoch,finished,job=self.epoch,false,self.job
    local cancel=api.inventory(action,function(result)
      if action=="stowCoins" and result and result.moved and job and self.job==job then job.coinsPending=false end
      if finished or epoch~=self.epoch or self.mode~="running" then return end
      finished=true;self.cancelInventory=nil
      if not result or not result.ok then self:pause("Pojemnik: "..tostring(result and result.reason or "brak potwierdzenia"));return end
      callback()
    end)
    if not finished and epoch==self.epoch then self.cancelInventory=cancel end
  end
  function K:pause(reason,quiet)
    if api.cancelTiming then pcall(api.cancelTiming,reason or "pauza") end
    if self.pending and self.pending.kind == "move" then self.node = nil end
    self:clearTimers()
    self.pending, self.walking, self.boardRows, self.exitCapture = nil,nil,nil,nil
    self.mode, self.phase, self.lastPause = "paused", "idle", reason or "Pauza."
    self.restState=nil
    if self.learning then self.learning = nil end
    self:checkpoint()
    if not quiet then self:say(self.lastPause.."  /kurier wznow, aby kontynuowac.") end
  end
  function K:restLimits()
    local limits=api.restLimits and api.restLimits() or {}
    local stop=math.max(1,math.min(100,tonumber(limits.stop) or 80))
    return stop,math.max(0,math.min(stop-1,tonumber(limits.start) or 20)),tonumber(limits.hp) or 30
  end
  function K:checkFatigue()
    if api.combatTransit and api.combatTransit() then return false end
    local vitals=api.vitals and api.vitals()
    if type(vitals)~="table" then return false end
    local stop,_,hp=self:restLimits()
    if tonumber(vitals.hp) and tonumber(vitals.hp)<hp then
      if api.lowHealth then api.lowHealth() else self:pause("Niskie HP; kurier zatrzymany.") end
      return true
    end
    if tonumber(vitals.fatigue) and tonumber(vitals.fatigue)>=stop then self:rest("Osiagnieto prog zmeczenia.");return true end
    return false
  end
  function K:rest(reason)
    if api.combatTransit and api.combatTransit() then return end
    if self.mode=="resting" then return end
    if self.mode~="running" then
      if self.mode=="learning" then self:pause(reason or "Zmeczenie; nauka przerwana.") end
      return
    end
    local staticMove=self.pending and self.pending.kind=="move" and self.pending or nil
    if staticMove then self.node=nil end
    self:clearTimers()
    self.pending,self.walking,self.boardRows,self.exitCapture=nil,nil,nil,nil
    self.mode,self.phase="resting","resting"
    self.restState={ready=false,staticMove=staticMove}
    if staticMove then self:later("restAck",15,function()
      if self.mode=="resting" and self.restState and self.restState.staticMove then self:pause("Brak potwierdzenia ostatniego kroku podczas odpoczynku.") end
    end) end
    local _,start=self:restLimits()
    self.lastPause=(reason or "Zmeczenie.").." Odpoczywam; wznowie automatycznie przy zmeczeniu <= "..start.."%."
    self:say(self.lastPause)
    local function poll()
      if self.mode~="resting" then return end
      self:sendCommand("stan")
      if self.mode=="resting" then self:later("restPoll",10,poll) end
    end
    self:later("restPoll",10,poll)
  end
  function K:onVitals(vitals)
    if type(vitals)~="table" or (self.mode~="running" and self.mode~="resting") then return end
    if api.combatTransit and api.combatTransit() then return end
    local stop,start,hp=self:restLimits()
    if tonumber(vitals.hp) and tonumber(vitals.hp)<hp then
      if api.lowHealth then api.lowHealth() else self:pause("Niskie HP; kurier zatrzymany.") end
      return
    end
    local fatigue=tonumber(vitals.fatigue)
    if not fatigue then return end
    if self.mode=="running" then
      if fatigue>=stop then self:rest("Osiagnieto prog zmeczenia.") end
      return
    end
    self.restState.ready=fatigue<=start
    if not self.restState.ready then self:cancel("restResume");return end
    self:tryResumeRest()
  end
  function K:tryResumeRest()
    if self.mode~="resting" or not self.restState or not self.restState.ready or self.restState.staticMove or
      (api.travelPending and api.travelPending()) then return end
    local held=api.inventoryState and api.inventoryState()
    if held and held.coinsUncertain then return end
    self:later("restResume",self:delay(),function()
      if self.mode~="resting" or not self.restState or not self.restState.ready then return end
      if self.restState.staticMove or (api.travelPending and api.travelPending()) then return end
      local inventory=api.inventoryState and api.inventoryState()
      if inventory and inventory.coinsUncertain then return end
      if self.awaitingPickup or self.awaitingDelivery or self.awaitingReturn or self.awaitingReward then
        self:pause("Odpoczynek zakonczony, ale wynik operacji z paczka nie zostal potwierdzony.");return
      end
      self.restState=nil;self.mode="paused"
      self:say("Odpoczynek zakonczony. Automatycznie wznawiam kuriera.")
      self:begin(true)
    end)
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
    if self.mode=="resting" then
      local move=self.restState and self.restState.staticMove
      if move then
        if not same(room,move.expected) then self:pause("Odpowiedz na ostatni krok nie potwierdza trasy.");return end
        self.node=move.target;self.restState.staticMove=nil
        self:cancel("restAck");self:tryResumeRest()
      end
      return
    end
    if self.externalNavigation or (self.source and (self.staticSource==false or not self.pending)) then return end
    local p=self.pending
    if not p then
      if self.mode=="running" and self.phase~="waiting" then
        self.node=nil; self:pause("Dodatkowy opis lokacji poza oczekiwanym ruchem. Sprawdz pozycje.")
      end
      return
    end
    if p.kind=="look" then
      self.pending=nil; self:cancel("watchdog")
      self:later("action",self:delay(),function() p.callback(room) end)
    elseif p.kind=="move" then
      if not same(room,p.expected) then
        self.node=nil
        self:pause("Trasa sie nie zgadza. Oczekiwano: "..p.expected.title.." / "..p.expected.exits.."; otrzymano: "..room.title.." / "..room.exits)
        return
      end
      self.node=p.target; self.pending=nil; self:cancel("watchdog")
      self:later("action",self:delay(),function() self:walkNext() end)
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
    if self:checkFatigue() then return end
    if self.source then
      local current=api.position and api.position()
      if not current or current.id~=self.source.id or current.map~=self.source.map then self:pause("Nie potwierdzono powrotu do urzedu nadania."); return end
    elseif self.node~="home" or not same(self.lastRoom,data.office) then self:pause("Tablice czytam dopiero na rozpoznanej poczcie."); return end
    self.phase="board"; self.boardRows={}; self.rowBuffer=nil; self.boardHeader=false; self.boardStale=false
    self:watch("pelna tablica paczek"); self:sendCommand("przeczytaj tablice")
  end
  function K:offerKey(o) return o.name.."|"..o.kg.."|"..value(o.pay) end
  function K:startPlanning(work,done,validate)
    if not api.planWork then done(work());return end
    if self.cancelPlanning then self.cancelPlanning();self.cancelPlanning=nil end
    local token,epoch,actor={},self.epoch,self.actor
    self.planningToken=token
    local function alive()
      if self.planningToken~=token or self.epoch~=epoch or self.actor~=actor or self.mode~="running" then return false,"przerwane planowanie" end
      if validate then return validate() end
      return true
    end
    local cancel=api.planWork(work,function(good,first,second,third,fourth)
      if self.planningToken~=token or self.epoch~=epoch or self.actor~=actor or self.mode~="running" then return end
      self.planningToken=nil;self.cancelPlanning=nil
      if not good then
        if second=="zmieniono ustawienia rankingu" then self:later("ranking",0.001,function() self:choose() end)
        elseif second=="zmieniono oferty na tablicy" then self:readBoard()
        else self:pause("Planowanie: "..tostring(second or "nie udalo sie wyznaczyc trasy")) end
        return
      end
      local completed,problem=pcall(done,first,second,third,fourth)
      if not completed then self:pause("Blad po planowaniu: "..tostring(problem)) end
    end,alive)
    if self.planningToken==token then self.cancelPlanning=cancel end
  end
  function K:rank(rows)
    local eligible,unknown,diagnostics,byOffer={},{},{},{}
    local routesByRecipient={}
    local groups={miejscowa={},miedzymiastowa={}}
    for _,o in ipairs(rows) do
      if api.cooperate then api.cooperate() end
      local detail={number=o.number,name=o.name,kg=o.kg,kind=o.kind,eligible=false}
      diagnostics[#diagnostics+1]=detail;byOffer[o]=detail
      o.route,o.value,o.score,o.eta=nil,nil,nil,nil
      -- Classify from the server's explicit type BEFORE any route work.
      if not groups[o.kind] then
        detail.category="kind";detail.reason="paczki miedzydomenowe sa wylaczone z automatycznego wyboru"
      elseif type(o.kg)~="number" or o.kg>self.config.maxKg then
        detail.category="weight"
        detail.reason=type(o.kg)=="number" and string.format("waga %.2f kg przekracza limit %.2f kg",o.kg,self.config.maxKg) or "nie rozpoznano wagi paczki"
      elseif type(o.count)~="number" or o.count<=0 then
        detail.category="empty";detail.reason="oferta wyczerpana"
      elseif value(o.pay)<=0 then
        detail.category="pay";detail.reason="brak dodatniej nagrody"
      elseif self.rejected[self:offerKey(o)] then
        detail.category="rejected";detail.reason="gra odrzucila te oferte przy poprzedniej probie"
      else groups[o.kind][#groups[o.kind]+1]=o end
    end
    for _,kind in ipairs({"miejscowa","miedzymiastowa"}) do
      local defer=kind=="miedzymiastowa" and #eligible>0
      for _,o in ipairs(groups[kind]) do
        if api.cooperate then api.cooperate() end
        local detail=byOffer[o]
        if defer then
          detail.category="deferred";detail.reason="odlozona: najpierw dostepne paczki miejscowe; trasa jeszcze nie liczona"
        else
          local recipient=norm(o.name)
          local cached=routesByRecipient[recipient]
          if not cached then
            local route,why=self:resolveRoute(o.name)
            cached={route=route,reason=why};routesByRecipient[recipient]=cached
          end
          local route,why=cached.route,cached.reason
          if not route then
            unknown[#unknown+1]=o.name
            detail.category="route";detail.reason=why or "nierozpoznany adresat lub brak drogi"
          elseif kind=="miedzymiastowa" and not route.postal then
            detail.category="kind";detail.reason="paczka miedzymiastowa wymaga doreczenia poczta -> poczta"
          else
            o.route=route;o.value=value(o.pay)
            detail.cost=route.cost or 2*#route.commands
            -- ETA and rate are diagnostics only. Neither can change the
            -- class/board order or reject an otherwise deliverable parcel.
            if api.estimateTime then
              local ok,estimate
              if api.planning and api.planning() then
                ok=true;estimate=api.estimateTime(o,route,self.source,self:delay())
              else ok,estimate=pcall(api.estimateTime,o,route,self.source,self:delay()) end
              if ok and type(estimate)=="table" and type(estimate.seconds)=="number" and
                  estimate.seconds>0 and estimate.seconds<math.huge then
                o.eta=estimate;o.score=o.value*5/estimate.seconds
                detail.eta=estimate;detail.etaSeconds=estimate.seconds;detail.silverPerMinute=o.score
                detail.timeMethod=estimate.method;detail.timeSamples=estimate.samples or 0;detail.timeConfidence=estimate.confidence
              end
            end
            detail.category="eligible";detail.eligible=true;detail.score=o.score
            eligible[#eligible+1]=o
          end
        end
      end
    end
    table.sort(eligible,function(a,b) return a.number<b.number end)
    for position,o in ipairs(eligible) do
      local detail=byOffer[o];detail.rank=position
      detail.reason="dostepna; "..o.kind.."; pozycja rankingu "..position.."; koszt drogi "..tostring(detail.cost)
      if detail.etaSeconds then
        detail.reason=detail.reason..string.format("; ETA %.1f min; %.2f sr/min; %s (%d pomiarow)",
          detail.etaSeconds/60,detail.silverPerMinute,detail.timeMethod=="learned" and "pomiar + szacunek" or "szacunek",detail.timeSamples)
      end
    end
    self.offerDiagnostics=diagnostics;self.offersLimit=self.config.maxKg;self.offersStrategy="local_first"
    self.offersSource=self.source and {id=self.source.id,name=self.source.name,city=self.source.city} or nil
    return eligible,unknown,diagnostics
  end
  function K:offerSummary()
    local rows=self.offerDiagnostics or {}
    local counts,accepted={},0
    for _,row in ipairs(rows) do
      if row.eligible then accepted=accepted+1 else counts[row.category]=(counts[row.category] or 0)+1 end
    end
    local labels={weight="waga",route="adresat lub trasa",kind="rodzaj doreczenia",deferred="po miejscowych",empty="wyczerpane",pay="nagroda",rejected="odmowa gry",time="czas kursu"}
    local reasons={}
    for _,category in ipairs({"weight","route","kind","deferred","empty","pay","rejected","time"}) do
      if counts[category] then reasons[#reasons+1]=labels[category]..": "..counts[category] end
    end
    return "Ocena ofert: "..accepted.." z "..#rows.." spelnia warunki"..(#reasons>0 and " ("..table.concat(reasons,", ")..")" or "")..". /paczki oferty — przyczyny i ranking."
  end
  function K:choose()
    if self.mode~="running" then return end
    if self.job or self.awaitingPickup or self.awaitingDelivery or self.awaitingReturn or self.awaitingReward then
      self:pause("Paczka nie zostala rozliczona; nie wybieram kolejnej ani nie zmieniam poczty."); return
    end
    if self.boardStale then self:readBoard(); return end
    local source,actor,rows=self.source,self.actor,self.boardRows
    local sourceId,sourceMap=source and source.id,source and source.map
    local maxKg,strategy,delay,roam=self.config.maxKg,self.config.strategy,self:delay(),self.config.roam
    self:cancel("watchdog")
    if api.planWork then self.phase="ranking" end
    self:startPlanning(function()
      local eligible,unknown=self:rank(rows or {})
      local office,why
      if not eligible[1] and self.config.roam and api.nextOffice and source then office,why=api.nextOffice(source) end
      return eligible,unknown,office,why
    end,function(eligible,unknown,office,why) self:chooseRanked(eligible,unknown,office,why) end,function()
      local here=api.position and api.position()
      if self.actor~=actor or self.source~=source or self.boardRows~=rows or
          (source and (source.id~=sourceId or source.map~=sourceMap or not here or here.id~=sourceId or here.map~=sourceMap)) then
        return false,"zmieniono postac, poczte lub polozenie podczas oceny ofert"
      end
      if self.boardStale then return false,"zmieniono oferty na tablicy" end
      if self.config.maxKg~=maxKg or self.config.strategy~=strategy or self:delay()~=delay or self.config.roam~=roam then return false,"zmieniono ustawienia rankingu" end
      return true
    end)
  end
  function K:chooseRanked(eligible,unknown,office,why)
    if self.mode~="running" then return end
    if self.boardStale then self:readBoard();return end
    if not eligible[1] then
      self:say(self:offerSummary())
      if office and self.config.roam then self:relocate(office); return end
      local seen,names={},{}
      for _,name in ipairs(unknown) do if not seen[name] then seen[name]=true; names[#names+1]=name end end
      self.phase="waiting"
      self:say("Brak dostepnej znanej paczki do "..self.config.maxKg.." kg. Odswiezanie za "..self.config.refresh.." s."..
        (why and " Inna poczta: "..why.."." or "")..
        (#names>0 and " Nieznane trasy: "..table.concat(names,", ")..". /paczki npc <adresat>" or ""))
      self:later("refresh",self.config.refresh,function() self:readBoard() end)
      return
    end
    if api.officeWorking and self.source then api.officeWorking(self.source) end
    local o=eligible[1]
    self.selected=o; self.phase="pickup"
    self:say("Wybieram #"..o.number.." ["..o.kind.."]: "..o.route.name..", "..o.kg.." kg, "..o.pay.gold.." zl, "..o.pay.silver.." sr, "..o.pay.copper.." md; koszt drogi: "..
      (o.route.cost or 2*#o.route.commands)..(o.route.postal and " (do poczty docelowej)." or " (tam i z powrotem)."))
    if o.eta then self:say(string.format("Przewidywany caly kurs: %.1f min; %.2f sr/min (%s; %d pomiarow).",
      o.eta.seconds/60,o.score,o.eta.method=="learned" and "dopasowanie do pomiarow" or "szacunek",o.eta.samples or 0)) end
    if api.startTiming then pcall(api.startTiming,o,self.source) end
    self.awaitingPickup=true
    self:checkpoint()
    self:watch("odbior paczki"); self:sendCommand("wybierz paczke "..o.number)
  end
  function K:accepted(name)
    self:cancel("watchdog")
    self.awaitingPickup=false
    -- The game's own pickup ACK confirms the already ranked recipient.
    -- Navigation still plans fresh road legs; do not block this event by
    -- recomputing every quote that was just used to choose the parcel.
    local route=self.selected and norm(self.selected.name)==norm(name) and self.selected.route or nil
    if not route then route=self:resolveRoute(name) end
    self.job={name=name,route=route,actor=self.actor,delivered=false,source=self.source,recipientConfirmed=true}
    if api.pickupTiming then pcall(api.pickupTiming,self.job) end
    if api.parcelState then api.parcelState("hands") end
    self:checkpoint()
    if not route then
      self.phase="returnUnknown"
      self:say("Gra wydala paczke dla nieznanego adresata: "..name..". Zwracam ja w urzedzie nadania.")
      self:later("action",self:delay(),function()
        self.awaitingReturn=true; self:checkpoint(); self:watch("zwrot nieznanej paczki"); self:sendCommand("zwroc paczke")
      end)
      return
    end
    if self.selected and norm(name)~=self.selected.name then self:say("Zmiana numeracji ofert. Potwierdzony adresat: "..route.name..".") end
    self:later("action",self:delay(),function()
      self:outbound()
    end)
  end
  function K:waitForRecipient(reason,absent)
    local route=self.job and self.job.route
    if self.mode~="running" or not route then return false end
    local searching=api.canSearchFor and api.canSearchFor(route)==true
    local waiting=api.canWaitFor and api.canWaitFor(route)==true
    if not searching and not waiting then return false end
    self:cancel("watchdog");self:cancel("action")
    self.awaitingDelivery=false;self.manualDelivery=false
    if absent and api.recipientAbsent then api.recipientAbsent(route) end
    self:checkpoint()
    if not reason and absent then
      reason=searching and "Adresat odszedl. Szukam go w kolejnych lokacjach miasta." or
        "Adresat jest chwilowo nieobecny. Czekam na jego powrot w tej lokacji."
    end
    if reason then self:say(reason) end
    -- Cancelling a walk cannot recall its last sent step. Keep the course
    -- owned, but never start another movement or handover until it settles.
    if api.travelPending and api.travelPending() then
      self.phase=searching and "searchingCity" or "waitingNpc"
      local function settled()
        if self.mode~="running" or not self.job or self.job.route~=route then return end
        if api.travelPending and api.travelPending() then self:later("recipientSearch",0.1,settled)
        else self:waitForRecipient() end
      end
      self:later("recipientSearch",0.1,settled)
      return true
    end
    self:cancel("recipientSearch")
    -- Re-enter only the owned recipient search. The parcel remains in its
    -- confirmed location; do not replay stowing or a completed handover.
    self:navigate(route,function() self:deliver() end)
    return true
  end
  function K:recipientReady()
    local route=self.job and self.job.route
    if route and api.deliveryReady and api.deliveryReady(route)==false then
      if not self:waitForRecipient() then
        self:pause("Nie potwierdzono adresata w jego znanej lokacji. Sprawdz pozycje i baze /npc.")
      end
      return false
    end
    return true
  end
  function K:deliver()
    if not self:recipientReady() then return end
    self:inventory("takeParcel",function() self:handoverParcel() end)
  end
  function K:handoverParcel()
    if not self:recipientReady() then return end
    if self.job and self.job.route and self.job.route.postal then
      self.phase="delivery"; self.awaitingDelivery=true; self:checkpoint();self:watch("doreczenie w urzedzie"); self:sendCommand("oddaj paczke"); return
    end
    self.phase="introduce"
    self:sendCommand("przedstaw sie")
    self:later("action",math.max(self:delay(),0.5),function()
      if not self:recipientReady() then return end
      self.phase="delivery"; self.awaitingDelivery=true; self:checkpoint();self:watch("doreczenie paczki"); self:sendCommand("oddaj paczke")
    end)
  end
  function K:settleDelivery()
    if self.job and self.job.coinReceipt and api.coinReceipt and api.coinReceipt()>self.job.coinReceipt then self.job.coinsPending=false end
    if self.job and not self.job.coinsPending then self:afterDelivery();return end
    if self.job and api.coinReceipt then self.job.coinReceipt=api.coinReceipt() end
    self:inventory("stowCoins",function()
      if self.job then self.job.coinsPending=false end
      self:checkpoint()
      self:afterDelivery()
    end)
  end
  function K:goHome()
    local function arrived()
      if self.staticSource~=false then self.node="home"; self.lastRoom=data.office end
      if api.finishTiming then pcall(api.finishTiming,self.job,self.source) end
      self.job=nil; self.selected=nil
      self:checkpoint()
      if self.stopAt and self.stats.delivered>=self.stopAt then
        self:stop("Wykonano limit doreczen; postac wrocila na poczte."); self:status()
      else self:readBoard() end
    end
    if self.source and (self.staticSource==false or (self.job and self.job.route and self.job.route.native)) then
      self:navigate(self.source,arrived,true)
    else self:walk("home",arrived,"inbound") end
  end
  function K:afterDelivery()
    local route=self.job and self.job.route
    if route and route.postal and api.currentOffice then
      local held=api.inventoryState and api.inventoryState()
      local uncertainCoins=held and held.coinsUncertain or (not held and self.savedInventoryUncertain)
      if not self.job.delivered or self.job.coinsPending or uncertainCoins or
        self.awaitingPickup or self.awaitingDelivery or self.awaitingReturn or self.awaitingReward then
        self:pause("Paczka lub wyplata nie zostala rozliczona; nie zmieniam urzedu nadania.");return
      end
      local here=api.position and api.position()
      local office=api.currentOffice()
      local mapped=here and type(here.map)=="number" and here.map>0 and here.map==math.floor(here.map) and
        type(here.id)=="string" and here.id~=""
      if not mapped or not office or office.id~=here.id or office.map~=here.map then office=nil end
      -- A delivered parcel may have been settled manually before travelling
      -- to another known office. Continue at the verified current office.
      -- A delivery-only depot can be absent from the static office registry;
      -- recognize it only at the exact map/hash of this confirmed postal job.
      if not office and mapped and here.id==route.targetId and route.roomIds and route.roomIds[here.map]==here.id then
        office={id=here.id,map=here.map,name=route.targetName or here.name or self.job.name,staticNuln=false}
      end
      if not office then
        self:pause("Paczka oddana, ale nie potwierdzono polozenia poczty docelowej.");return
      end
      if api.finishTiming then pcall(api.finishTiming,self.job,office) end
      self.job=nil;self:adoptOffice(office)
      if self.stopAt and self.stats.delivered>=self.stopAt then
        self:stop("Wykonano limit doreczen; postac jest w rozpoznanej placowce.");self:status()
      else
        self:say("Doreczenie miedzy urzedami zakonczone. Sprawdzam paczki tutaj: "..office.name..".")
        self:readBoard()
      end
    else self:goHome() end
  end
  function K:begin(resume,limit)
    local function refuse(reason)
      if self.mode=="resting" or self.mode=="paused" then self:pause(reason)
      else self.lastPause=reason; self:say(reason) end
    end
    if self.mode=="running" or self.mode=="learning" then self:say("Automat juz pracuje. /kurier stop"); return end
    if self.needsResumeValidation and api.sessionReady then
      local ready,why=api.sessionReady(self.actor)
      if not ready then refuse("Kurs pozostaje zapisany. "..tostring(why or "Czekam na dane postaci i pozycji GMCP.").." /paczki wznow po odswiezeniu danych.");return end
      local hydrated,problem=self:hydrateRun()
      if not hydrated then refuse("Kurs pozostaje zapisany: "..tostring(problem)..".");return end
      self.needsResumeValidation=false
    end
    local held=api.inventoryState and api.inventoryState()
    local uncertainCoins=held and held.coinsUncertain or (not held and self.savedInventoryUncertain)
    if uncertainCoins then
      refuse(self.job and self.job.coinsPending and "Paczka jest rozliczona, ale schowanie monet nie zostalo potwierdzone. Sprawdz monety przed wznowieniem." or
        "Przeniesienie monet nie zostalo potwierdzone. Czekam na wynik poprzedniej operacji; nie ponawiam jej przed wznowieniem.");return
    end
    if held and held.state=="unknown" and self.job and not self.job.delivered then
      refuse("Kurs pozostaje zapisany, ale polozenie paczki nie zostalo potwierdzone. Sprawdz plecak, wez paczke do rak i uzyj /paczki paczka <adresat>.");return
    end
    if self.awaitingPickup or self.awaitingDelivery or self.awaitingReturn or self.awaitingReward then
      refuse("Wynik ostatniego odbioru/oddania/zwrotu nie zostal potwierdzony. Sprawdz paczke: /kurier paczka <adresat>, jesli ja masz; /kurier reset po jej rozliczeniu."); return
    end
    if not resume and self.job and not self.job.delivered then refuse("Pamietam rozpoczęte doreczenie. Uzyj /kurier wznow albo /kurier reset po recznym rozliczeniu paczki."); return end
    if self.job and self.job.actor and self.actor and self.job.actor~=self.actor then refuse("Zmieniono postac. Uzyj /kurier reset przed nowym uruchomieniem."); return end
    -- Checkpoints keep semantic destinations, never executable paths or local
    -- map numbers. Resolve also completed postal jobs before deciding where
    -- to work next, so a reload cannot send them back to the issuing office.
    if self.job and not self.job.route and api.planWork then
      local job,source,here=self.job,self.source,api.position and api.position()
      self:clearTimers();self.mode="running";self.phase="planningCourse"
      self:startPlanning(function() return self:resolveRoute(job.name) end,function(route,why)
        if not route then
          if job.delivered then self:pause("Kurs pozostaje zapisany. Paczka oddana, ale nie rozpoznano jej celu na aktualnej mapie; sprawdz baze /npc i mape przed wznowieniem.")
          else self:pause("Kurs pozostaje zapisany: "..tostring(why or "brak drogi do adresata")..".") end
          return
        end
        job.route=route;self.mode="paused";self:begin(resume,limit)
      end,function()
        local current=api.position and api.position()
        return self.job==job and self.source==source and here and current and current.id==here.id and current.map==here.map,
          "zmieniono kurs lub polozenie podczas odtwarzania trasy"
      end)
      return
    end
    if self.job and not self.job.route then self.job.route=self:resolveRoute(self.job.name) end
    if self.job and self.job.delivered and not self.job.route then
      refuse("Kurs pozostaje zapisany. Paczka oddana, ale nie rozpoznano jej celu na aktualnej mapie; sprawdz baze /npc i mape przed wznowieniem.");return
    end
    self:clearTimers(); self.pending=nil; self.mode="running"; self.phase="locating"; self.lastPause=nil
    self.runCleared=nil
    if not resume then
      self.rejected={}
      if limit then self.stopAt=self.stats.delivered+limit else self.stopAt=nil end
    end
    self.stats.started=self.stats.started or api.now()
    self:checkpoint()
    if self:checkFatigue() then return end
    if not resume and not self.job then
      local office=api.currentOffice and api.currentOffice()
      if office then self:adoptOffice(office)
      elseif not self.relocation then self.source=nil;self.staticSource=nil end
    end
    if self.relocation and not self.job then self:relocate(self.relocation.to,self.relocation.manual); return end
    if self.job and self.job.delivered and self.job.coinsPending then self:settleDelivery();return end
    if self.job and self.job.delivered and self.job.route and self.job.route.postal and api.currentOffice then
      self:afterDelivery();return
    end
    if not self.source and api.source then
      self:captureSource()
    end
    if self.source and (self.staticSource==false or (self.job and self.job.route and self.job.route.native)) then
      if self.job and not self.job.delivered then
        if not self.job.route then self.job.route=self:resolveRoute(self.job.name) end
        self:outbound()
      else self:goHome() end
      return
    end
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
        self:outbound()
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
    if api.cancelTiming then pcall(api.cancelTiming,"reczna komenda") end
    if self.mode=="resting" then self:pause("Reczna komenda lub inny skrypt przerwal odpoczynek.");self.node=nil end
    if cmd:match("^wybierz paczke %d+$") and self.mode~="learning" then
      if self.mode=="running" then self:pause("Reczny odbior paczki; czekam na odpowiedz gry.") end
      self.manualPickup=true;self.awaitingPickup=true
      self.runCleared=nil
      self.pendingManualSource=api.currentOffice and api.currentOffice()
      self:checkpoint()
      return
    end
    -- A player may complete the remembered job after a navigation pause.
    -- Observe the actual command and server reply; never infer completion
    -- merely from stopping the bot or from a parcel disappearing in inventory.
    if cmd=="oddaj paczke" and self.job and not self.job.delivered and self.mode~="learning" then
      if self.mode=="running" then self:pause("Reczne oddanie paczki; czekam na odpowiedz gry.") end
      self.manualDelivery=true; self.awaitingDelivery=true
      self:checkpoint()
      return
    end
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
      local label=cmd=="i" and " 'i'" or ""
      self:pause("Reczna komenda"..label.." lub inny skrypt przejal sterowanie."); self.node=nil
    elseif reverse[cmd] or cmd:find("wejdz",1,true) or cmd:find("wyjdz",1,true) then self.node=nil end
  end
  function K:disconnected()
    self.sessionNonce=self.sessionNonce+1
    self.needsResumeValidation=true
    self:pause("Polaczenie z gra zostalo przerwane. Po zalogowaniu uzyj /kurier wznow."); self.node=nil
  end
  function K:captureDeliveryProof(subject,text)
    if not subject or not self.config.autoLearn or not api.deliveryEvidence then return end
    if not subject.recipientConfirmed and not (subject==self.learning and subject.picked) then return end
    local ok,evidence=pcall(api.deliveryEvidence,subject.route or {name=subject.name})
    if not ok or type(evidence)~="table" or evidence.verified~=true then return end
    evidence.recipient=subject.name
    evidence.postal=tostring(text):match("^zostawiasz przesylke w okienku urzedu pocztowego%.")~=nil
    if evidence.postal then evidence.npc=nil end
    evidence.handover=true;evidence.reward=false
    subject.deliveryProof={evidence=evidence,actor=self.actor,session=self.sessionNonce}
  end
  function K:learnConfirmedDelivery(subject)
    local proof=subject and subject.deliveryProof
    if not proof or subject.learningSaved or not self.config.autoLearn or not api.learnDelivery then return end
    subject.learningSaved=true
    if proof.actor~=self.actor or proof.session~=self.sessionNonce then return end
    proof.evidence.reward=true
    local ok,saved,why=pcall(api.learnDelivery,proof.evidence)
    if not ok or not saved then
      self:say("Nie zapisano adresata w bazie kuriera: "..tostring(ok and why or saved)..".")
    end
  end
  function K:identifyActor(name,initial)
    local actor=norm(name)
    if actor=="" then return end
    if initial and not self.actor then
      self.actor=actor
      if self.job or self.relocation then
        if self.job then self.job.actor=actor end
        self:checkpoint()
      else self:restoreRun() end
      return
    end
    local changed=self.actor~=actor
    if changed then
      self:checkpoint()
      if self.actor and (self.mode=="running" or self.mode=="learning" or self.mode=="resting") then self:pause("Zmieniono postac; rozpocznij nowa prace kuriera.") end
      self.suppressCheckpoint=true
      if api.actorChanged then api.actorChanged() end
      if api.clearTravelIntent then api.clearTravelIntent() end
      self.job=nil;self.stats={delivered=0,gold=0,silver=0,copper=0,started=nil}
      self.runCleared=nil
      self.savedInventoryUncertain=false
      self.offerDiagnostics=nil;self.offersSource=nil;self.offersLimit=nil;self.offersStrategy=nil
      self.node=nil;self.source=nil;self.staticSource=nil;self.relocation=nil;self.stopAt=nil
      self.awaitingPickup,self.awaitingDelivery,self.awaitingReturn,self.awaitingReward=false,false,false,false
      self.manualDelivery=false;self.manualPickup=false;self.pendingManualSource=nil
      if api.resetOffices then api.resetOffices() end
      if api.parcelState then api.parcelState("hands") end
      self.suppressCheckpoint=nil
    end
    self.actor=actor
    if changed and api.loadRun then self:restoreRun() end
  end
  function K:rememberLateConfirmation(s,text)
    if self.manualPickup and self.awaitingPickup and ((s:match("^nie ") and (s:find("pacz",1,true) or s:find("przesyl",1,true) or s:find("sily",1,true))) or
        s:match("^masz juz ") or s:match("^niesiesz juz ") or s:match("^to zlecenie ") or s:match("^jestes zbyt obciazon")) then
      self.manualPickup=false;self.awaitingPickup=false;self.pendingManualSource=nil
      self:checkpoint()
      self:say("Gra nie potwierdzila recznego odbioru paczki.");return
    end
    if self.manualDelivery and self.awaitingDelivery and (s:match("^adresat nie znajduje sie w tym miejscu%.") or
        s:match("^musisz odnalezc ") or s:match("^nie masz ") or s:match("^nie niesiesz ") or
        s:match("^nie ma tu ") or s:match("^nie widzisz ")) then
      self.manualDelivery=false; self.awaitingDelivery=false
      self:checkpoint()
      self:say("Gra nie potwierdzila recznego oddania. Sprawdz adresata i paczke.")
      return
    end
    local picked=s:match("^bierzesz paczke przeznaczona dla: (.+)%.$")
    if picked and self.awaitingPickup then
      self.awaitingPickup=false
      if self.manualPickup and self.pendingManualSource then self:adoptOffice(self.pendingManualSource) end
      self.manualPickup=false;self.pendingManualSource=nil
      local route=not self.manualPickup and self.selected and norm(self.selected.name)==norm(picked) and self.selected.route or nil
      -- A manual/late pickup needs no navigation while paused. Resolve its
      -- semantic destination when the player resumes the saved course.
      self.job={name=route and route.name or picked,route=route,actor=self.actor,delivered=false,source=self.source,recipientConfirmed=true}
      if api.parcelState then api.parcelState("hands") end
      self:checkpoint()
      self:say("Gra potwierdzila odbior paczki; automat pozostaje wstrzymany.")
    elseif self.awaitingDelivery and self.job and handover(s) then
      self.awaitingDelivery=false; self.manualDelivery=false; self.awaitingReward=true; self.job.delivered=true
      self:captureDeliveryProof(self.job,s)
      if api.parcelState then api.parcelState("hands") end
      self.stats.delivered=self.stats.delivered+1
      self:checkpoint()
      self:say("Gra potwierdzila doreczenie po zatrzymaniu automatu.")
    elseif self.awaitingReward and reward(s) then
      self.awaitingReward=false
      self:learnConfirmedDelivery(self.job)
      if self.job then self.job.coinsPending=true end
      local pay=money(s)
      self.stats.gold=self.stats.gold+pay.gold; self.stats.silver=self.stats.silver+pay.silver; self.stats.copper=self.stats.copper+pay.copper
      self:checkpoint()
    elseif self.awaitingReturn and (s:match("^zwracasz paczke") or s:match("^oddajesz paczke pracownikowi") or s:match("^zwrociles paczke") or s:match("^zwrocilas paczke")) then
      self.awaitingReturn=false; self.job=nil
      self:checkpoint()
    end
  end
  function K:onLine(raw)
    local text=trim(tostring(raw or "")); local s=norm(text)
    if s=="" then return end
    local actor=s:match("^witaj, (.-)[%.!] podaj haslo")
    if actor then
      -- The greeting uses a vocative (e.g. Testowiczu), not the canonical
      -- character name. Only Char.Info may change identity in native mode.
      if api.actor then
        local canonical=api.actor()
        if canonical then self:identifyActor(canonical,true) end
      else self:identifyActor(actor) end
    end
    local active=self.mode=="running" or self.mode=="learning" or self.mode=="resting"
    local attacker=s:match("^([^:'\"]+) atakuje cie[%s%.!]") or s:match("^([^:'\"]+) rzuca sie na ciebie[%s%.!]") or
      s:match("^([^:'\"]+) koncentruje sie na walce z toba[%s%.!]")
    local attack=attacker or
      s:match("^zostajesz zaatakowan") or s:match("^jestes w trakcie walki")
    if active and attack and api.combatStarted then api.combatStarted({name=attacker});return end
    if active and (s:find("nadchodzi czas apokalipsy",1,true) or s:find("glos jezdzca apokalipsy",1,true) or
        s:match("^podaj swoje imie") or s:match("^witaj, .-podaj haslo") or
        s:match("^jestes w trakcie walki") or s:find("nie mozesz zakonczyc gry w takim pospiechu",1,true) or
        s:find("atakuje cie",1,true) or s:find("rzuca sie na ciebie",1,true) or s:match("^zostajesz zaatakowan")) then
      self:pause("Gra wymaga uwagi: walka, apokalipsa lub ponowne logowanie."); return
    end
    if self.mode~="running" and self.mode~="learning" then
      self:rememberLateConfirmation(s,text)
      if self.mode~="resting" then return end
      self:tryResumeRest()
    end
    if self.awaitingReward and self.phase~="reward" and reward(s) then
      self:rememberLateConfirmation(s,text); return
    end
    if self.mode=="learning" and self.learning and self.learning.awaitingReward and reward(s) then
      self.learning.awaitingReward=false;self:learnConfirmedDelivery(self.learning);return
    end
    if self.pending and self.pending.kind=="move" and s:find("zmecz",1,true) and s:find("nie mozesz isc",1,true) then
      self.pending=nil
      self:rest("Gra odmowila kroku ze zmeczenia.");return
    end
    if self.phase=="board" and s=="nie masz zadnej poczty." then
      -- This is an explicit response to our board request, not a truncated
      -- offer list. Delivery-only depots need not provide outgoing parcels.
      self:cancel("watchdog")
      self.boardRows={};self.rowBuffer=nil;self.boardHeader=false;self.boardStale=false
      self.phase="planning"
      self:say("Placowka nie udostepnia tablicy paczek. Sprawdzam dalsza prace zgodnie z ustawieniem zmiany poczty.")
      self:later("action",self:delay(),function() self:choose() end)
      return
    end
    if self.phase=="board" and s:match("^przesylki dostepne dla .+:$") then
      self.boardHeader=true; self.rowBuffer=nil; return
    end
    if (self.phase=="board" or self.phase=="planning" or self.phase=="ranking") and s:find("bierze paczke z tablicy",1,true) then self.boardStale=true end
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
        self:later("action",self:delay(),function() self:choose() end)
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
      self:checkpoint()
      self:later("action",self:delay(),function() self:readBoard() end); return
    end
    if handover(s) then
      if self.mode=="learning" and self.learning then
        local l=self.learning
        if self.pending or not l.picked or #l.commands<1 then self:pause("Brak pelnej trasy do udanego doreczenia."); return end
        l.delivered=true; l.returnIndex=#l.commands;l.awaitingReward=true
        self:captureDeliveryProof(l,s)
        self:say("Doreczenie potwierdzone. Wroc recznie dokladnie ta sama droga w odwrotnej kolejnosci; powrot na poczte zapisze trase.")
      elseif self.phase=="delivery" and self.job and not self.job.delivered then
        self.awaitingDelivery=false; self.awaitingReward=true
        self.job.delivered=true; self.stats.delivered=self.stats.delivered+1
        if api.handoverTiming then pcall(api.handoverTiming,self.job) end
        self:captureDeliveryProof(self.job,s)
        if api.parcelState then api.parcelState("hands") end
        self.phase="reward"; self:watch("kwota nagrody po doreczeniu")
        self:checkpoint()
      end
      return
    end
    if self.phase=="reward" and reward(s) then
      self:cancel("watchdog")
      self.awaitingReward=false
      if api.rewardTiming then pcall(api.rewardTiming,self.job) end
      self:learnConfirmedDelivery(self.job)
      local pay=money(s)
      self.stats.gold=self.stats.gold+pay.gold; self.stats.silver=self.stats.silver+pay.silver; self.stats.copper=self.stats.copper+pay.copper
      self.phase="rewardReceived"
      self.job.coinsPending=true
      self:checkpoint()
      self:say("Doreczono: "..self.job.name..". Lacznie: "..self.stats.delivered.." paczek; "..
        self.stats.gold.." zlotych, "..self.stats.silver.." srebrnych, "..self.stats.copper.." miedzianych.")
      self:later("action",self:delay(),function() self:settleDelivery() end); return
    end
    local packageContext=s:find("pacz",1,true) or s:find("przesyl",1,true) or s:find("zlecen",1,true) or s:find("numer",1,true)
    if self.phase=="pickup" and (((s:match("^nie ") or s:match("^to zlecenie ") or s:match("^ta paczka ") or s:match("^masz juz ") or s:match("^niesiesz juz ")) and packageContext) or s:match("^nie masz dosc sily") or s:match("^jestes zbyt obciazon")) then
      if api.cancelTiming then pcall(api.cancelTiming,"gra odrzucila odbior") end
      self.awaitingPickup=false
      self:checkpoint()
      if s:find("pacz",1,true) and (s:find("juz",1,true) or s:find("niesiesz",1,true)) and not s:find("nie ma juz",1,true) then
        self:pause("Gra informuje o niesionej paczce. Ustal adresata i uzyj /kurier paczka <adresat>.")
      else
        self:cancel("watchdog")
        if self.selected then self.rejected[self:offerKey(self.selected)]=true end
        self.phase="rejected"
        self:later("action",self:delay(),function() self:readBoard() end)
      end
      return
    end
    if self.phase=="delivery" and (s:match("^adresat nie znajduje sie w tym miejscu%.") or s:match("^musisz odnalezc ") or s:match("^nie masz ") or s:match("^nie niesiesz ") or s:match("^nie ma tu ") or s:match("^nie widzisz ")) then
      self.awaitingDelivery=false
      if (s:match("^adresat nie znajduje sie w tym miejscu%.") or s:match("^musisz odnalezc ")) and
        self:waitForRecipient(nil,true) then return end
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
      (elapsed>0 and string.format(" | %.1f sr/min (czas od pierwszego startu)",value(self.stats)*5/elapsed) or "")..
      " | limit wagi: "..self.config.maxKg.." kg | strategia: "..self.config.strategy..
      string.format(" | opoznienie kroku: %.2f s",self:delay())..
      " | nauka: "..(self.config.autoLearn and "auto" or "wylaczona")..
      " | zmiana poczty: "..(self.config.roam and "auto" or "wylaczona")..
      (self.relocation and " | kolejna poczta: "..self.relocation.to.name or "")..
      (self.job and " | paczka: "..self.job.name..(self.job.delivered and " (oddana)" or " (w drodze)") or ""))
  end
  function K:help()
    self:say("/kurier start [liczba] | stop | wznow | status | trasy | oferty | plecak auto/stop | limit <kg> | tempo <sekundy> | odswiezanie <sekundy> | tryb miejscowe | poczty auto/stop | poczta <miasto|tutaj> | paczka <adresat> | ucz <adresat> | nauka auto/stop | baza | reset")
    self:say("Pierwszy start: bez paczki, w urzedzie nadania. /paczki npc Imie Nazwisko sprawdza baze /npc i mape. Trasy tekstowe oraz ich nauka zaczynaja sie na poczcie w Nuln.")
    if api.estimateTime then self:say("Kolejnosc: miejscowe, potem miedzymiastowe poczta -> poczta. Miedzydomenowe wylaczone. W grupie: numer tablicy; waga tylko jako limit. ETA i sr/min sa informacyjne.") end
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
    elseif verb=="poczta" then self:selectOffice(arg)
    elseif verb=="status" then self:status()
    elseif verb=="plecak" then
      local option=norm(arg)
      if option~="auto" and option~="stop" then self:say("/paczki plecak auto | /paczki plecak stop. Wykrywanie noszonego plecaka: "..(self.config.autoBackpack and "wlaczone" or "wylaczone").."; przypisania /pojemniki maja pierwszenstwo.");return end
      self.config.autoBackpack=option=="auto";self:save()
      self:say("Automatyczne wykrywanie noszonego plecaka: "..(self.config.autoBackpack and "wlaczone" or "wylaczone")..". Przypisania /pojemniki maja pierwszenstwo.")
    elseif verb=="nauka" then
      local option=norm(arg)
      if option~="auto" and option~="stop" then self:say("/paczki nauka auto | /paczki nauka stop; zapis po potwierdzonym oddaniu i wyplacie. /paczki baza — zapamietani adresaci.");return end
      self.config.autoLearn=option=="auto";self:save()
      self:say("Automatyczne zapamietywanie doreczen: "..(self.config.autoLearn and "wlaczone" or "wylaczone")..". Zapisana baza pozostaje dostepna.")
    elseif verb=="trasy" then
      local names={}; for _,r in pairs(self.routes) do names[#names+1]=r.name.." ("..#r.commands.." krokow)" end
      table.sort(names); self:say("Znane trasy z poczty Nuln: "..table.concat(names, "; "))
    elseif verb=="ucz" then self:learn(arg)
    elseif verb=="paczka" then
      if self.mode=="running" or self.mode=="learning" then self:say("Najpierw /kurier stop."); return end
      if self.needsResumeValidation and api.sessionReady then
        local ready,why=api.sessionReady(self.actor)
        if not ready then self:say(why or "Czekam na dane postaci i pozycji GMCP.");return end
        local hydrated,problem=self:hydrateRun()
        if not hydrated then self:say("Kurs pozostaje zapisany: "..tostring(problem)..".");return end
      end
      if not self.source and api.source then self:captureSource() end
      local r=self:resolveRoute(arg)
      -- A postal delivery can be recovered on the road after reloading the
      -- profile: it ends at its destination office, without a guessed return
      -- to an unknown issuing office. NPC jobs still require their source.
      if not r and not self.source and api.resolveRoute and api.position then
        local here=api.position()
        if here and type(here.map)=="number" and here.map>0 and here.id then
          local candidate=api.resolveRoute(arg,here)
          if candidate and candidate.postal then
            r=candidate;self.source=here;self.staticSource=false;self.node=nil
          end
        end
      end
      if not r then self:say("Nieznany adresat. /kurier trasy"); return end
      self.awaitingPickup,self.awaitingDelivery,self.awaitingReturn,self.awaitingReward=false,false,false,false
      self.manualDelivery=false
      self.manualPickup=false;self.pendingManualSource=nil
      local confirmed=self.job and self.job.recipientConfirmed and norm(self.job.name)==norm(r.name)
      self.job={name=r.name,route=r,actor=self.actor,delivered=false,source=self.source,recipientConfirmed=confirmed==true}; self:say("Ustawiono niesiona paczke dla "..r.name..". /kurier wznow")
      self.runCleared=nil;self.savedInventoryUncertain=false
      if api.parcelState then api.parcelState("hands") end
      self:checkpoint()
    elseif verb=="reset" then
      self:stop("Zatrzymano kuriera przed wyczyszczeniem kursu.")
      if api.forgetRun and self.actor and (not api.loadRun or api.loadRun(self.actor)) then
        local ok,removed,why=pcall(api.forgetRun,self.actor)
        if not ok or removed==false then
          self.lastPause="Nie usunieto zapisu kursu: "..tostring(ok and why or removed)..". Kurs pozostaje zapamietany; ponow /paczki reset po naprawie zapisu."
          self:say(self.lastPause);return
        end
      end
      self.job=nil; self.node=nil; self.rejected={}; self.stopAt=nil; self.source=nil; self.staticSource=nil; self.relocation=nil
      if api.resetOffices then api.resetOffices() end
      self.awaitingPickup,self.awaitingDelivery,self.awaitingReturn,self.awaitingReward=false,false,false,false
      self.manualDelivery=false
      self.manualPickup=false;self.pendingManualSource=nil
      self.stats={delivered=0,gold=0,silver=0,copper=0,started=nil}
      self.runCleared=true;self.needsResumeValidation=false;self.savedInventoryUncertain=false
      if api.restoreInventory then api.restoreInventory({state="hands",coinsUncertain=false}) end
      self.lastPause="Wyczyszczono pamiec kursu; paczka w grze wymaga osobnego rozliczenia."
      self:say(self.lastPause)
    elseif verb=="poczty" then
      local option=norm(arg)
      if option=="auto" then self.config.roam=true
      elseif option=="stop" then self.config.roam=false
      else self:say("/paczki poczty auto — zmieniaj pusta poczte; /paczki poczty stop — czekaj na miejscu."); return end
      self:save(); self:say("Zmiana poczty przy braku odpowiednich ofert: "..(self.config.roam and "auto" or "wylaczona")..".")
      if not self.config.roam and self.relocation and not self.relocation.manual then
        self:pause("Anulowano automatyczna zmiane poczty.");self.relocation=nil
        local office=api.currentOffice and api.currentOffice()
        if office then self:adoptOffice(office) else self.source=nil;self.staticSource=nil end
        self:checkpoint()
      end
    elseif verb=="tempo" or verb=="opoznienie" then
      if norm(arg)=="chodzik" or norm(arg)=="auto" then self.config.tempoSource="walker"
      elseif arg~="" then
        local n=tonumber((arg:gsub(",",".")))
        if not n or n<0.15 or n>60 then self:say("Opoznienie kroku: 0.15–60 sekund, np. /paczki tempo 1.5; /paczki tempo chodzik.");return end
        self.config.delay=n;self.config.tempoSource="courier"
      else
        self:say(string.format("Opoznienie kroku: %.2f s (%s). /paczki tempo 1.5 | /paczki tempo chodzik",self:delay(),self.config.tempoSource=="walker" and "ustawienia chodzika" or "wlasne tempo paczek"));return
      end
      self:save()
      if api.cancelTiming then pcall(api.cancelTiming,"zmieniono tempo") end
      if api.tempoChanged then api.tempoChanged() end
      self:say(string.format("Opoznienie kroku: %.2f s (%s).",self:delay(),self.config.tempoSource=="walker" and "ustawienia chodzika" or "wlasne tempo paczek"))
    elseif verb=="limit" or verb=="odswiezanie" then
      local n=tonumber(((arg or ""):gsub(",",".")))
      local key,min,max="maxKg",0.1,100
      if verb=="tempo" then key,min,max="delay",0.15,10 elseif verb=="odswiezanie" then key,min,max="refresh",5,600 end
      if not n or n<min or n>max then self:say("Podaj liczbe od "..min.." do "..max.."."); return end
      self.config[key]=n; self.rejected={}; self:save(); self:say("Ustawiono "..key.." = "..n)
      if verb=="limit" and api.resetOffices then api.resetOffices() end
    elseif verb=="tryb" then
      if not ({miejscowe=true,zarobek=true,zaplata=true,lekkie=true})[norm(arg)] then
        self:say("Tryb: miejscowe. Najpierw miejscowe, potem miedzymiastowe poczta -> poczta."); return
      end
      self.config.strategy="local_first"; self:save()
      self:say("Kolejnosc: miejscowe, potem miedzymiastowe poczta -> poczta. Dawne tryby cen i wagi nie zmieniaja tej kolejnosci.")
    else self:help() end
  end
  -- Configuration and recorded text routes; live courses use the separate
  -- validated per-character checkpoint injected by the native adapter.
  K.nodes.home={room=data.office,edges={}}; K.titles[norm(data.office.title)]=true
  for _,r in pairs(data.routes) do assert(K:addRoute(r),"Invalid bundled route: "..tostring(r.name)) end
  if type(saved)=="table" then
    if type(saved.config)=="table" then
      local c=saved.config
      for _,key in ipairs({"delay","timeout","refresh","maxKg"}) do
        local n=tonumber(c[key]); if n and n>0 and n<1000 then K.config[key]=n end
      end
      K.config.delay=math.max(0.15,K.config.delay); K.config.refresh=math.max(5,K.config.refresh)
      -- Old saved rate/pay/light preferences cannot override local-first policy.
      K.config.strategy="local_first"
      if type(c.roam)=="boolean" then K.config.roam=c.roam end
      if type(c.autoLearn)=="boolean" then K.config.autoLearn=c.autoLearn end
      if type(c.autoBackpack)=="boolean" then K.config.autoBackpack=c.autoBackpack end
      if c.tempoSource=="walker" or c.tempoSource=="courier" then K.config.tempoSource=c.tempoSource
      elseif tonumber(c.delay) and tonumber(c.delay)~=0.35 then K.config.tempoSource="courier" end
    end
    if type(saved.customRoutes)=="table" then
      for key,r in pairs(saved.customRoutes) do if K:addRoute(r) then K.customRoutes[key]=r end end
    end
  end
  return K
end
