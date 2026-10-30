-- Run from the pristine upstream 5.0.0-beta.13 checkout.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local fixtures=dofile("../chimera-kurier/tests/fixtures.lua")
local routes=dofile("../chimera-kurier/src/routes.lua").routes
local extra=dofile("../chimera-native/tests/new_fixtures.lua")
for name,r in pairs(dofile("../chimera-native/data/new_static.lua").routes) do routes[name]=r;fixtures.routes[name]=extra.routes[name] end
for _,b in ipairs(extra.boards) do fixtures.boards[#fixtures.boards+1]=b end
local inverse={n="s",s="n",e="w",w="e",nw="se",ne="sw",se="nw",sw="ne",u="d",d="u"}
T.module("test.walker",function()
    return {name="walker",setup=function(ctx)
        return {stop=function(reason) ctx:emit("chimera.walk.stopped",{reason=reason}) end,
            resolve=function() return nil,"not used by courier" end,go=function() error("not used") end,cost=function() return 1 end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,name in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua","scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua","postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name))
    end
end
local function start()
    local app=T.start({"chimera.core.cli","chimera.gmcp","chimera.world","chimera.mapper","chimera.terrain",
        "chimera.locations","test.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    -- Upstream's stub records send(), while Mudlet also raises this event.
    -- Add that documented wire behaviour for the integration tests.
    local wire=send
    _G.send=function(command,...)
        local before=M.denied
        raiseEvent("sysDataSendRequest",command)
        if M.denied==before then wire(command,...) end
    end
    -- Legacy route scenarios explicitly disable automatic backpack discovery.
    -- Dedicated inventory suites cover the production default separately.
    record.api.engine.config.autoBackpack=false;record.api.engine:save()
    return app,app.loader.records.bots.api,record.api.engine
end
local home=fixtures.routes["Henry Schmidt"].backward[13]
local function feed(lines) for _,text in ipairs(lines) do M.line(text) end end
local function nextSend()
    local n=#M.sent
    for _=1,30 do
        M.advance(0.1)
        if #M.sent>n then return M.sent[#M.sent] end
    end
    error("expected a send; output: "..M.text())
end
local function begin(command)
    M.input(command or "/bot paczki"); T.eq("zerknij",M.sent[#M.sent]);feed(home);T.eq("przeczytaj tablice",nextSend())
end
local function singleBoard(name)
    for _,board in ipairs(fixtures.boards) do for _,line in ipairs(board) do
        if line:find(name,1,true) and line:find("miejscowa",1,true) then return {board[1],line,board[#board]} end
    end end
end

T.test("discovery through native plugin folder and Boty registry; no automatic start",function()
    local app,bots,C=start()
    T.eq("chimera_paczki",app.plugin_list[1].name);T.eq(nil,bots.status());T.eq("stopped",C.mode)
    M.clear_output();M.input("/bot");T.contains(M.text(),"[paczki]")
    T.contains(M.text(),"Ustawienia: /paczki")
    T.ok(app.commands.by_name.paczki~=nil);T.eq(nil,app.commands.by_name.kozo)
end)
T.test("native configuration panel and a single parcel button",function()
    local app,bots,C=start();M.input("/paczki");T.contains(M.text(),"Boty / Paczki")
    M.click("[1 paczka]");T.eq(1,C.stopAt);T.eq("running",C.mode);T.ok(bots.status()~=nil)
end)
for name,route in pairs(routes) do
    T.test("native /bot coroutine completes real round trip: "..name,function()
        local app,bots,C=start();begin("/paczki start 1")
        feed(singleBoard(name));nextSend();M.line(fixtures.routes[name].pickup)
        for i,cmd in ipairs(route.commands) do T.eq(cmd,nextSend());feed(fixtures.routes[name].forward[i]) end
        T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
        M.line(fixtures.routes[name].handover);M.line(fixtures.routes[name].receipt)
        for i,raw in ipairs(fixtures.routes[name].backward) do T.eq(inverse[route.commands[#route.commands-i+1]],nextSend());feed(raw) end
        M.advance(0.5);T.eq("stopped",C.mode);T.eq("home",C.node);T.eq(1,C.stats.delivered);T.eq(nil,bots.status())
        T.contains(M.text(),"Bot paczki zakonczony.");T.eq(0,#app.errors,M.text())
    end)
end
T.test("native common STOP cancels already scheduled courier movement",function()
    local app,bots,C=start();begin();feed(singleBoard("Henry Schmidt"));nextSend();M.line(fixtures.routes["Henry Schmidt"].pickup)
    local n=#M.sent;M.input("/bot stop");M.advance(30)
    T.eq(nil,bots.status());T.eq("stopped",C.mode);T.eq(n,#M.sent);T.eq(nil,next(C.timers))
end)
T.test("native one-bot policy does not start courier alongside another coroutine",function()
    local app,bots,C=start();bots.register("inny",function(b) b.czekaj(50) end)
    M.input("/bot inny");M.input("/paczki start");T.eq("stopped",C.mode)
    T.contains(bots.status(),"Bot inny");T.not_contains(table.concat(M.sent,"|"),"zerknij")
end)
T.test("native low HP, teleport, numpad and fight events cancel courier timers",function()
    for _,kind in ipairs({"hp","teleport","key","fight"}) do
        local app,bots,C=start();begin();local n=#M.sent
        if kind=="hp" then app.bus:emit("chimera.char.low",{what="hp",value=20,threshold=30})
        elseif kind=="teleport" then app.bus:emit("chimera.room.changed",{id="elsewhere",how="przeniesienie"})
        elseif kind=="key" then app.bus:emit("chimera.numpad.pressed","n")
        elseif kind=="fight" then app.bus:emit("chimera.fight.started",{room="here",enemies={"ork"}}) end
        M.advance(30);T.eq(nil,bots.status());T.ok(C.mode=="paused" or C.mode=="stopped");T.eq(n,#M.sent);T.eq(nil,next(C.timers))
    end
end)
T.test("fatigue keeps a late static move ACK and resumes an otherwise ambiguous room",function()
    local app,bots,C=start();local name="Henry Schmidt";local route=routes[name];local f=fixtures.routes[name]
    begin("/paczki start 1");feed(singleBoard(name));nextSend();M.line(f.pickup)
    for index=1,9 do T.eq(route.commands[index],nextSend());feed(f.forward[index]) end
    T.eq(route.commands[10],nextSend());T.eq("move",C.pending.kind)
    local target,room=C.pending.target,C.pending.expected
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=85})
    T.eq("resting",C.mode);T.ok(bots.status()~=nil);T.eq(nil,C.node);T.eq(1,C.stopAt)
    local guessed,matches=C:localize(room)
    T.eq(nil,guessed);T.ok(matches and matches>1,"test room must be ambiguous without the expected-step ACK")
    local before=#M.sent
    M.advance(1.2);feed(f.forward[10])
    T.eq("resting",C.mode);T.eq(target,C.node);T.eq(nil,C.restState.staticMove)
    T.eq(before,#M.sent,"late ACK must never start another movement during rest")
    M.advance(9);T.eq(before+1,#M.sent);T.eq("stan",M.sent[#M.sent]);T.eq("resting",C.mode)
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=20})
    T.eq("zerknij",nextSend());feed(f.forward[10])
    T.eq(route.commands[11],nextSend());T.eq("running",C.mode)
    T.eq(target.."/"..route.commands[11],C.pending.target,"resume must advance from the confirmed node")
    T.eq(name,C.job.name);T.eq(1,C.stopAt);T.ok(bots.status()~=nil)
    M.input("/bot stop");local stopped=#M.sent;M.advance(30)
    T.eq(stopped,#M.sent);T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("own directional sends are classified by native numpad as steps, not teleports",function()
    local app,bots,C=start()
    M.packet("Room.Info",{id="6f2c03461c2f1438",name="Poczta",exits={nw="street"}})
    begin();feed(singleBoard("Henry Schmidt"));nextSend();M.line(fixtures.routes["Henry Schmidt"].pickup)
    T.eq("nw",nextSend())
    M.packet("Room.Info",{id="street",name="Ulica",exits={se="6f2c03461c2f1438"}})
    T.eq("running",C.mode,M.text());T.ok(bots.status()~=nil);feed(fixtures.routes["Henry Schmidt"].forward[1])
    T.eq("e",nextSend())
end)
T.test("reload via actual loader removes the old courier and preserves native saved settings",function()
    local app,bots,C=start();M.input("/paczki limit 1.5");M.input("/paczki tryb lekkie");M.input("/paczki poczty stop");begin()
    local aliases,triggers=M.count("aliases"),M.count("triggers")
    local ok=app.loader:reload({"kurier_paczki"});T.ok(ok~=false,M.text())
    local new=app.loader.records.kurier_paczki.api.engine
    T.eq(nil,bots.status());T.eq("stopped",C.mode);T.eq("stopped",new.mode)
    T.eq(1.5,new.config.maxKg);T.eq("intercity_first",new.config.strategy);T.eq(false,new.config.roam)
    T.eq(aliases,M.count("aliases"));T.eq(triggers,M.count("triggers"));T.eq(0,#app.errors,M.text())
    M.clear_output();M.input("/bot");T.contains(M.text(),"[paczki]")
end)
T.test("native session end stops courier; helper commands stay under /paczki",function()
    local app,bots,C=start();begin();local n=#M.sent
    app.bus:emit("chimera.session.end");M.advance(30);T.eq(n,#M.sent);T.eq(nil,bots.status())
    M.clear_output();M.input("/paczki pomoc");T.contains(M.text(),"/paczki start");T.not_contains(M.text(),"/kurier")
end)
T.run()
