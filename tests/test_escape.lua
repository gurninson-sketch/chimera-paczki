-- texlua tests/test_escape.lua (cwd chimera-native)
local script=arg[0]:gsub("\\", "/")
local root=script:match("^(.*)/tests/test_escape%.lua$") or "."
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/escape.lua")
local passed,assertions=0,0
local function eq(expected,actual,why)
    assertions=assertions+1
    assert(expected==actual,(why or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(name,body)
    local ok,problem=pcall(body)
    if not ok then error(name..": "..tostring(problem),0) end
    passed=passed+1;print("OK "..name)
end
local function setup()
    local s={now=0,map=4,hashes={[1]="junction",[2]="trail",[3]="cub",[4]="bear",[5]="elsewhere"},
        room={id="bear",key="bear",name="Gdzies w Gorach Szarych.",exits={poludnie="cub",polnoc="elsewhere"}},
        character={name="Yarrim",id="self"},allowed=true,connected=true,timers={},events={},handlers={},triggers={},
        cleanups={},sent={},results={},order=0}
    local ctx={}
    function ctx:on(event,callback)
        s.handlers[event]=s.handlers[event] or {};table.insert(s.handlers[event],callback)
    end
    function s.emit(event,...)
        for _,callback in ipairs(s.handlers[event] or {}) do callback(...) end
    end
    function ctx:emit(event,data)
        table.insert(s.events,{event=event,data=data});s.emit(event,data)
    end
    function ctx:trigger(_,callback) table.insert(s.triggers,callback) end
    function s.line(text) for _,callback in ipairs(s.triggers) do callback(text) end end
    function ctx:timer(delay,callback)
        s.order=s.order+1;local timer={at=s.now+delay,callback=callback,order=s.order};s.timers[timer]=true;return timer
    end
    function ctx:cancel(timer) s.timers[timer]=nil end
    function ctx:cleanup(callback) table.insert(s.cleanups,callback) end
    function s.cleanup() for _,callback in ipairs(s.cleanups) do callback() end end
    function s.advance(seconds)
        local limit=s.now+seconds
        while true do
            local first
            for timer in pairs(s.timers) do
                if timer.at<=limit and (not first or timer.at<first.at or timer.at==first.at and timer.order<first.order) then first=timer end
            end
            if not first then break end
            s.now=first.at;s.timers[first]=nil;first.callback()
        end
        s.now=limit
    end
    function s.arrive(map,exits)
        s.room={id=s.hashes[map],key=s.hashes[map],name="Previous road",exits=exits or {polnoc="bear"}}
        s.emit("chimera.room.info",s.room)
        s.map=map;s.emit("chimera.mapper.moved",map,s.room)
    end
    s.proof={fromId="cub",fromMap=3,toId="bear",toMap=4}
    s.api=create(ctx,{
        gmcp={room=function() return s.room end,char=function() return s.character end,connected=function() return s.connected end},
        mapper={current_room=function() return s.map end,chimera_id=function(map) return s.hashes[map] end},
        allow=function() return s.allowed end,
        send=function(command)
            table.insert(s.sent,command)
            if s.onSend then return s.onSend(command) end
            return true
        end,
        onDone=function(result) table.insert(s.results,result);if s.onDone then s.onDone(result) end end,
    })
    return s
end

test("bear attack immediately sends the live reverse exit and waits for mapper acknowledgement",function()
    local s=setup()
    eq(true,s.api.start(s.proof));eq("s",s.sent[1]);eq(1,#s.sent);eq(true,s.api.active());eq("escaping",s.api.phase())
    eq("chimera.walk.started",s.events[1].event);eq(true,s.events[1].data.emergency)
    s.room={id="cub",key="cub",exits={polnoc="bear"}};s.emit("chimera.room.info",s.room)
    eq(0,#s.results,"Room.Info precedes mapper update")
    s.map=3;s.emit("chimera.mapper.moved",3,s.room)
    eq(false,s.api.active());eq(true,s.results[1].ok);eq(1,s.results[1].attempts)
    eq("chimera.walk.arrived",s.events[2].event);eq("cub",s.events[2].data.target)
    s.advance(60);eq(1,#s.results);eq(1,#s.sent);eq(nil,next(s.timers))
end)
test("duplicate combat requests never queue a second escape",function()
    local s=setup();eq(true,s.api.start(s.proof));eq(false,s.api.start(s.proof));eq(false,s.api.start(s.proof))
    eq(1,#s.sent);s.arrive(3);eq(1,#s.results);eq(1,#s.sent)
end)
test("no reply times out once and does not guess or repeat the step",function()
    local s=setup();s.api.start(s.proof);s.advance(4.9);eq(true,s.api.active());eq(1,#s.sent)
    s.advance(0.2);eq(false,s.api.active());eq(false,s.results[1].ok);eq(1,s.results[1].attempts)
    s.advance(60);eq(1,#s.sent);eq(1,#s.results);eq(nil,next(s.timers))
end)
test("unverified or stale edge proof cannot issue any command",function()
    for _,mutate in ipairs({
        function(s) s.proof=nil end,
        function(s) s.proof.toId="old" end,
        function(s) s.proof.fromId="different" end,
        function(s) s.proof.fromMap=4 end,
        function(s) s.proof.fromMap=-1 end,
        function(s) s.hashes[3]="changed" end,
        function(s) s.map=5 end,
        function(s) s.room.id="elsewhere" end,
        function(s) s.connected=false end,
    }) do
        local s=setup();mutate(s);eq(false,s.api.start(s.proof));eq(0,#s.sent);eq(false,s.api.active());eq(0,#s.results)
    end
end)
test("reverse command comes from GMCP rather than a guessed inverse",function()
    local s=setup();s.room.exits={zachod="cub"};eq(true,s.api.start(s.proof));eq("w",s.sent[1]);s.arrive(3);eq(true,s.results[1].ok)
end)
test("special exits and unknown targets do not authorize a retreat",function()
    for _,exits in ipairs({{["wespnij sie"]="cub"},{["wsiadz na prom"]="cub"},{["s;zabij niedzwiedzice"]="cub"},
        {["s\nkill bear"]="cub"},{poludnie=false},{poludnie="elsewhere"},{}}) do
        local s=setup();s.room.exits=exits;eq(false,s.api.start(s.proof));eq(0,#s.sent)
    end
end)
test("Polish and long direction forms normalize to a single ordinary command",function()
    for command,expected in pairs({["północny-zachód"]="nw",south="s",up="u",down="d"}) do
        local s=setup();s.room.exits={[command]="cub"};eq(true,s.api.start(s.proof));eq(expected,s.sent[1])
    end
end)
test("another character fighting does nothing unless the owner explicitly starts a retreat",function()
    local s=setup();s.emit("chimera.combat.state",{primary="",relations={{attacker="other",defender="enemy"}}})
    s.advance(60);eq(0,#s.sent);eq(0,#s.results);eq(false,s.api.active())
end)
test("a synchronous ownership revocation before send prevents the emergency command",function()
    local s=setup();s.emit("chimera.bots.changed",nil);s.allowed=false
    eq(false,s.api.start(s.proof));eq(0,#s.sent)
    s=setup();s.handlers["chimera.walk.started"]={function() s.allowed=false end}
    eq(false,s.api.start(s.proof));eq(0,#s.sent);eq(false,s.api.active());eq(false,s.results[1].ok)
end)
test("a changed live exit during event dispatch prevents the emergency command",function()
    local s=setup();s.handlers["chimera.walk.started"]={function() s.room.exits={poludnie="elsewhere"} end}
    eq(false,s.api.start(s.proof));eq(0,#s.sent);eq(false,s.api.active());eq(false,s.results[1].ok)
end)
test("synchronous exact acknowledgement finishes only once",function()
    local s=setup();s.onSend=function() s.arrive(3);return true end
    eq(true,s.api.start(s.proof));eq(1,#s.sent);eq(1,#s.results);eq(true,s.results[1].ok);eq(false,s.api.active())
    s.advance(60);eq(1,#s.results);eq(nil,next(s.timers))
end)
test("native nested mapper callback may arrive before this module's Room.Info listener",function()
    local s=setup();s.api.start(s.proof)
    -- GMCP stores the new packet, then an earlier mapper listener emits moved
    -- before escape's own listener gets its turn in the outer Room.Info event.
    s.room={id="cub",key="cub",exits={polnoc="bear"}};s.map=3
    s.emit("chimera.mapper.moved",3,s.room)
    eq(false,s.api.active());eq(1,#s.results);eq(true,s.results[1].ok)
    s.emit("chimera.room.info",s.room);s.advance(60)
    eq(1,#s.results);eq(1,#s.sent);eq(nil,next(s.timers))
end)
test("a standalone forged mapper movement cannot replace current GMCP confirmation",function()
    local s=setup();s.api.start(s.proof)
    s.emit("chimera.mapper.moved",3,{id="cub",key="cub"})
    eq(false,s.api.active());eq(1,#s.results);eq(false,s.results[1].ok);eq(1,#s.sent)
end)
test("send failure releases the emergency marker without retry",function()
    for _,raise in ipairs({false,true}) do
        local s=setup();s.onSend=function() if raise then error("network") end;return false end
        eq(false,s.api.start(s.proof));eq(false,s.api.active());eq(1,#s.results);eq(false,s.results[1].ok)
        s.advance(60);eq(1,#s.sent);eq(nil,next(s.timers))
    end
end)
test("unexpected room, instance and broken mapper acknowledgement cancel the retreat",function()
    for _,change in ipairs({
        function(s) s.arrive(5) end,
        function(s) s.room.key="bear#2";s.emit("chimera.room.info",s.room) end,
        function(s) s.room={id="cub",key="cub",exits={}};s.emit("chimera.room.info",s.room);s.hashes[3]="changed";s.map=3;s.emit("chimera.mapper.moved",3,s.room) end,
    }) do
        local s=setup();s.api.start(s.proof);change(s);eq(false,s.api.active());eq(false,s.results[1].ok)
        s.advance(60);eq(1,#s.sent);eq(1,#s.results)
    end
end)
test("manual controls, disconnect, session, map loss and cleanup cancel all pending work",function()
    for _,event in ipairs({"sysDataSendRequest","chimera.numpad.pressed","chimera.step.manual","chimera.locations.key",
        "chimera.session.end","sysDisconnectionEvent","chimera.mapper.lost","cleanup"}) do
        local s=setup();s.api.start(s.proof)
        if event=="cleanup" then s.cleanup() else s.emit(event,"n") end
        eq(false,s.api.active(),event);eq(false,s.results[1].ok,event);eq(nil,next(s.timers),event)
        s.arrive(3);s.advance(60);eq(1,#s.results,event);eq(1,#s.sent,event)
        if event=="cleanup" then eq(false,s.api.start(s.proof)) end
    end
end)
test("own send event is scoped and cannot cancel itself",function()
    local s=setup();s.onSend=function(command) s.emit("sysDataSendRequest",nil,command);return true end
    eq(true,s.api.start(s.proof));eq(true,s.api.active());eq(0,#s.results);s.arrive(3);eq(true,s.results[1].ok)
end)
test("character identity change cancels and a repeated same character does not",function()
    local s=setup();s.api.start(s.proof);s.emit("chimera.char.info",{name="Yarrim",id="self"});eq(true,s.api.active())
    s.emit("chimera.char.info",{name="Inny",id="other"});eq(false,s.api.active());eq(false,s.results[1].ok)
    s.arrive(3);s.advance(60);eq(1,#s.results);eq(1,#s.sent)
end)
test("death confirmation cancels immediately and other death narration does not",function()
    local s=setup();s.api.start(s.proof);s.line("Niedzwiedzica umiera.");eq(true,s.api.active())
    s.line("\27[31mUmierasz.\27[0m");eq(false,s.api.active());eq(false,s.results[1].ok)
    s.advance(60);eq(1,#s.sent);eq(nil,next(s.timers))
end)
test("explicit cancellation is idempotent and never invokes automatic delivery continuation",function()
    local s=setup();s.api.start(s.proof);eq(true,s.api.cancel("/bot stop"));eq(false,s.api.cancel("again"))
    eq(1,#s.results);eq("/bot stop",s.results[1].reason);eq(false,s.results[1].ok);eq("idle",s.api.phase())
    s.arrive(3);s.advance(60);eq(1,#s.sent);eq(1,#s.results)
end)
print(string.format("PASS: %d scenarios, %d assertions",passed,assertions))
