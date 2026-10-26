-- Uses the actual beta.13 Context and Bus with independent numeric ID domains.
-- Run from chimera-native, e.g. tools/run_lua.py tests/test_scope.lua.
package.path="../chimera-main/src/?.lua;../chimera-main/src/?/init.lua;"..package.path
local Context=require("chimera.core.context")
local Bus=require("chimera.core.bus")
local create=dofile("chimera_wtyczki/chimera_paczki/scope.lua")
local tests,checks=0,0
local function check(value,message) checks=checks+1;assert(value,message or "check failed") end
local function eq(a,b,message) check(a==b,(message or "different values")..": "..tostring(a).." ~= "..tostring(b)) end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end

local function setup()
    local s={time=0,timers={},timerArchive={},events={},triggers={},errors={},sent={},saved={},
        timerSeq=0,eventSeq=0,triggerSeq=0,killedTimers={},killedTriggers={}}
    _G.tempTimer=function(seconds,fn,repeating)
        s.timerSeq=s.timerSeq+1;local id=s.timerSeq
        s.timers[id]={at=s.time+seconds,fn=fn,every=repeating and seconds or nil};s.timerArchive[id]=fn
        return id
    end
    _G.killTimer=function(id) s.killedTimers[#s.killedTimers+1]=id;s.timers[id]=nil;return true end
    _G.registerAnonymousEventHandler=function(event,fn)
        s.eventSeq=s.eventSeq+1;s.events[s.eventSeq]={event=event,fn=fn};return s.eventSeq
    end
    _G.killAnonymousEventHandler=function(id) s.events[id]=nil;return true end
    local function trigger(pattern,fn)
        s.triggerSeq=s.triggerSeq+1;s.triggers[s.triggerSeq]={pattern=pattern,fn=fn};return s.triggerSeq
    end
    _G.tempTrigger=trigger;_G.tempBeginOfLineTrigger=trigger;_G.tempExactMatchTrigger=trigger;_G.tempRegexTrigger=trigger
    _G.killTrigger=function(id) s.killedTriggers[#s.killedTriggers+1]=id;s.triggers[id]=nil;return true end
    _G.send=function(command,echo) s.sent[#s.sent+1]={command=command,echo=echo} end
    local bus=Bus.new(function(_,_,problem) s.errors[#s.errors+1]=problem end);bus.mirror=false;s.bus=bus
    local dependency={value="native API"}
    local app={bus=bus,config={view=function() return {} end},
        loader={records={dependency={status="running",api=dependency}}},storage={}}
    function app:report_error(_,_,problem) s.errors[#s.errors+1]=problem end
    function app.storage:get_state(name,key) return s.saved[name..":"..key] end
    function app.storage:set_state(name,key,value) s.saved[name..":"..key]=value end
    local original=Context.new(app,{name="kurier_paczki",state={marker=true},spec={deps={"dependency"}}})
    s.original=original;s.ctx=create(original)
    function s.advance(seconds)
        local ending=s.time+seconds
        while true do
            local selected,earliest
            for id,timer in pairs(s.timers) do
                if timer.at<=ending and (not earliest or timer.at<earliest or timer.at==earliest and id<selected) then selected,earliest=id,timer.at end
            end
            if not selected then break end
            s.time=earliest;local timer=s.timers[selected]
            if timer.every then timer.at=s.time+timer.every else s.timers[selected]=nil end
            timer.fn()
        end
        s.time=ending
    end
    function s.event(event,...)
        local ids={};for id,handler in pairs(s.events) do if handler.event==event then ids[#ids+1]=id end end;table.sort(ids)
        for _,id in ipairs(ids) do if s.events[id] then s.events[id].fn(event,...) end end
    end
    return s
end

test("upstream raw cancellation reproduces the ID-domain collision",function()
    local s=setup();local calls=0
    local bus=s.original:on("chimera.raw",function() calls=calls+1 end)
    local timer=s.original:timer(10,function() end)
    eq(bus,timer,"independent bus and timer domains both issue ID 1")
    check(s.original:cancel(bus));eq(count(s.timers),0,"wrongly cancelled timer in original Context")
    s.bus:emit("chimera.raw");eq(calls,1,"original raw cancel left the bus callback alive")
end)
test("four identical raw numeric IDs are isolated by distinct lease tables",function()
    local s=setup();local c=s.ctx;local events,timers,triggers=0,0,0
    local bus=c:on("chimera.same",function() events=events+1 end)
    local timer=c:timer(10,function() timers=timers+1 end)
    local trigger=c:trigger("^",function() triggers=triggers+1 end)
    local event=c:on("sysDataSendRequest",function() events=events+10 end)
    for _,token in ipairs({bus,timer,trigger,event}) do eq(type(token),"table");eq(token.active,true) end
    check(bus~=timer and bus~=trigger and trigger~=event)
    eq(s.bus.next_id,1);eq(s.timerSeq,1);eq(s.triggerSeq,1);eq(s.eventSeq,1)
    check(c:cancel(bus));eq(bus.active,false);eq(count(s.timers),1);eq(count(s.triggers),1);eq(count(s.events),1)
    s.bus:emit("chimera.same");eq(events,0)
    check(c:cancel(trigger));eq(count(s.triggers),0);eq(count(s.timers),1);eq(count(s.events),1)
    s.event("sysDataSendRequest","n");eq(events,10)
    s.advance(10);eq(timers,1);eq(timer.active,false);eq(triggers,0)
    check(c:cancel(event));eq(count(s.events),0);eq(count(s.timers),0)
end)
test("many colliding events and timers cancel only their own resources",function()
    local s=setup();local bus,timers={},{};local eventCalls,timerCalls=0,0
    for i=1,20 do
        bus[i]=s.ctx:on("chimera.many",function() eventCalls=eventCalls+1 end)
        timers[i]=s.ctx:timer(5,function() timerCalls=timerCalls+1 end)
    end
    for i=1,20,2 do check(s.ctx:cancel(bus[i])) end
    eq(count(s.timers),20);eq(s.bus:count("chimera.many"),10)
    for i=2,20,2 do check(s.ctx:cancel(timers[i])) end
    eq(count(s.timers),10);eq(s.bus:count("chimera.many"),10)
    s.bus:emit("chimera.many");eq(eventCalls,10);s.advance(5);eq(timerCalls,10)
    eq(count(s.timers),0);eq(s.bus:count("chimera.many"),10)
end)
test("a callback already in a Bus snapshot is inert after cancellation",function()
    local s=setup();local calls=0;local second
    s.ctx:on("chimera.snapshot",function() s.ctx:cancel(second) end)
    second=s.ctx:on("chimera.snapshot",function() calls=calls+1 end)
    s.bus:emit("chimera.snapshot");eq(calls,0);eq(second.active,false)
    s.bus:emit("chimera.snapshot");eq(calls,0)
end)
test("fired timer cannot forget or cancel a later colliding registration",function()
    local s=setup();local timers,events=0,0
    local timer=s.ctx:timer(1,function() timers=timers+1 end)
    s.advance(1);eq(timers,1);eq(timer.active,false)
    local event=s.ctx:on("chimera.after",function() events=events+1 end)
    eq(s.bus.next_id,1);eq(s.timerSeq,1)
    s.timerArchive[1]();eq(timers,1);eq(s.ctx:cancel(timer),false)
    s.bus:emit("chimera.after");eq(events,1);eq(event.active,true)
    eq(s.original:count("bus"),1);eq(s.original:count("timer"),0)
end)
test("cancelled timer and trigger callbacks remain inert if the host dequeued them",function()
    local s=setup();local calls=0
    local timer=s.ctx:timer(1,function() calls=calls+1 end)
    local trigger=s.ctx:trigger_substring("x",function() calls=calls+10 end)
    local timerFn=s.timerArchive[1];local triggerFn=s.triggers[1].fn
    s.ctx:cancel(timer);s.ctx:cancel(trigger);timerFn();triggerFn();eq(calls,0)
    eq(next(s.timers),nil);eq(next(s.triggers),nil)
end)
test("repeating timer keeps its lease until explicitly cancelled",function()
    local s=setup();local calls=0;local timer
    timer=s.ctx:timer(1,function() calls=calls+1;if calls==3 then s.ctx:cancel(timer) end end,true)
    s.advance(10);eq(calls,3);eq(timer.active,false);eq(count(s.timers),0)
    s.timerArchive[1]();eq(calls,3)
end)
test("scope cleanup runs callbacks once in reverse order and cancels every domain",function()
    local s=setup();local calls,order=0,{}
    local timer=s.ctx:timer(100,function() calls=calls+1 end)
    local bus=s.ctx:on("chimera.cleanup",function() calls=calls+10 end)
    local event=s.ctx:on("sys",function() calls=calls+100 end)
    local trigger=s.ctx:trigger_exact("line",function() calls=calls+1000 end)
    local originalTimer=s.timerArchive[1]
    local cleanup=s.ctx:cleanup(function() order[#order+1]="first";s.bus:emit("chimera.cleanup") end)
    s.ctx:cleanup(function() order[#order+1]="second";s.ctx:cancel(timer) end)
    s.original:dispose()
    eq(table.concat(order,","),"second,first");eq(calls,0);eq(count(s.timers),0)
    eq(count(s.events),0);eq(count(s.triggers),0);eq(s.bus:count("chimera.cleanup"),0)
    eq(#s.original.handles,0);eq(timer.active,false);eq(bus.active,false);eq(event.active,false);eq(trigger.active,false)
    originalTimer();eq(calls,0);eq(s.ctx:cancel(cleanup),false)
    s.original:dispose();eq(#order,2);eq(#s.errors,0)
    eq(pcall(function() s.ctx:timer(1,function() end) end),false,"closed scopes reject new resources")
end)
test("user cleanup cancellation invokes its callback exactly once",function()
    local s=setup();local calls=0
    local token=s.ctx:cleanup(function() calls=calls+1 end)
    check(s.ctx:cancel(token));eq(calls,1);eq(s.ctx:cancel(token),false)
    s.original:dispose();eq(calls,1)
end)
test("delegated methods bind the original Context and share its data",function()
    local s=setup();local c=s.ctx
    eq(c.app,s.original.app);eq(c.log,s.original.log);eq(c.state,s.original.state)
    eq(c:use("dependency").value,"native API")
    eq(c:saved("missing",false),false);c:save("answer",42);eq(c:saved("answer"),42)
    eq(s.saved["kurier_paczki:answer"],42)
    c:send("n",true);eq(s.sent[1].command,"n");eq(s.sent[1].echo,false)
    c.someField="shared";eq(s.original.someField,"shared")
    s.original.onlyOriginalSelf=function(self,value) eq(self,s.original);return value end
    eq(c:onlyOriginalSelf("ok"),"ok");eq(c.onlyOriginalSelf("dot"),"dot")
end)
test("raw event arguments and all trigger variants retain the Context contract",function()
    local s=setup();local received
    s.ctx:on("sysDataSendRequest",function(...) received={n=select("#",...),...} end)
    s.event("sysDataSendRequest","n",nil,"tail")
    eq(received.n,4);eq(received[1],"sysDataSendRequest");eq(received[2],"n");eq(received[3],nil);eq(received[4],"tail")
    local calls=0;local tokens={s.ctx:trigger_begin("start",function() calls=calls+1 end),
        s.ctx:trigger_exact("exact",function() calls=calls+1 end),
        s.ctx:make_trigger("regex","^",function() calls=calls+1 end)}
    for _,trigger in pairs(s.triggers) do trigger.fn() end;eq(calls,3)
    for _,token in ipairs(tokens) do check(s.ctx:cancel(token)) end
    eq(count(s.triggers),0)
end)
test("numeric raw IDs are refused while delegated unique table handles can be cancelled",function()
    local s=setup();local calls=0
    s.ctx:on("chimera.foreign",function() calls=calls+1 end)
    s.ctx:timer(1,function() calls=calls+10 end)
    eq(s.ctx:cancel(1),false);eq(count(s.timers),1);eq(s.bus:count("chimera.foreign"),1)
    local foreign={kind="command"}
    s.original:track("command",foreign,function() calls=calls+100 end)
    check(s.ctx:cancel(foreign));eq(calls,100);eq(s.ctx:cancel(foreign),false)
    eq(s.ctx:cancel({}),false);eq(s.ctx:cancel(nil),false)
end)
test("timer errors are logged by the original Context after retiring the lease",function()
    local s=setup();local timer=s.ctx:timer(1,function() error("expected timer failure") end)
    s.advance(1);eq(timer.active,false);eq(count(s.timers),0);eq(#s.errors,1)
    check(s.errors[1]:find("expected timer failure",1,true)~=nil)
    s.timerArchive[1]();eq(#s.errors,1)
end)

print(string.format("Resource scope: %d tests, %d assertions passed",tests,checks))
