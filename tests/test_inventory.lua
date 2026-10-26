-- Standalone reply-driven inventory tests; no Mudlet globals are required.
local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tests/test_inventory%.lua$") or "."
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
local function setup(options)
    local s={now=0,timers={},events={},triggers={},cleanups={},sent={},notices={},configured={inne=true,monety=true},
        autoOpen=false,sequence=0,requests={}}
    local ctx={}
    function ctx:on(event,callback)
        local handle={};s.events[event]=s.events[event] or {};s.events[event][handle]=callback;return handle
    end
    function ctx:trigger(_,callback) local handle={};s.triggers[handle]=callback;return handle end
    function ctx:timer(seconds,callback)
        s.sequence=s.sequence+1;local handle={order=s.sequence};s.timers[handle]={at=s.now+seconds,callback=callback};return handle
    end
    function ctx:cancel(handle)
        s.timers[handle],s.triggers[handle]=nil,nil
        for _,listeners in pairs(s.events) do listeners[handle]=nil end
    end
    function ctx:cleanup(callback) s.cleanups[#s.cleanups+1]=callback end
    function ctx:send() error("inventory must use the owned injected sender") end
    function s.line(text)
        for _,callback in pairs(s.triggers) do callback(text) end
    end
    function s.emit(event,data)
        for _,callback in pairs(s.events[event] or {}) do callback(data) end
    end
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
    function s.cleanup() for i=#s.cleanups,1,-1 do s.cleanups[i]() end end
    function s.result()
        local result={calls=0};return result,function(value) result.calls,result.value=result.calls+1,value end
    end
    local bags={configured=function(kind) return s.configured[kind]==true end}
    function bags.forms(name)
        s.formsRequested=name
        if s.formsFail then return nil end
        return {name=name:gsub("otwarty ",""):gsub("zamkniety ",""),b="swoj plecak",d="swojego plecaka"}
    end
    function bags.commands(verb,items)
        s.requests[#s.requests+1]={verb=verb,items=items}
        local kind=items.inne and "inne" or "monety"
        local item=items[kind][1]
        local b,d=s.bagB or "swoj plecak",s.bagD or "swojego plecaka"
        local command=verb=="wloz" and "wloz "..item.." do "..d or "wez "..item.." z "..d
        if s.badCommands then return s.badCommands end
        return s.autoOpen and {"otworz "..b,command,"zamknij "..b} or {command}
    end
    function bags.put() error("unchecked batch put must not be used") end
    function bags.take() error("unchecked batch take must not be used") end
    local opts={timeout=1,settle=0.25,openClose=function() return s.autoOpen end,say=function(message) s.notices[#s.notices+1]=message end,
        send=function(command)
            s.sent[#s.sent+1]=command
            if s.onSend then return s.onSend(command) end
            return true
        end}
    for key,value in pairs(options or {}) do opts[key]=value end
    s.api=create(ctx,bags,opts)
    return s
end
local PUT="Wkladasz pocztowa paczke do otwartego skorzanego plecaka."
local TAKE="Bierzesz pocztowa paczke z otwartego skorzanego plecaka."
local COIN="Wkladasz 8 srebrnych monet do otwartego skorzanego plecaka."
local OPEN="Otwierasz swoj plecak."
local CLOSE="Zamykasz swoj plecak."
local function sent(s) return table.concat(s.sent,"|") end

test("missing configured containers skip without guessing and explain each type once",function()
    local s=setup();s.configured={}
    for _,method in ipairs({"stowParcel","takeParcel","stowParcel","stowCoins","stowCoins"}) do
        local result,done=s.result();s.api[method](done);eq(true,result.value.ok);eq(true,result.value.skipped)
    end
    eq(0,#s.sent);eq(2,#s.notices);assert(s.notices[1]:find("/pojemniki inne plecak",1,true))
    assert(s.notices[2]:find("/pojemniki monety plecak",1,true));eq("unknown",s.api.parcelState())
end)

test("unknown parcel location refuses configured transfers without duplicate guesses",function()
    local s=setup()
    for _,method in ipairs({"stowParcel","takeParcel"}) do
        local result,done=s.result();s.api[method](done);eq(false,result.value.ok);eq(true,result.value.uncertain)
    end
    eq(0,#s.sent)
end)

test("parcel storage opens first and waits for opening transfer and serialized close",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done)
    eq("otworz swoj plecak",sent(s));eq("hands",s.api.parcelState());eq(0,result.calls)
    eq("paczke",s.requests[1].items.inne[1])
    s.line(OPEN);eq("unknown",s.api.parcelState());eq("wloz paczke do swojego plecaka",s.sent[2])
    s.line(PUT);eq("bag",s.api.parcelState());eq("close",s.api.phase());eq(0,result.calls)
    eq("otworz swoj plecak|wloz paczke do swojego plecaka|zamknij swoj plecak",sent(s))
    s.line(CLOSE);eq(true,result.value.ok);eq(true,result.value.moved);eq(1,result.calls);eq(nil,next(s.timers))
end)

test("taking a parcel supports first-person wrapped replies and ignores other actors",function()
    local s=setup();s.api.setParcelState("bag")
    local result,done=s.result();s.api.takeParcel(done)
    s.line("Zwinna jaszczuroczleczka wyjmuje paczke z plecaka.")
    eq("unknown",s.api.parcelState());eq(0,result.calls)
    s.line("Bierzesz pocztowa paczke z otwartego skorzanego")
    eq(0,result.calls);s.line("plecaka.")
    eq("hands",s.api.parcelState());s.line(CLOSE);eq(true,result.value.ok)
end)

test("configured opening disabled means only the configured move and its reply",function()
    local s=setup();s.autoOpen=false;s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowParcel(done);s.line(PUT)
    eq(true,result.value.ok);eq(1,#s.sent);eq("bag",s.api.parcelState());cancel();eq(1,result.calls)
    local skipped,nextDone=s.result();s.api.stowParcel(nextDone);eq(true,skipped.value.skipped);eq(1,#s.sent)
end)

test("already-held parcel skips take without sending",function()
    local s=setup();s.api.setParcelState("hands")
    local result,done=s.result();s.api.takeParcel(done);eq(true,result.value.skipped);eq(0,#s.sent)
end)

test("explicit closed denial permits one open and a single confirmed retry",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done);s.line(OPEN)
    s.emit("chimera.container.closed",{action="wlozyc"})
    eq("hands",s.api.parcelState());eq("open",s.api.phase());eq(3,#s.sent)
    s.line("Nie jestes w stanie wlozyc pocztowej paczki do zamknietego pojemnika.")
    eq(3,#s.sent)
    s.line(OPEN);eq(4,#s.sent);eq("unknown",s.api.parcelState())
    s.line(PUT);s.line(CLOSE);eq(true,result.value.ok);eq("bag",s.api.parcelState())
end)

test("closed container cannot trigger an unbounded retry or ignore opening settings",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done);s.line(OPEN)
    s.emit("chimera.container.closed",{action="wlozyc"});s.line("Otwierasz swoj plecak.")
    s.emit("chimera.container.closed",{action="wlozyc"})
    eq(false,result.value.ok);eq(4,#s.sent);eq("hands",s.api.parcelState());eq(nil,next(s.timers))
    s=setup();s.autoOpen=false;s.api.setParcelState("hands");result,done=s.result();s.api.stowParcel(done)
    s.emit("chimera.container.closed",{action="wlozyc"});eq(false,result.value.ok);eq(1,#s.sent)
end)

test("silent transfer leaves parcel unknown and never repeats the command",function()
    local s=setup();s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done);s.advance(1)
    eq(false,result.value.ok);eq(true,result.value.uncertain);eq("unknown",s.api.parcelState())
    s.advance(10);eq(1,#s.sent);eq(1,result.calls)
    s.line(PUT);eq("bag",s.api.parcelState());eq(1,#s.sent);eq(1,result.calls)
end)

test("STOP after send allows only a late confirmed state update and no close or callback",function()
    local s=setup();s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowParcel(done);cancel()
    eq(false,result.value.ok);eq("unknown",s.api.parcelState());eq(1,result.calls)
    s.line(PUT);eq("bag",s.api.parcelState());s.advance(10)
    eq(1,#s.sent);eq(1,result.calls);eq(nil,next(s.timers))
end)

test("a wrapped transfer that started before STOP can finish updating state afterward",function()
    local s=setup();s.api.setParcelState("bag")
    local result,done=s.result();local cancel=s.api.takeParcel(done)
    s.line("Bierzesz pocztowa paczke z otwartego skorzanego");cancel();s.line("plecaka.")
    eq("hands",s.api.parcelState());eq(1,#s.sent);eq(1,result.calls)
end)

test("STOP during close preserves the already-confirmed stored parcel",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowParcel(done);s.line(OPEN);s.line(PUT);cancel();s.line(CLOSE)
    eq(false,result.value.ok);eq(true,result.value.moved);eq(false,result.value.uncertain)
    eq("bag",s.api.parcelState());eq(3,#s.sent);eq(1,result.calls);eq(nil,next(s.timers))
end)

test("authoritative pickup or handover invalidates obsolete late transfer replies",function()
    local s=setup();s.api.setParcelState("hands")
    local _,done=s.result();local cancel=s.api.stowParcel(done);cancel()
    s.api.setParcelState("hands");s.line(PUT);eq("hands",s.api.parcelState());eq(1,#s.sent)
end)

test("coins collect multiple denominations before a serialized best-effort close",function()
    local s=setup();s.autoOpen=true;local result,done=s.result();s.api.stowCoins(done)
    eq("otworz swoj plecak",sent(s));s.line(OPEN)
    eq("wloz monety do swojego plecaka",s.sent[2]);s.line(COIN);s.advance(0.15);eq(2,#s.sent)
    s.line("Wkladasz wiele miedzianych monet do otwartego skorzanego");s.line("plecaka.")
    s.advance(0.2);eq(2,#s.sent);s.advance(0.1);eq(3,#s.sent);eq(0,result.calls)
    s.line(CLOSE);eq(true,result.value.ok);eq(true,result.value.moved);eq("unknown",s.api.parcelState())
    eq(1,s.api.coinReceipt(),"multiple denominations form one confirmed coin operation")
end)

test("STOP before a coin ACK permits one late receipt without close or callback",function()
    local s=setup();s.api.setParcelState("bag")
    local result,done=s.result();local cancel=s.api.stowCoins(done)
    eq(0,s.api.coinReceipt());cancel();eq(false,result.value.ok);eq(1,result.calls)
    s.line(COIN);eq(1,s.api.coinReceipt());eq("bag",s.api.parcelState())
    s.line(COIN);s.line("Wkladasz 3 zlote monety do otwartego skorzanego plecaka.");s.advance(10)
    eq(1,s.api.coinReceipt());eq(1,#s.sent);eq(1,result.calls);eq(nil,next(s.timers))
end)

test("STOP after a coin ACK before close cannot count the same operation twice",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowCoins(done);s.line(OPEN)
    s.line(COIN);eq(1,s.api.coinReceipt());s.advance(0.3);eq(3,#s.sent)
    cancel();s.line(COIN);s.line(CLOSE);s.advance(10)
    eq(false,result.value.ok);eq(true,result.value.moved);eq(1,result.calls)
    eq(1,s.api.coinReceipt());eq(3,#s.sent);eq("hands",s.api.parcelState())
end)

test("wrapped coin reply can begin before STOP and only increment its late receipt afterward",function()
    local s=setup();local result,done=s.result();local cancel=s.api.stowCoins(done)
    s.line("Wkladasz wiele miedzianych monet do otwartego skorzanego")
    cancel();s.line("plecaka.")
    eq(1,s.api.coinReceipt());eq(1,#s.sent);eq(1,result.calls);eq("unknown",s.api.parcelState())
end)

test("new operation and session end invalidate obsolete coin receipts",function()
    for _,method in ipairs({"operation","session","reload"}) do
        local s=setup();s.api.setParcelState("hands")
        local _,done=s.result();local cancel=s.api.stowCoins(done);cancel()
        if method=="operation" then
            local _,nextDone=s.result();s.api.takeParcel(nextDone) -- an already-held skipped operation
        elseif method=="session" then s.emit("chimera.session.end") else s.cleanup() end
        s.line(COIN);eq(0,s.api.coinReceipt(),method);eq(1,#s.sent);eq("hands",s.api.parcelState())
    end
end)

test("each new successful coin command advances a monotonic receipt once",function()
    local s=setup();s.autoOpen=false;s.api.setParcelState("bag")
    for n=1,3 do
        local result,done=s.result();s.api.stowCoins(done);s.line(COIN);s.line(COIN);s.advance(0.3)
        eq(true,result.value.ok);eq(n,s.api.coinReceipt());eq("bag",s.api.parcelState())
    end
    local result,done=s.result();local cancel=s.api.stowCoins(done);cancel();s.line("Wkladasz dlugi miecz do otwartego skorzanego plecaka.")
    eq(3,s.api.coinReceipt());eq(false,result.value.ok)
end)

test("no guessed empty-coins text is treated as success",function()
    local s=setup();local result,done=s.result();s.api.stowCoins(done)
    s.line("Nie masz przy sobie zadnych monet.")
    eq(false,result.value.ok);eq(1,#s.sent);eq(1,result.calls)
end)

test("positive replies for the wrong item or wrong container do not confirm storage",function()
    local s=setup();s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done)
    s.line("Wkladasz dlugi miecz do otwartego skorzanego plecaka.")
    s.line("Wkladasz pocztowa paczke do otwartej torby.")
    eq(0,result.calls);eq("unknown",s.api.parcelState());s.advance(1);eq(false,result.value.ok)
end)

test("unrelated negative lines cannot restore an unconfirmed parcel location",function()
    local s=setup();s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done)
    s.line("Nie widzisz zadnego wyjscia prowadzacego na polnoc.")
    eq(0,result.calls);eq("unknown",s.api.parcelState());s.advance(1);eq(false,result.value.ok)
end)

test("unsupported opening fails safely while unsuccessful close keeps confirmed storage",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done);s.line("Otworz co?")
    eq(false,result.value.ok);eq("hands",s.api.parcelState());eq(1,#s.sent)
    s=setup();s.autoOpen=true;s.api.setParcelState("hands");result,done=s.result();s.api.stowParcel(done);s.line(OPEN);s.line(PUT);s.line("Zamknij co?")
    eq(true,result.value.ok);eq(true,result.value.closeFailed);eq("bag",s.api.parcelState())
end)

test("close timeout is best effort and does not undo a confirmed move",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done);s.line(OPEN);s.line(PUT);s.advance(1)
    eq(true,result.value.ok);eq(true,result.value.closeFailed);eq("bag",s.api.parcelState());eq(nil,next(s.timers))
end)

test("an old cancellation handle cannot cancel a later coin operation",function()
    local s=setup();s.autoOpen=false;s.api.setParcelState("hands")
    local first,done=s.result();local cancel=s.api.stowParcel(done);s.line(PUT)
    local coins,nextDone=s.result();s.api.stowCoins(nextDone);cancel();s.line(COIN);s.advance(0.3)
    eq(true,first.value.ok);eq(true,coins.value.ok);eq(1,coins.calls)
end)

test("synchronous replies complete safely without leaving stale timers",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    s.onSend=function(command)
        if command:match("^otworz ") then s.line(OPEN)
        elseif command:match("^wloz ") then s.line(PUT) else s.line(CLOSE) end
        return true
    end
    local result,done=s.result();s.api.stowParcel(done);eq(true,result.value.ok);eq(nil,next(s.timers));eq(1,result.calls)
end)

test("sender failure and disposal never repeat a transfer",function()
    local s=setup();s.api.setParcelState("hands");s.onSend=function() return false end
    local result,done=s.result();s.api.stowParcel(done);eq(false,result.value.ok);eq("unknown",s.api.parcelState());eq(nil,next(s.timers))
    s=setup();s.api.setParcelState("hands");result,done=s.result();s.api.stowParcel(done);s.cleanup();s.line(PUT);s.advance(10)
    eq(false,result.value.ok);eq(1,result.calls);eq(1,#s.sent);eq("unknown",s.api.parcelState())
end)

test("malformed configured batches are rejected without executing guessed commands",function()
    for _,list in ipairs({{"wloz pocztowa paczke do plecaka"},{"wloz paczke do swojego plecaka; s"}}) do
        local s=setup();s.api.setParcelState("hands");s.badCommands=list
        local result,done=s.result();s.api.stowParcel(done);eq(false,result.value.ok);eq(0,#s.sent);eq("hands",s.api.parcelState())
    end
end)

local WORN="Nosisz na plecach otwarty skorzany plecak."
test("automatic fallback proves a worn backpack before storing and never changes global configuration",function()
    local s=setup({autoDetect=true});s.autoOpen=true;s.configured={};s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done)
    eq("i",sent(s));eq("detect",s.api.phase());eq("hands",s.api.parcelState())
    s.line("Na ziemi lezy otwarty skorzany plecak.")
    s.line("Zwinna jaszczuroczleczka nosi na plecach otwarty plecak.")
    s.line(WORN);s.advance(1.49);eq(1,#s.sent);eq(0,result.calls)
    s.advance(0.01);eq("i|otworz swoj plecak",sent(s));eq("hands",s.api.parcelState())
    s.line(OPEN);eq("wloz paczke do swojego plecaka",s.sent[3])
    eq("skorzany plecak",s.api.status().detectedPack);eq("unknown",s.api.parcelState())
    s.line(PUT);eq("bag",s.api.parcelState());eq("swojego plecaka",s.api.status().parcelContainer)
    eq("zamknij swoj plecak",s.sent[4]);s.line(CLOSE)
    eq(true,result.value.ok);eq(true,result.value.moved);eq(1,result.calls);eq(0,#s.requests)
    eq(nil,next(s.configured));eq(nil,next(s.timers))
end)

test("explicit configured containers take priority over automatic detection",function()
    local s=setup({autoDetect=true});s.autoOpen=false;s.bagB,s.bagD="swoja torbe","swojej torby"
    s.api.setParcelState("hands");local result,done=s.result();s.api.stowParcel(done)
    eq("wloz paczke do swojej torby",sent(s));eq(nil,s.formsRequested)
    s.line("Wkladasz pocztowa paczke do otwartej torby.");eq(true,result.value.ok)
    eq(nil,s.api.status().detectedPack);eq("swojej torby",s.api.status().parcelContainer)
end)

test("automatic query joins only bounded first-person wrapped backpack descriptions",function()
    local s=setup({autoDetect=true,openClose=false});s.configured={};s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done)
    s.line("Nosisz na plecach otwarty")
    s.line("skorzany plecak.");s.advance(1.5)
    eq(2,#s.sent);eq("otwarty skorzany plecak",s.formsRequested)
    s.line("Wkladasz pocztowa paczke do otwartego skorzanego");s.line("plecaka.")
    eq(true,result.value.ok);eq(2,#s.sent);eq("bag",s.api.parcelState())
end)

test("ground carried and other-character backpacks never authorize a fallback transfer",function()
    local s=setup({autoDetect=true});s.configured={};s.api.setParcelState("hands")
    s.line(WORN) -- a previous inventory print is not proof for this query
    for n=1,2 do
        local result,done=s.result();s.api.stowParcel(done)
        s.line("Jest tutaj otwarty skorzany plecak.")
        s.line("Masz przy sobie otwarty skorzany plecak.")
        s.line("PRZY SOBIE: otwarty skorzany plecak.")
        s.line("Zwinna jaszczuroczleczka mowi: Nosisz na plecach otwarty skorzany plecak.")
        s.advance(1.5);eq(true,result.value.ok);eq(true,result.value.skipped)
        assert(result.value.reason:find("Nie wykryto",1,true));eq(n,#s.sent);eq("hands",s.api.parcelState())
    end
    eq(1,#s.notices);eq(nil,s.api.status().detectedPack);eq(nil,next(s.timers))
end)

test("multiple worn backpack replies and incomplete replies skip without guessing",function()
    for _,lines in ipairs({{WORN,WORN},{"Nosisz na plecach otwarty skorzany"}}) do
        local s=setup({autoDetect=true});s.configured={};s.api.setParcelState("hands")
        local result,done=s.result();s.api.stowParcel(done)
        for _,text in ipairs(lines) do s.line(text) end
        s.advance(1.5);eq(true,result.value.skipped);eq(1,#s.sent);eq("hands",s.api.parcelState())
        eq(nil,s.api.status().detectedPack);eq(nil,next(s.timers))
        if #lines==2 then assert(result.value.reason:find("kilka",1,true)) end
    end
end)

test("an unrelated room or actor sentence cannot complete a wrapped own inventory fragment",function()
    for _,foreign in ipairs({"Na ziemi lezy skorzany plecak.","Gror niesie skorzany plecak.",
        "Zwinna jaszczuroczleczka nosi skorzany plecak."}) do
        local s=setup({autoDetect=true});s.configured={};s.api.setParcelState("hands")
        local result,done=s.result();s.api.stowParcel(done)
        s.line("Nosisz na plecach otwarty");s.line(foreign);s.advance(1.5)
        eq(true,result.value.skipped);eq(1,#s.sent);eq(nil,s.formsRequested)
        eq(nil,s.api.status().detectedPack);eq("hands",s.api.parcelState())
    end
end)

test("automatic detection requires public safe own-backpack forms",function()
    local s=setup({autoDetect=true});s.configured={};s.api.setParcelState("hands");s.formsFail=true
    local result,done=s.result();s.api.stowParcel(done);s.line(WORN);s.advance(1.5)
    eq(true,result.value.skipped);eq(1,#s.sent)
    s=setup({autoDetect=true});s.configured={};s.api.setParcelState("hands")
    result,done=s.result();s.api.stowParcel(done)
    s.line("Nosisz na plecach otwarty plecak; wloz monety do torby plecak.")
    s.advance(1.5);eq(true,result.value.skipped);eq(1,#s.sent);eq(nil,s.formsRequested)
end)

test("switching automatic mode off during the query prevents a later transfer",function()
    local enabled=true
    local s=setup({autoDetect=function() return enabled end});s.configured={};s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done);s.line(WORN);enabled=false;s.advance(1.5)
    eq(true,result.value.skipped);eq(1,#s.sent);eq(false,s.api.status().autoDetect)
    eq(nil,s.api.status().detectedPack);s.advance(10);eq(1,#s.sent)
end)

test("STOP rest session actor changes and reload cancel the entire backpack query",function()
    for _,method in ipairs({"cancel","rest","session","actor","reload"}) do
        local s=setup({autoDetect=true});s.configured={};s.api.setParcelState("hands")
        local result,done=s.result();local cancel=s.api.stowParcel(done)
        s.line("Nosisz na plecach otwarty skorzany")
        if method=="cancel" then cancel()
        elseif method=="rest" then s.api.cancel()
        elseif method=="session" then s.emit("chimera.session.end")
        elseif method=="actor" then s.emit("chimera.paczki.actor.changed") else s.cleanup() end
        s.line("plecak.");s.line(WORN);s.advance(10)
        eq(false,result.value.ok,method);eq(1,result.calls,method);eq(1,#s.sent,method)
        eq(nil,s.api.status().detectedPack,method);eq(nil,next(s.timers),method)
    end
end)

test("automatic fallback honors disabled opening and bounded closed-container handling",function()
    local s=setup({autoDetect=true,openClose=false});s.configured={};s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done);s.line(WORN);s.advance(1.5)
    s.emit("chimera.container.closed",{action="wlozyc"});eq(false,result.value.ok);eq(2,#s.sent);eq("hands",s.api.parcelState())
    s=setup({autoDetect=true,openClose=function() return true end});s.configured={};s.api.setParcelState("hands")
    result,done=s.result();s.api.stowParcel(done);s.line(WORN);s.advance(1.5)
    eq("otworz swoj plecak",s.sent[2]);s.line(OPEN);eq("wloz paczke do swojego plecaka",s.sent[3])
    s.emit("chimera.container.closed",{action="wlozyc"});eq("otworz swoj plecak",s.sent[4])
    s.line(OPEN);eq("wloz paczke do swojego plecaka",s.sent[5])
    s.line(PUT);s.line(CLOSE);eq(true,result.value.ok);eq(6,#s.sent)
end)

test("parcel retrieval keeps the confirmed configured container after configuration changes",function()
    local s=setup({autoDetect=true});s.autoOpen=false;s.api.setParcelState("hands")
    local stored,done=s.result();s.api.stowParcel(done);s.line(PUT);eq(true,stored.value.ok)
    s.bagB,s.bagD="swoja torbe","swojej torby"
    local result,take=s.result();s.api.takeParcel(take)
    eq("wez paczke z swojego plecaka",s.sent[2]);eq(1,#s.requests)
    s.line("Bierzesz pocztowa paczke z otwartej torby.");eq(0,result.calls)
    s.line(TAKE);eq(true,result.value.ok);eq(nil,s.api.status().parcelContainer);eq("hands",s.api.parcelState())
end)

test("detected parcel container survives disabled automation and a new global container",function()
    local enabled=true
    local s=setup({autoDetect=function() return enabled end,openClose=false});s.configured={};s.api.setParcelState("hands")
    local stored,done=s.result();s.api.stowParcel(done);s.line(WORN);s.advance(1.5);s.line(PUT)
    eq(true,stored.value.ok);enabled=false;s.configured.inne=true;s.bagB,s.bagD="swoja torbe","swojej torby"
    local result,take=s.result();s.api.takeParcel(take)
    eq("wez paczke z swojego plecaka",s.sent[3]);eq(0,#s.requests)
    s.line(TAKE);eq(true,result.value.ok);eq("hands",s.api.parcelState());eq(3,#s.sent)
end)

test("a late stored-parcel acknowledgement also remembers its original container",function()
    local s=setup({autoDetect=true,openClose=false});s.configured={};s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowParcel(done);s.line(WORN);s.advance(1.5);cancel()
    s.configured.inne=true;s.bagB,s.bagD="swoja torbe","swojej torby"
    s.line(PUT);eq("bag",s.api.parcelState());eq("swojego plecaka",s.api.status().parcelContainer)
    eq(false,result.value.ok);eq(2,#s.sent);eq(1,result.calls)
    local recovered,take=s.result();s.api.takeParcel(take);eq("wez paczke z swojego plecaka",s.sent[3])
    s.line(TAKE);eq(true,recovered.value.ok);eq(nil,s.api.status().parcelContainer)
end)

test("coins use a fresh owned backpack query and preserve receipt guarantees after STOP",function()
    local s=setup({autoDetect=true,openClose=false});s.configured={};s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowCoins(done)
    eq("i",sent(s));s.line(WORN);s.advance(1.5);eq("wloz monety do swojego plecaka",s.sent[2])
    cancel();s.line(COIN);s.line(COIN);s.advance(10)
    eq(1,s.api.coinReceipt());eq("hands",s.api.parcelState());eq(2,#s.sent);eq(false,result.value.ok);eq(1,result.calls)
    local nextResult,nextDone=s.result();s.api.stowCoins(nextDone);eq("i",s.sent[3])
    s.advance(1.5);eq(true,nextResult.value.skipped);eq(3,#s.sent);eq(1,s.api.coinReceipt())
end)

test("an unknown parcel never starts automatic probing or duplicate movement",function()
    local s=setup({autoDetect=true});s.configured={}
    for _,method in ipairs({"stowParcel","takeParcel"}) do
        local result,done=s.result();s.api[method](done);eq(false,result.value.ok);eq(true,result.value.uncertain)
    end
    eq(0,#s.sent)
end)

test("synchronous inventory replies and cancellation cannot leave a delayed transfer",function()
    local s=setup({autoDetect=true,openClose=false});s.configured={};s.api.setParcelState("hands")
    s.onSend=function(command) s.line(command=="i" and WORN or PUT);return true end
    local result,done=s.result();s.api.stowParcel(done);s.advance(1.5)
    eq(true,result.value.ok);eq(2,#s.sent);eq(nil,next(s.timers))
    s=setup({autoDetect=true});s.configured={};s.api.setParcelState("hands")
    s.onSend=function() s.emit("chimera.session.end");return false end
    result,done=s.result();s.api.stowParcel(done);s.line(WORN);s.advance(10)
    eq(false,result.value.ok);eq(1,result.calls);eq(1,#s.sent);eq(nil,next(s.timers))
end)

test("inventory checkpoint exports fresh semantic allowlists without operations or commands in flight",function()
    local s=setup();s.autoOpen=false;s.api.setParcelState("hands")
    local initial=s.api.exportState();eq("hands",initial.state);eq(false,initial.coinsUncertain);eq(nil,initial.container)
    local _,done=s.result();s.api.stowParcel(done)
    local uncertain=s.api.exportState();eq("unknown",uncertain.state);eq(nil,uncertain.container)
    eq(nil,uncertain.pending);eq(nil,uncertain.timer);eq(nil,uncertain.coinReceipt)
    s.line(PUT);local stored=s.api.exportState();eq("bag",stored.state);eq("swojego plecaka",stored.container.d)
    eq(nil,stored.container.b);eq(nil,stored.container.move);eq(nil,stored.container.op)
    for key in pairs(stored) do assert(({state=true,container=true,coinsUncertain=true})[key]) end
    stored.state="hands";stored.container.d="cudzej torby"
    eq("bag",s.api.exportState().state);eq("swojego plecaka",s.api.exportState().container.d)
end)

test("a confirmed d-only container restores without sends and retrieves from the same container",function()
    local original=setup();original.autoOpen=false;original.api.setParcelState("hands")
    local _,done=original.result();original.api.stowParcel(done);original.line(PUT)
    local checkpoint=original.api.exportState()
    local notifications=0
    local restored=setup({autoDetect=true,onStateChanged=function() notifications=notifications+1 end})
    restored.bagB,restored.bagD="swoja torbe","swojej torby"
    eq(true,restored.api.restoreState(checkpoint));eq(0,notifications);eq(0,#restored.sent)
    eq("bag",restored.api.parcelState());checkpoint.container.d="cudzej torby"
    local result,take=restored.result();restored.api.takeParcel(take)
    eq("wez paczke z swojego plecaka",sent(restored));eq(0,#restored.requests)
    restored.line(TAKE);eq(true,result.value.ok);eq("hands",restored.api.exportState().state)
    eq(nil,restored.api.exportState().container)
end)

test("detected backpack metadata restores as a fixed confirmed parcel container",function()
    local original=setup({autoDetect=true,openClose=false});original.configured={};original.api.setParcelState("hands")
    local _,done=original.result();original.api.stowParcel(done);original.line(WORN);original.advance(1.5);original.line(PUT)
    local snapshot=original.api.exportState();eq(true,snapshot.container.detected);eq("skorzany plecak",snapshot.container.name)
    local restored=setup({autoDetect=false,openClose=false});restored.configured={}
    eq(true,restored.api.restoreState(snapshot));eq(0,#restored.sent)
    local result,take=restored.result();restored.api.takeParcel(take)
    eq("wez paczke z swojego plecaka",sent(restored));restored.line(TAKE)
    eq(true,result.value.ok);eq(1,#restored.sent)
end)

test("missing invalid or injected saved bag metadata becomes unknown without guessing",function()
    local invalid={false,{}, {d="swojego plecaka;s"}, {d="swojego plecaka",b="swoj plecak",close="oddaj paczke"},
        {d="swojego plecaka",containerWord="torby"}, {d="swojej torby",b="swoja torbe",detected=true},
        {d="swojego plecaka",detected="true"}, {d="swojego plecaka",open="otworz swoj plecak"}}
    for _,container in ipairs(invalid) do
        local notifications=0;local s=setup({onStateChanged=function() notifications=notifications+1 end})
        local ok=s.api.restoreState({state="bag",container=container or nil,coinsUncertain=true})
        eq(false,ok);eq("unknown",s.api.parcelState());eq(true,s.api.exportState().coinsUncertain)
        eq(0,#s.sent);eq(0,notifications);eq(nil,next(s.timers))
    end
    local s=setup();eq(false,s.api.restoreState({state="bag"}));eq("unknown",s.api.parcelState())
    eq(false,s.api.restoreState({state="ground"}));eq(false,s.api.restoreState({state="hands",coinsUncertain="true"}))
end)

test("restored uncertainty stays unknown and obsolete late acknowledgements cannot change it",function()
    local s=setup();s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowParcel(done);cancel()
    eq(true,s.api.restoreState({state="unknown",coinsUncertain=true}));s.line(PUT);s.line(COIN)
    eq("unknown",s.api.parcelState());eq(true,s.api.exportState().coinsUncertain);eq(0,s.api.coinReceipt())
    eq(1,result.calls);eq(1,#s.sent)
    local recovery,recover=s.result();s.api.stowParcel(recover);eq(false,recovery.value.ok);eq(1,#s.sent)
end)

test("restore refuses an active operation without sends or callbacks",function()
    local s=setup();s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowParcel(done)
    eq(false,s.api.restoreState({state="hands",coinsUncertain=false}));eq(0,result.calls);eq(1,#s.sent)
    eq("unknown",s.api.parcelState());cancel();eq(1,result.calls)
    eq(true,s.api.restoreState({state="hands",coinsUncertain=false}));s.line(PUT);eq("hands",s.api.parcelState())
end)

test("semantic state notifications occur before sends and after confirmed parcel acknowledgements",function()
    local s,changes
    changes={}
    s=setup({onStateChanged=function() changes[#changes+1]=s.api.exportState() end});s.autoOpen=false
    s.api.setParcelState("hands");eq("hands",changes[1].state)
    s.onSend=function(command)
        if command:match("^wloz ") then eq("unknown",changes[#changes].state)
        elseif command:match("^wez ") then eq("unknown",changes[#changes].state) end
        return true
    end
    local _,done=s.result();s.api.stowParcel(done);eq(2,#changes);s.line(PUT)
    eq("bag",changes[3].state);eq("swojego plecaka",changes[3].container.d)
    local _,take=s.result();s.api.takeParcel(take);eq("unknown",changes[4].state);s.line(TAKE)
    eq("hands",changes[5].state);eq(nil,changes[5].container)
    eq(true,s.api.restoreState({state="hands",coinsUncertain=false}));eq(5,#changes)
end)

test("coin uncertainty is saved before sending and survives STOP disconnect and cleanup",function()
    for _,method in ipairs({"cancel","session","reload"}) do
        local s,changes;changes={}
        s=setup({onStateChanged=function() changes[#changes+1]=s.api.exportState() end})
        s.onSend=function(command) if command:match("^wloz monety") then eq(true,changes[#changes].coinsUncertain) end;return true end
        local result,done=s.result();local cancel=s.api.stowCoins(done)
        eq(true,s.api.exportState().coinsUncertain)
        if method=="cancel" then cancel() elseif method=="session" then s.emit("chimera.session.end") else s.cleanup() end
        eq(true,s.api.exportState().coinsUncertain,method);eq(false,result.value.ok);eq(1,result.calls)
        s.advance(10);eq(1,#s.sent);eq(1,#changes)
    end
end)

test("a late coin acknowledgement clears persisted uncertainty once without continuing the cancelled operation",function()
    local s,changes;changes={}
    s=setup({onStateChanged=function() changes[#changes+1]=s.api.exportState() end})
    local result,done=s.result();local cancel=s.api.stowCoins(done);cancel()
    eq(true,changes[1].coinsUncertain);s.line(COIN)
    eq(false,changes[2].coinsUncertain);eq(false,s.api.exportState().coinsUncertain);eq(1,s.api.coinReceipt())
    s.line(COIN);s.advance(10);eq(2,#changes);eq(1,#s.sent);eq(1,result.calls)
end)

test("explicit coin refusal clears uncertainty while a new restore resets only raw receipts",function()
    local s=setup();s.autoOpen=false
    local result,done=s.result();s.api.stowCoins(done);s.line("Nie masz przy sobie zadnych monet.")
    eq(false,result.value.ok);eq(false,s.api.exportState().coinsUncertain)
    local success,nextDone=s.result();s.api.stowCoins(nextDone);s.line(COIN);s.advance(0.3)
    eq(true,success.value.ok);eq(1,s.api.coinReceipt());eq(false,s.api.exportState().coinsUncertain)
    eq(true,s.api.restoreState({state="hands",coinsUncertain=true}));eq(0,s.api.coinReceipt())
    eq(true,s.api.exportState().coinsUncertain);s.line(COIN);eq(0,s.api.coinReceipt())
    local recovered,recover=s.result();s.api.stowCoins(recover);s.line(COIN);s.advance(0.3)
    eq(true,recovered.value.ok);eq(1,s.api.coinReceipt());eq(false,s.api.exportState().coinsUncertain)
end)

test("confirmed stored containers remain exportable after disconnect and module cleanup",function()
    local s=setup();s.autoOpen=false;s.api.setParcelState("hands")
    local _,done=s.result();s.api.stowParcel(done);s.line(PUT)
    s.emit("chimera.session.end");s.cleanup()
    local snapshot=s.api.exportState();eq("bag",snapshot.state);eq("swojego plecaka",snapshot.container.d)
    eq(false,s.api.restoreState(snapshot));eq(1,#s.sent)
end)

test("checkpoint notification cancellation cannot arm late timers or send another command",function()
    local s,cancelOn
    s=setup({onStateChanged=function()
        if cancelOn then s.api.cancel() end
    end});s.api.setParcelState("hands");cancelOn=true
    local result,done=s.result();s.api.stowParcel(done)
    eq(false,result.value.ok);eq(0,#s.sent);eq(nil,next(s.timers));s.advance(10);eq(1,result.calls)
    s=setup({onStateChanged=function() if cancelOn then s.api.cancel() end end});cancelOn=false
    result,done=s.result();s.api.stowCoins(done);cancelOn=true;s.line(COIN)
    eq(false,result.value.ok);eq(false,s.api.exportState().coinsUncertain);eq(1,#s.sent);eq(nil,next(s.timers))
end)

test("both already-open word orders authorize one parcel transfer and still require its own receipt",function()
    for _,reply in ipairs({"Skorzany plecak juz jest otwarty.","Skorzany plecak jest juz otwarty.",
        "Plecak juz jest otwarty.","Juz jest otwarty.","Jest juz otwarty.",
        "\27[32mSkórzany plecak już jest otwarty.\27[0m"}) do
        local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
        local result,done=s.result();s.api.stowParcel(done);s.line(reply)
        eq("wloz paczke do swojego plecaka",s.sent[2]);eq(2,#s.sent);eq(0,result.calls)
        s.line(reply);eq(2,#s.sent);s.line(PUT);eq("zamknij swoj plecak",s.sent[3])
        s.line(CLOSE);eq(true,result.value.ok);eq(1,result.calls);eq(nil,next(s.timers))
    end
end)

test("already-open nominative forms match configured female and male containers",function()
    for _,row in ipairs({{"swoja torbe","swojej torby","Duza skorzana torba juz jest otwarta."},
        {"swoja sakiewke","swojej sakiewki","Skorzana sakiewka jest juz otwarta."},
        {"swoja sakwe","swojej sakwy","Sakwa juz jest otwarta."},
        {"swoj worek","swojego worka","Plocienny zielony worek juz jest otwarty."}}) do
        local s=setup();s.autoOpen=true;s.bagB=row[1];s.bagD=row[2]
        local result,done=s.result();s.api.stowCoins(done);s.line(row[3])
        eq("wloz monety do "..row[2],s.sent[2]);eq(0,result.calls)
    end
end)

test("foreign actor speech negation wrong container and prose cannot acknowledge an opening",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done)
    for _,reply in ipairs({"Skorzany plecak nie jest juz otwarty.","Kobieta mowi, ze jej plecak juz jest otwarty.",
        "Kobieta twierdzi ze plecak jest juz otwarty.","Zwinna jaszczuroczleczka otwiera skorzany plecak.",
        "Kobieta mowi: Skorzany plecak juz jest otwarty.","Skorzana torba juz jest otwarta.",
        "Cudzy plecak juz jest otwarty.","Skorzany plecak juz jest zamkniety."}) do
        s.line(reply);eq(1,#s.sent);eq("open",s.api.phase());eq("hands",s.api.parcelState())
    end
    s.line("Skorzany plecak juz jest otwarty.");eq(2,#s.sent);eq(0,result.calls)
end)

test("late already-open after STOP or disconnect cannot restart a container operation",function()
    for _,stop in ipairs({"cancel","disconnect"}) do
        local s=setup();s.autoOpen=true;s.api.setParcelState("hands")
        local result,done=s.result();local cancel=s.api.stowParcel(done)
        if stop=="cancel" then cancel() else s.emit("chimera.session.end") end
        s.line("Skorzany plecak juz jest otwarty.");s.advance(10)
        eq(1,#s.sent);eq(1,result.calls);eq(false,result.value.ok);eq("hands",s.api.parcelState())
        eq(nil,next(s.timers))
    end
end)

test("fare withdrawal opens the bag then waits for own wrapped coins and serialized close",function()
    local s=setup();s.autoOpen=true;s.api.setParcelState("bag")
    local result,done=s.result();s.api.takeCoins(done)
    eq("otworz swoj plecak",sent(s));eq(0,result.calls);eq("bag",s.api.parcelState())
    s.line("Skorzany plecak juz jest otwarty.")
    eq("wez monety z swojego plecaka",s.sent[2]);eq("monety",s.requests[1].items.monety[1]);eq("wez",s.requests[1].verb)
    eq(true,s.api.exportState().coinsUncertain);eq(0,s.api.coinReceipt());eq(0,s.api.coinWithdrawalReceipt())
    s.line("Zwinna jaszczuroczleczka bierze wiele monet z otwartego skorzanego plecaka.")
    eq(0,result.calls);eq(true,s.api.exportState().coinsUncertain);eq(0,s.api.coinWithdrawalReceipt())
    s.line("Bierzesz wiele miedzianych monet, wiele zlotych monet i wiele srebrnych monet z otwartego skorzanego")
    eq(true,s.api.exportState().coinsUncertain);eq(0,s.api.coinReceipt());eq(0,s.api.coinWithdrawalReceipt())
    s.line("plecaka.");eq(false,s.api.exportState().coinsUncertain);eq(0,result.calls);eq(1,s.api.coinWithdrawalReceipt())
    s.line("Wyjmujesz jeszcze dwie srebrne monety z otwartego skorzanego plecaka.")
    s.advance(0.3);eq("zamknij swoj plecak",s.sent[3]);eq(0,result.calls)
    s.line(CLOSE);eq(true,result.value.ok);eq(true,result.value.moved);eq(1,result.calls)
    eq(0,s.api.coinReceipt());eq(1,s.api.coinWithdrawalReceipt());eq("bag",s.api.parcelState());eq(nil,next(s.timers))
end)

test("fare withdrawal never advances the proof of stored delivery money",function()
    local s=setup();s.api.setParcelState("hands")
    local stored,put=s.result();s.api.stowCoins(put);s.line(COIN);s.advance(0.3)
    eq(true,stored.value.ok);eq(1,s.api.coinReceipt());eq(0,s.api.coinWithdrawalReceipt())
    local taken,take=s.result();s.api.takeCoins(take);eq(true,s.api.exportState().coinsUncertain)
    s.line(COIN);eq(true,s.api.exportState().coinsUncertain);eq(1,s.api.coinReceipt());eq(0,taken.calls);eq(0,s.api.coinWithdrawalReceipt())
    s.line("Bierzesz osiem srebrnych monet z otwartego skorzanego plecaka.");s.advance(0.3)
    eq(true,taken.value.ok);eq(1,s.api.coinReceipt());eq(false,s.api.exportState().coinsUncertain);eq(1,s.api.coinWithdrawalReceipt())
    local again,reput=s.result();s.api.stowCoins(reput);s.line(COIN);s.advance(0.3)
    eq(true,again.value.ok);eq(2,s.api.coinReceipt());eq(1,s.api.coinWithdrawalReceipt());eq("hands",s.api.parcelState())
end)

test("a late wrapped withdrawal clears only its own uncertainty without storage credit or continuation",function()
    local s=setup();s.api.setParcelState("bag")
    local stored,put=s.result();s.api.stowCoins(put);s.line(COIN);s.advance(0.3)
    eq(1,s.api.coinReceipt());local before=#s.sent
    local result,done=s.result();local cancel=s.api.takeCoins(done)
    s.line("Bierzesz wiele zlotych monet z otwartego skorzanego");cancel()
    eq(false,result.value.ok);eq(1,result.calls);eq(true,s.api.exportState().coinsUncertain);eq(0,s.api.coinWithdrawalReceipt())
    s.line("plecaka.");eq(false,s.api.exportState().coinsUncertain);eq(1,s.api.coinReceipt());eq(1,s.api.coinWithdrawalReceipt())
    s.line("Bierzesz wiele zlotych monet z otwartego skorzanego plecaka.");s.line(CLOSE);s.advance(10)
    eq(before+1,#s.sent);eq(1,result.calls);eq(1,s.api.coinReceipt());eq(1,s.api.coinWithdrawalReceipt());eq("bag",s.api.parcelState());eq(nil,next(s.timers))
end)

test("disconnect and cleanup leave an unacknowledged withdrawal uncertain and ignore old replies",function()
    for _,method in ipairs({"disconnect","cleanup","restore"}) do
        local s=setup();s.api.setParcelState("hands")
        local stored,put=s.result();s.api.stowCoins(put);s.line(COIN);s.advance(0.3)
        eq(1,s.api.coinReceipt())
        local result,done=s.result();local cancel=s.api.takeCoins(done)
        if method=="disconnect" then s.emit("chimera.session.end")
        elseif method=="cleanup" then s.cleanup()
        else cancel();eq(true,s.api.restoreState({state="hands",coinsUncertain=true})) end
        local receipt=s.api.coinReceipt();local count=#s.sent
        s.line("Bierzesz osiem srebrnych monet z otwartego skorzanego plecaka.");s.advance(10)
        eq(true,s.api.exportState().coinsUncertain,method);eq(receipt,s.api.coinReceipt());eq(0,s.api.coinWithdrawalReceipt())
        eq(count,#s.sent);eq(1,result.calls);eq(false,result.value.ok);eq("hands",s.api.parcelState())
    end
end)

test("a new storage operation cannot consume an obsolete fare withdrawal acknowledgement",function()
    local s=setup();s.api.setParcelState("bag")
    local old,done=s.result();local cancel=s.api.takeCoins(done);cancel()
    local current,put=s.result();s.api.stowCoins(put)
    s.line("Bierzesz osiem srebrnych monet z otwartego skorzanego plecaka.")
    eq(true,s.api.exportState().coinsUncertain);eq(0,s.api.coinReceipt());eq(0,s.api.coinWithdrawalReceipt());eq(0,current.calls)
    s.line(COIN);s.advance(0.3)
    eq(true,current.value.ok);eq(1,s.api.coinReceipt());eq(false,s.api.exportState().coinsUncertain);eq(0,s.api.coinWithdrawalReceipt())
    eq(1,old.calls);eq(false,old.value.ok);eq("bag",s.api.parcelState())
end)

test("automatic fare withdrawal uses one freshly proved worn backpack without guessing a floor bag",function()
    local s=setup({autoDetect=true});s.configured={};s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.takeCoins(done);eq("i",sent(s))
    s.line("Na ziemi lezy otwarty skorzany plecak.");s.line(WORN);s.advance(1.5)
    eq("otworz swoj plecak",s.sent[2]);s.line(OPEN)
    eq("wez monety z swojego plecaka",s.sent[3]);eq(true,s.api.exportState().coinsUncertain)
    s.line("Wyjmujesz szesc srebrnych monet z otwartego skorzanego plecaka.");s.advance(0.3)
    eq("zamknij swoj plecak",s.sent[4]);s.line(CLOSE)
    eq(true,result.value.ok);eq(0,s.api.coinReceipt());eq(1,s.api.coinWithdrawalReceipt());eq("hands",s.api.parcelState());eq(nil,next(s.timers))
end)

test("fare preparation skips absent configuration or an unproved backpack without moving coins",function()
    local s=setup();s.configured={};s.api.setParcelState("bag")
    local result,done=s.result();s.api.takeCoins(done)
    eq(true,result.value.ok);eq(true,result.value.skipped);eq(0,#s.sent);eq(0,s.api.coinReceipt());eq(0,s.api.coinWithdrawalReceipt());eq("bag",s.api.parcelState())
    s=setup({autoDetect=true});s.configured={};s.api.setParcelState("hands")
    result,done=s.result();s.api.takeCoins(done);s.line("Na ziemi lezy otwarty skorzany plecak.");s.advance(1.5)
    eq(true,result.value.ok);eq(true,result.value.skipped);eq("i",sent(s));eq(0,s.api.coinReceipt())
    eq(false,s.api.exportState().coinsUncertain);eq(0,s.api.coinWithdrawalReceipt());eq("hands",s.api.parcelState())
end)

test("a refused or silent fare withdrawal does not invent held money or storage receipts",function()
    local s=setup();s.api.setParcelState("bag")
    local result,done=s.result();s.api.takeCoins(done);s.line("Nie widzisz zadnych monet w plecaku.")
    eq(false,result.value.ok);eq(false,s.api.exportState().coinsUncertain);eq(0,s.api.coinReceipt());eq(0,s.api.coinWithdrawalReceipt());eq("bag",s.api.parcelState())
    local second,nextDone=s.result();s.api.takeCoins(nextDone);local count=#s.sent;s.advance(1.1)
    eq(false,second.value.ok);eq(true,s.api.exportState().coinsUncertain);eq(0,s.api.coinReceipt());eq(0,s.api.coinWithdrawalReceipt())
    s.advance(10);eq(count,#s.sent);eq(1,second.calls);eq("bag",s.api.parcelState())
end)

test("withdrawal receipts notify once and stay monotonic without checkpoint persistence",function()
    local s,changes
    changes={}
    s=setup({onStateChanged=function() changes[#changes+1]=s.api.coinWithdrawalReceipt() end})
    local first,done=s.result();s.api.takeCoins(done)
    eq(0,changes[#changes]);eq(0,s.api.coinWithdrawalReceipt())
    s.line("Bierzesz osiem srebrnych monet z otwartego skorzanego plecaka.")
    eq(1,changes[#changes]);eq(1,s.api.coinWithdrawalReceipt());local acknowledgements=#changes
    s.line("Wyjmujesz dwie zlote monety z otwartego skorzanego plecaka.")
    eq(acknowledgements,#changes);eq(1,s.api.coinWithdrawalReceipt());s.advance(0.3);eq(true,first.value.ok)
    local snapshot=s.api.exportState();eq(nil,snapshot.coinWithdrawalReceipt)
    snapshot.state="hands";snapshot.coinWithdrawalReceipt=900
    eq(true,s.api.restoreState(snapshot));eq(1,s.api.coinWithdrawalReceipt())
    local second,nextDone=s.result();s.api.takeCoins(nextDone)
    s.line("Bierzesz trzy miedziane monety z otwartego skorzanego plecaka.");s.advance(0.3)
    eq(true,second.value.ok);eq(2,s.api.coinWithdrawalReceipt());eq(2,changes[#changes]);eq(0,s.api.coinReceipt())
    local fresh=setup();eq(true,fresh.api.restoreState(snapshot));eq(0,fresh.api.coinWithdrawalReceipt())
end)

test("a delayed own already-open reply continues once within the extended opening window",function()
    local s=setup({timeout=6,openTimeout=30});s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done)
    s.advance(6.1);eq(1,#s.sent);eq(0,result.calls);eq("open",s.api.phase());eq("hands",s.api.parcelState())
    eq(1,#s.notices);assert(s.notices[1]:find("Czekam na potwierdzenie otwarcia",1,true))
    s.line("Skorzany plecak juz jest otwarty.")
    eq(2,#s.sent);eq("wloz paczke do swojego plecaka",s.sent[2]);eq("unknown",s.api.parcelState())
    s.line(PUT);s.line(CLOSE);eq(1,result.calls);eq(true,result.value.ok);eq("bag",s.api.parcelState())
    s.advance(40);eq(3,#s.sent);eq(1,result.calls);eq(nil,next(s.timers))
end)

test("an extended opening wait fails at its full bound without repeating any command",function()
    local s=setup({timeout=6,openTimeout=30});s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();s.api.stowParcel(done)
    s.advance(29.9);eq(0,result.calls);eq(1,#s.sent);eq("hands",s.api.parcelState());eq(1,#s.notices)
    s.advance(0.2);eq(1,result.calls);eq(false,result.value.ok);eq(false,result.value.uncertain)
    assert(result.value.reason:find("brak potwierdzenia otwarcia",1,true));eq(nil,next(s.timers))
    s.line("Skorzany plecak juz jest otwarty.");s.advance(30);eq(1,#s.sent);eq(1,result.calls)
end)

test("foreign actions and quoted already-open prose cannot complete an extended opening wait",function()
    local s=setup({timeout=6,openTimeout=30});s.autoOpen=true;s.api.setParcelState("hands")
    local result,done=s.result();local cancel=s.api.stowParcel(done);s.advance(7)
    for _,line in ipairs({"Morrid otwiera skorzany plecak.","Morrid mowi: Skorzany plecak juz jest otwarty.",
        "Czy skorzany plecak juz jest otwarty?","Cudzy skorzany plecak juz jest otwarty."}) do s.line(line) end
    eq(1,#s.sent);eq(0,result.calls);eq("open",s.api.phase());eq("hands",s.api.parcelState())
    cancel();eq(1,result.calls);eq(false,result.value.ok);eq(nil,next(s.timers))
end)

test("STOP disconnect and cleanup cancel grace and late opening cannot start a transfer",function()
    for _,method in ipairs({"stop","disconnect","cleanup"}) do
        local s=setup({timeout=6,openTimeout=30});s.autoOpen=true;s.api.setParcelState("hands")
        local result,done=s.result();local cancel=s.api.stowParcel(done);s.advance(7)
        eq(1,#s.sent);eq(0,result.calls);eq(1,#s.notices)
        if method=="stop" then cancel() elseif method=="disconnect" then s.emit("chimera.session.end") else s.cleanup() end
        eq(1,result.calls);eq(false,result.value.ok);eq(nil,next(s.timers))
        s.line("Skorzany plecak juz jest otwarty.");s.line(OPEN);s.advance(40)
        eq(1,#s.sent);eq(1,result.calls);eq("hands",s.api.parcelState());eq(nil,next(s.timers))
    end
end)

print("PASS "..passed.." inventory tests")
