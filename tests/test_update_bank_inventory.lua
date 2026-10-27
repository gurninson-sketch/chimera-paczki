-- Bank money operations use only an injected sender and exact own receipts.
local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tests/test_update_bank_inventory%.lua$") or "."
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/inventory.lua")
local passed=0
local function eq(expected,actual,why)
    assert(expected==actual,(why or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(name,body)
    local ok,problem=pcall(body)
    if not ok then error(name..": "..tostring(problem),0) end
    passed=passed+1;print("OK "..name)
end
local TAKE="wez monety z swojego plecaka"
local STORE="wloz monety do swojego plecaka"
local OPEN="otworz swoj plecak"
local CLOSE="zamknij swoj plecak"
local TAKEN="Bierzesz wiele srebrnych monet z otwartego skorzanego plecaka."
local STORED="Wkladasz mithrylowa monete i siedem srebrnych monet do otwartego skorzanego plecaka."
local DENOMINATED="Twoje pieniadze zostaly zdenominowane."
local MAXIMUM="Twoje pieniadze juz sa maksymalnie zdenominowane."
local function setup()
    local s={now=0,timers={},events={},triggers={},cleanups={},sent={},configured=true,sequence=0,autoOpen=false}
    local ctx={}
    function ctx:on(event,callback)
        local handle={};s.events[event]=s.events[event] or {};s.events[event][handle]=callback;return handle
    end
    function ctx:trigger(_,callback) local handle={};s.triggers[handle]=callback;return handle end
    function ctx:timer(seconds,callback)
        s.sequence=s.sequence+1;local handle={order=s.sequence}
        s.timers[handle]={at=s.now+seconds,callback=callback};return handle
    end
    function ctx:cancel(handle)
        s.timers[handle],s.triggers[handle]=nil,nil
        for _,listeners in pairs(s.events) do listeners[handle]=nil end
    end
    function ctx:cleanup(callback) s.cleanups[#s.cleanups+1]=callback end
    function ctx:send() error("bank operation must use the owned injected sender") end
    function s.line(text) for _,callback in pairs(s.triggers) do callback(text) end end
    function s.emit(event,value) for _,callback in pairs(s.events[event] or {}) do callback(value) end end
    function s.cleanup() for i=#s.cleanups,1,-1 do s.cleanups[i]() end end
    function s.advance(seconds)
        local ending=s.now+seconds
        while true do
            local selected,earliest
            for handle,timer in pairs(s.timers) do
                if timer.at<=ending and (not earliest or timer.at<earliest or
                    (timer.at==earliest and handle.order<selected.order)) then selected,earliest=handle,timer.at end
            end
            if not selected then break end
            s.now=earliest;local timer=s.timers[selected];s.timers[selected]=nil;timer.callback()
        end
        s.now=ending
    end
    function s.result()
        local result={calls=0};return result,function(value) result.calls,result.value=result.calls+1,value end
    end
    local bags={configured=function() return s.configured end}
    function bags.commands(verb)
        local command=verb=="wez" and TAKE or STORE
        return s.autoOpen and {OPEN,command,CLOSE} or {command}
    end
    s.api=create(ctx,bags,{timeout=1,settle=0.1,openClose=function() return s.autoOpen end,
        send=function(command)
            s.sent[#s.sent+1]=command
            if s.onSend then return s.onSend(command) end
            return true
        end,
        onStateChanged=function() if s.onStateChanged then s.onStateChanged() end end})
    return s
end
local function exchange(s)
    s.line(TAKEN);s.advance(0.11)
    eq("zdenominuj",s.sent[#s.sent]);eq("denominate",s.api.phase())
end
local function complete(s)
    exchange(s);s.line(DENOMINATED);s.line(STORED);s.advance(0.11)
end
local function commands(s) return table.concat(s.sent,"|") end

test("denomination waits for withdrawal exchange and storage acknowledgements",function()
    local s=setup();local result,done=s.result();s.api.denominate(done)
    eq(TAKE,commands(s));eq(0,result.calls)
    s.advance(0.2);eq(TAKE,commands(s))
    exchange(s);eq(0,result.calls);eq(true,s.api.status().active)
    s.line(DENOMINATED);eq(STORE,s.sent[#s.sent]);eq(0,result.calls)
    s.line(STORED);s.advance(0.11)
    eq(TAKE.."|zdenominuj|"..STORE,commands(s));eq(1,result.calls);eq(true,result.value.ok)
    eq(true,result.value.changed);eq(true,result.value.withdrawn.moved);eq(true,result.value.stored.moved)
    eq(false,result.value.uncertain);eq("idle",s.api.phase());eq(false,s.api.status().active)
    eq(nil,next(s.timers))
end)

test("already maximally denominated is a confirmed success and still stores money",function()
    local s=setup();local result,done=s.result();s.api.denominate(done);exchange(s)
    s.line("\27[32mTwoje pieniądze już są maksymalnie zdenominowane.\27[0m")
    eq(STORE,s.sent[#s.sent]);s.line(STORED);s.advance(0.11)
    eq(true,result.value.ok);eq(false,result.value.changed);eq(1,result.calls)
end)

test("foreign speech denomination events and extended prose do not acknowledge exchange",function()
    local s=setup();local result,done=s.result();s.api.denominate(done);exchange(s)
    for _,text in ipairs({"Gror denominuje swoje pieniadze.","Gror mowi: "..DENOMINATED,
        "Nieprawda: "..DENOMINATED,DENOMINATED.." Gror odchodzi.","Twoje pieniadze nie zostaly zdenominowane."}) do s.line(text) end
    s.emit("chimera.money.denominated",{changed=true})
    eq(2,#s.sent);eq(0,result.calls);s.advance(1)
    eq(2,#s.sent);eq(1,result.calls);eq(false,result.value.ok);eq("denominate",result.value.phase)
    eq(true,result.value.uncertain);eq("idle",s.api.phase())
    s.line(DENOMINATED);s.advance(10);eq(2,#s.sent);eq(1,result.calls)
end)

test("a denomination receipt before the owned exchange send is ignored",function()
    local s=setup();local result,done=s.result();s.api.denominate(done)
    s.line(DENOMINATED);eq(1,#s.sent);exchange(s)
    eq(2,#s.sent);eq(0,result.calls);s.advance(1)
    eq(false,result.value.ok);eq(2,#s.sent)
end)

test("missing withdrawal and storage acknowledgements stop without subsequent commands",function()
    for _,phase in ipairs({"withdraw","store"}) do
        local s=setup();local result,done=s.result();s.api.denominate(done)
        if phase=="store" then exchange(s);s.line(DENOMINATED) end
        local count=#s.sent;s.advance(1.1)
        eq(false,result.value.ok);eq(phase,result.value.phase);eq(1,result.calls);eq(count,#s.sent)
        s.line(TAKEN);s.line(DENOMINATED);s.line(STORED);s.advance(10)
        eq(count,#s.sent);eq(1,result.calls)
    end
end)

test("missing coin container cannot turn a skipped withdrawal into denomination",function()
    local s=setup();s.configured=false;local result,done=s.result();s.api.denominate(done)
    eq(false,result.value.ok);eq("withdraw",result.value.phase);eq(0,#s.sent);eq(1,result.calls)
    eq(false,s.api.status().active)
end)

test("removing the coin configuration before storage fails without false success",function()
    local s=setup();local result,done=s.result();s.api.denominate(done);exchange(s)
    s.configured=false;s.line(DENOMINATED)
    eq(false,result.value.ok);eq("store",result.value.phase);eq(true,result.value.changed)
    eq(2,#s.sent);eq(1,result.calls)
end)

test("failed withdrawal exchange and storage sends each fail once",function()
    for _,command in ipairs({TAKE,"zdenominuj",STORE}) do
        local s=setup();s.onSend=function(sent) return sent~=command end
        local result,done=s.result();s.api.denominate(done)
        if command~=TAKE then s.line(TAKEN);s.advance(0.11) end
        if command==STORE then s.line(DENOMINATED) end
        eq(false,result.value.ok);eq(1,result.calls)
        local count=#s.sent;s.line(TAKEN);s.line(DENOMINATED);s.line(STORED);s.advance(10)
        eq(count,#s.sent);eq(1,result.calls)
    end
end)

test("unrecognised exchange command fails without storing or retrying",function()
    local s=setup();local result,done=s.result();s.api.denominate(done);exchange(s);s.line("Hmm?")
    eq(false,result.value.ok);eq(1,result.calls);s.advance(10);eq(2,#s.sent)
end)

test("bank and normal transfers retain exclusive ownership in every phase",function()
    for _,phase in ipairs({"withdraw","denominate","store"}) do
        local s=setup();s.api.setParcelState("hands");local result,done=s.result();s.api.denominate(done)
        if phase~="withdraw" then exchange(s) end
        if phase=="store" then s.line(DENOMINATED) end
        local count=#s.sent
        for _,method in ipairs({"denominate","takeCoins","stowCoins","stowParcel","takeParcel"}) do
            local other,otherDone=s.result();s.api[method](otherDone)
            eq(false,other.value.ok);eq(1,other.calls);eq(count,#s.sent)
        end
        eq(false,s.api.restoreState({state="hands"}));s.api.cancel();eq(false,result.value.ok)
    end
    local s=setup();local transfer,transferDone=s.result();s.api.takeCoins(transferDone)
    local result,done=s.result();s.api.denominate(done)
    eq(false,result.value.ok);eq(1,#s.sent);eq(0,transfer.calls)
end)

test("STOP cancellation disconnect actor change and reload cancel every denomination phase",function()
    for _,phase in ipairs({"withdraw","denominate","store"}) do
        for _,stop in ipairs({"handle","stop","disconnect","actor","reload"}) do
            local s=setup();local result,done=s.result();local cancel=s.api.denominate(done)
            if phase~="withdraw" then exchange(s) end
            if phase=="store" then s.line(DENOMINATED) end
            if stop=="handle" then cancel()
            elseif stop=="stop" then s.api.cancel()
            elseif stop=="disconnect" then s.emit("chimera.session.end")
            elseif stop=="actor" then s.emit("chimera.paczki.actor.changed") else s.cleanup() end
            eq(false,result.value.ok);eq(phase,result.value.phase);eq(1,result.calls)
            local count=#s.sent;s.line(TAKEN);s.line(DENOMINATED);s.line(STORED);s.advance(10);cancel()
            eq(count,#s.sent);eq(1,result.calls);eq(false,s.api.status().active);eq(nil,next(s.timers))
        end
    end
end)

test("STOP during confirmed withdrawal settle prevents the exchange send",function()
    local s=setup();local result,done=s.result();s.api.denominate(done)
    s.line(TAKEN);s.api.cancel();s.advance(10)
    eq(TAKE,commands(s));eq(false,result.value.ok);eq(1,result.calls)
end)

test("opening and closing confirmations are required before proceeding with bank money",function()
    local s=setup();s.autoOpen=true;local result,done=s.result();s.api.denominate(done)
    eq(OPEN,commands(s));s.line("Otwierasz swoj plecak.");eq(TAKE,s.sent[#s.sent])
    s.line(TAKEN);s.advance(0.11);eq(CLOSE,s.sent[#s.sent]);eq(0,result.calls)
    s.line("Zamykasz swoj plecak.");eq("zdenominuj",s.sent[#s.sent]);s.line(DENOMINATED)
    eq(OPEN,s.sent[#s.sent]);s.line("Skorzany plecak juz jest otwarty.");eq(STORE,s.sent[#s.sent])
    s.line(STORED);s.advance(0.11);eq(CLOSE,s.sent[#s.sent]);eq(0,result.calls)
    s.line("Zamykasz swoj plecak.");eq(true,result.value.ok);eq(1,result.calls)
end)

test("close timeout after withdrawal does not permit exchange",function()
    local s=setup();s.autoOpen=true;local result,done=s.result();s.api.denominate(done)
    s.line("Otwierasz swoj plecak.");s.line(TAKEN);s.advance(2)
    eq(false,result.value.ok);eq(OPEN.."|"..TAKE.."|"..CLOSE,commands(s));eq(1,result.calls)
end)

test("synchronous send receipts cannot overwrite phases or leave timers",function()
    local s=setup();s.onSend=function(command)
        if command==TAKE then s.line(TAKEN)
        elseif command=="zdenominuj" then s.line(DENOMINATED)
        elseif command==STORE then s.line(STORED) end
        return true
    end
    local result,done=s.result();s.api.denominate(done);s.advance(0.3)
    eq(true,result.value.ok);eq(1,result.calls);eq(TAKE.."|zdenominuj|"..STORE,commands(s))
    eq(nil,next(s.timers));eq(false,s.api.status().active)
end)

test("reentrant STOP from sender or state notification cannot send the next command",function()
    for _,where in ipairs({"withdrawSend","exchangeSend","withdrawState","storeState"}) do
        local s=setup();local result,done=s.result()
        s.onSend=function(command)
            if (where=="withdrawSend" and command==TAKE) or (where=="exchangeSend" and command=="zdenominuj") then s.api.cancel() end
            return true
        end
        s.api.denominate(done)
        if where=="withdrawState" then s.onStateChanged=function() s.api.cancel() end end
        if where~="withdrawSend" then
            s.line(TAKEN);s.advance(0.11)
            if where=="storeState" then s.onStateChanged=function() s.api.cancel() end;s.line(DENOMINATED) end
        end
        local count=#s.sent;s.line(TAKEN);s.line(DENOMINATED);s.line(STORED);s.advance(10)
        eq(false,result.value.ok);eq(1,result.calls);eq(count,#s.sent);eq(nil,next(s.timers))
    end
end)

test("a stale cancellation handle cannot cancel a subsequent bank operation",function()
    local s=setup();local first,done=s.result();local cancel=s.api.denominate(done);complete(s)
    eq(true,first.value.ok)
    local second,nextDone=s.result();s.api.denominate(nextDone);cancel();eq(0,second.calls)
    complete(s);eq(true,second.value.ok);eq(1,second.calls)
end)

test("done callback can synchronously start a new denomination without stale work",function()
    local s=setup();local second,nextDone=s.result();local calls=0
    s.api.denominate(function(value) eq(true,value.ok);calls=calls+1;s.api.denominate(nextDone) end)
    complete(s);eq(1,calls);eq(TAKE,s.sent[#s.sent]);eq(0,second.calls)
    complete(s);eq(true,second.value.ok);eq(1,second.calls)
end)

print("Passed "..passed.." bank inventory tests")
