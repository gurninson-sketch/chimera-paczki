-- texlua tests/test_recovery.lua (cwd chimera-native)
local script=arg[0]:gsub("\\", "/")
local root=script:match("^(.*)/tests/test_recovery%.lua$") or "."
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/recovery.lua")
local passed,assertions=0,0
local function eq(expected,actual,why)
    assertions=assertions+1
    assert(expected==actual,(why or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(label,callback)
    local ok,problem=pcall(callback);if not ok then error(label..": "..tostring(problem),0) end
    passed=passed+1;print("OK "..label)
end
local function setup()
    local s={now=0,map=3,hashes={[3]="road",[4]="bear"},room={id="road",key="road",exits={polnoc="bear"}},
        character={name="Yarrim",id="self"},allowed=true,connected=true,timers={},handlers={},triggers={},cleanups={},sent={},
        failures={},ready=0,refresh=0,readyResult=true,limits={hp=80,start=20},order=0}
    local ctx={}
    function ctx:on(event,callback) s.handlers[event]=s.handlers[event] or {};table.insert(s.handlers[event],callback) end
    function s.emit(event,...) for _,callback in ipairs(s.handlers[event] or {}) do callback(...) end end
    function ctx:timer(delay,callback)
        s.order=s.order+1;local t={at=s.now+delay,callback=callback,order=s.order};s.timers[t]=true;return t
    end
    function ctx:cancel(t) s.timers[t]=nil end
    function ctx:trigger(_,callback) table.insert(s.triggers,callback) end
    function s.line(text) for _,callback in ipairs(s.triggers) do callback(text) end end
    function ctx:cleanup(callback) table.insert(s.cleanups,callback) end
    function s.cleanup() for _,callback in ipairs(s.cleanups) do callback() end end
    function s.advance(seconds)
        local ending=s.now+seconds
        while true do
            local first
            for t in pairs(s.timers) do
                if t.at<=ending and (not first or t.at<first.at or t.at==first.at and t.order<first.order) then first=t end
            end
            if not first then break end
            s.now=first.at;s.timers[first]=nil;first.callback()
        end
        s.now=ending
    end
    function s.vitals(hp,fatigue) s.emit("chimera.char.vitals",{hp=hp,fatigue=fatigue}) end
    function s.combat(primary,relations,room) s.emit("chimera.combat.state",{room=room or s.room.id,primary=primary or "",relations=relations or {}}) end
    s.api=create(ctx,{
        gmcp={room=function() return s.room end,char=function() return s.character end,connected=function() return s.connected end},
        mapper={current_room=function() return s.map end,chimera_id=function(map) return s.hashes[map] end},
        allow=function() return s.allowed end,limits=function() return s.limits end,
        send=function(command) table.insert(s.sent,{command=command,time=s.now});if s.onSend then return s.onSend(command) end;return true end,
        refreshCombat=function() s.refresh=s.refresh+1 end,
        onReady=function() s.ready=s.ready+1;if s.onReady then return s.onReady() end;return s.readyResult end,
        onFailure=function(reason) table.insert(s.failures,reason) end,
    })
    return s
end
test("fresh clear and healthy vitals resume autonomously after one quiet second",function()
    local s=setup();eq(true,s.api.start());eq("stan",s.sent[1].command);eq(true,s.api.active())
    s.combat();s.vitals(80,20);s.advance(0.99);eq(0,s.ready)
    s.advance(0.02);eq(0,s.ready,"callback is outside nested combat dispatch")
    s.advance(0.05);eq(1,s.ready);eq(false,s.api.active());eq(nil,next(s.timers));eq(0,#s.failures)
end)
test("cached GMCP is never used without a fresh marker observation",function()
    local s=setup();s.combat();s.vitals(100,0);s.api.start();s.advance(120)
    eq(0,s.ready);eq(true,s.api.active());eq(13,#s.sent);eq(5,s.refresh)
    s.combat();s.vitals(100,0);s.advance(1.1);eq(1,s.ready);eq(false,s.api.active())
end)
test("marker accepts real clear and vitals received before retreat acknowledgement",function()
    local s=setup();local mark=s.api.mark();s.combat();s.vitals(90,10)
    eq(true,s.api.start(mark));s.advance(1.1);eq(1,s.ready);eq(false,s.api.active())
end)
test("marker cannot be forged, replayed, mutated or used for another actor",function()
    local s=setup();eq(false,s.api.start({combat=0,vitals=0}));eq(0,#s.sent)
    local mark=s.api.mark();mark.combat=-999;mark.vitals=-999
    s.api.start(mark);s.advance(2);eq(0,s.ready);s.api.cancel();eq(false,s.api.start(mark))
    mark=s.api.mark();s.character={name="Inny",id="other"};eq(false,s.api.start(mark));eq(1,#s.sent)
end)
test("fresh observations from the old combat room cannot authorize recovery elsewhere",function()
    local s=setup();local mark=s.api.mark();s.combat("",{},"bear");s.vitals(100,0)
    s.api.start(mark);s.advance(2);eq(0,s.ready);s.combat();s.advance(1.1);eq(1,s.ready)
end)
test("own combat invalidates quiet state and requires new vitals after the attack",function()
    local s=setup();s.api.start();s.combat();s.vitals(100,0);s.advance(0.5)
    s.combat("enemy",{{attacker="enemy",defender="self"}});s.advance(2);eq(0,s.ready)
    s.combat();s.advance(2);eq(0,s.ready,"pre-attack health cannot authorize continuation")
    s.vitals(85,10);s.advance(0.1);eq(1,s.ready)
end)
test("self relations block recovery even with an empty primary",function()
    for _,r in ipairs({{attacker="enemy",defender="self"},{attacker="self",defender="enemy"}}) do
        local s=setup();s.api.start();s.combat("",{r});s.vitals(100,0);s.advance(2);eq(0,s.ready)
        s.combat();s.vitals(100,0);s.advance(1.1);eq(1,s.ready)
    end
end)
test("foreign combat does not prevent a healthy recovered courier",function()
    local s=setup();s.api.start();s.combat("",{{attacker="someone",defender="other"}});s.vitals(100,0)
    s.advance(1.1);eq(1,s.ready);eq(false,s.api.active())
end)
test("health and fatigue limits must both be freshly satisfied",function()
    local s=setup();s.limits.start=10;s.api.start();s.combat();s.vitals(79,0);s.advance(2);eq(0,s.ready)
    s.vitals(80,11);s.advance(2);eq(0,s.ready)
    s.emit("chimera.char.vitals",{hp=100});s.advance(2);eq(0,s.ready)
    s.vitals(80,10);s.advance(0.1);eq(1,s.ready)
end)
test("HP recovery never drops below eighty percent even with a lower safety threshold",function()
    local s=setup();s.limits.hp=30;s.api.start();s.combat();s.vitals(50,0);s.advance(2);eq(0,s.ready)
    s.vitals(80,0);s.advance(0.1);eq(1,s.ready)
end)
test("long regeneration has no timeout and only polls bounded stan and combat refresh",function()
    local s=setup();s.api.start();s.combat();s.vitals(10,90);s.advance(600)
    eq(true,s.api.active());eq(0,s.ready);eq(61,#s.sent);eq(21,s.refresh);eq(0,#s.failures)
    for i,entry in ipairs(s.sent) do eq("stan",entry.command);eq((i-1)*10,entry.time) end
    s.vitals(100,0);s.advance(0.1);eq(1,s.ready);eq(false,s.api.active())
end)
test("unavailable route keeps ownership and retries ready callback once every thirty seconds",function()
    local s=setup();s.readyResult=false;s.api.start();s.combat();s.vitals(100,0);s.advance(1.1)
    eq(1,s.ready);eq(true,s.api.active());s.advance(29);eq(1,s.ready)
    s.advance(1);eq(2,s.ready);eq(true,s.api.active())
    s.readyResult=true;s.advance(30);eq(3,s.ready);eq(false,s.api.active());eq(nil,next(s.timers))
end)
test("new damage or attack cancels queued readiness and route retries",function()
    local s=setup();s.readyResult=false;s.api.start();s.combat();s.vitals(100,0);s.advance(1.1);eq(1,s.ready)
    s.vitals(30,0);s.advance(60);eq(1,s.ready);eq(true,s.api.active())
    s.vitals(100,0);s.combat("enemy",{});s.advance(60);eq(1,s.ready)
    s.combat();s.vitals(100,0);s.readyResult=true;s.advance(31.1);eq(2,s.ready);eq(false,s.api.active())
end)
test("manual input and safety lifecycle events cancel pending readiness without any later resume",function()
    for _,event in ipairs({"sysDataSendRequest","chimera.numpad.pressed","chimera.step.manual","chimera.locations.key",
        "chimera.session.end","sysDisconnectionEvent","chimera.mapper.lost"}) do
        local s=setup();s.api.start();s.combat();s.vitals(100,0);s.advance(0.5);s.emit(event,"n")
        eq(false,s.api.active(),event);eq(1,#s.failures,event);s.advance(60);eq(0,s.ready,event);eq(1,#s.sent,event);eq(nil,next(s.timers),event)
    end
end)
test("own stan send event is protected against the manual command guard",function()
    local s=setup();s.onSend=function(c) s.emit("sysDataSendRequest",nil,c);return true end
    eq(true,s.api.start());eq(true,s.api.active());eq(0,#s.failures);s.combat();s.vitals(100,0);s.advance(1.1);eq(1,s.ready)
end)
test("teleport instance change actor switch death and cleanup never resume a saved job",function()
    for _,kind in ipairs({"teleport","instance","map","actor","death","cleanup"}) do
        local s=setup();s.api.start();s.combat();s.vitals(100,0)
        if kind=="teleport" then s.room={id="bear",key="bear"};s.emit("chimera.room.info",s.room)
        elseif kind=="instance" then s.room.key="road#2";s.emit("chimera.room.info",s.room)
        elseif kind=="map" then s.map=4;s.emit("chimera.mapper.moved",4,{id="bear"})
        elseif kind=="actor" then s.character={name="Other",id="other"};s.emit("chimera.char.info",s.character)
        elseif kind=="death" then s.line("Umierasz.") else s.cleanup() end
        eq(false,s.api.active(),kind);s.advance(60);eq(0,s.ready,kind);eq(1,#s.sent,kind);eq(nil,next(s.timers),kind)
        if kind~="cleanup" then eq(1,#s.failures,kind) end
    end
end)
test("loss of ownership and stale mapper cannot trigger a ready callback",function()
    for _,kind in ipairs({"ownership","hash","disconnect"}) do
        local s=setup();s.api.start();s.combat();s.vitals(100,0)
        if kind=="ownership" then s.allowed=false elseif kind=="hash" then s.hashes[3]="different" else s.connected=false end
        s.advance(1.1);eq(0,s.ready,kind);eq(false,s.api.active(),kind);eq(1,#s.failures,kind)
    end
end)
test("silent cancel and failed polling leave no scheduled continuation",function()
    local s=setup();s.api.start();eq(true,s.api.cancel("/bot stop"));eq(false,s.api.cancel());eq(0,#s.failures)
    s.combat();s.vitals(100,0);s.advance(60);eq(0,s.ready);eq(1,#s.sent);eq(nil,next(s.timers))
    s=setup();s.onSend=function() return false end;eq(false,s.api.start());eq(1,#s.failures);eq(false,s.api.active());eq(nil,next(s.timers))
end)
test("ready callback can synchronously transfer its lease and send the first courier action",function()
    local s=setup();s.onReady=function()
        s.emit("sysDataSendRequest",nil,"przeczytaj tablice")
        eq(true,s.api.active(),"handoff remains authorized inside callback")
        return true
    end
    s.api.start();s.combat();s.vitals(100,0);s.advance(1.1)
    eq(1,s.ready);eq(0,#s.failures);eq(false,s.api.active());eq(nil,next(s.timers))
end)
test("an incomplete fresh combat transition invalidates earlier readiness",function()
    for _,packet in ipairs({{primary="enemy",relations={}},{room="road",primary="enemy"},{room="road",relations={}}}) do
        local s=setup();s.api.start();s.combat();s.vitals(100,0);s.advance(0.5)
        s.emit("chimera.combat.state",packet);s.advance(2);eq(0,s.ready);eq(true,s.api.active())
        s.combat();s.vitals(100,0);s.advance(1.1);eq(1,s.ready)
    end
end)
test("configured high health safety margin is clamped to attainable full health",function()
    local s=setup();s.limits.hp=105;s.api.start();s.combat();s.vitals(99,0);s.advance(2);eq(0,s.ready)
    s.vitals(100,0);s.advance(0.1);eq(1,s.ready);eq(false,s.api.active())
end)
print(string.format("PASS: %d scenarios, %d assertions",passed,assertions))
