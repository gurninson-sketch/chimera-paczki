-- Verified Grismerie crossing at Quenelles. No ticket purchase is involved.
-- Lines acknowledge each transport stage; only the target GMCP hash AND map
-- room confirm completion. Every callback belongs to one cancellable voyage.
local SOUTH, NORTH = "894039a1680ca034", "20016d960316ba51"
local WAIT_LIMIT, SAIL_LIMIT, LAND_LIMIT, BOARD_REPLY = 300, 300, 15, 15
local MAX_ATTEMPTS, RETRY_DELAY = 3, 0.5

local function norm(value)
    local text=tostring(value or ""):lower():gsub("ą","a"):gsub("ć","c"):gsub("ę","e"):gsub("ł","l")
        :gsub("ń","n"):gsub("ó","o"):gsub("ś","s"):gsub("ź","z"):gsub("ż","z")
    return text:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
end
local function copy(record)
    local out={}
    for key,value in pairs(record or {}) do out[key]=value end
    return out
end
local function valid_map(value) return type(value)=="number" and value>0 and value<math.huge and value==math.floor(value) end
local function boat(room)
    local name=norm(room and room.name)
    return name:find("prom",1,true)~=nil and name:find("poklad",1,true)~=nil
end

return function(ctx,opts)
    opts=opts or {}
    local gmcp,mapper=assert(opts.gmcp,"ferry: gmcp required"),assert(opts.mapper,"ferry: mapper required")
    local sender=opts.send or function(command) ctx:send(command) end
    local api,active,remembered,disposed,drain={},nil,nil,false,nil

    local function here()
        local room=gmcp.room() or {}
        return room,mapper.current_room()
    end
    local function map_of(hash)
        if type(getRoomIDbyHash)~="function" then return nil end
        local ok,id=pcall(getRoomIDbyHash,hash)
        return ok and valid_map(id) and id or nil
    end
    local function link_of(link)
        if type(link)~="table" then return nil,"brak przeprawy" end
        if not ((link.fromHash==SOUTH and link.toHash==NORTH) or (link.fromHash==NORTH and link.toHash==SOUTH)) then
            return nil,"niezweryfikowana przeprawa"
        end
        local out=copy(link)
        out.fromMap=out.fromMap or map_of(out.fromHash)
        out.toMap=out.toMap or map_of(out.toHash)
        if not valid_map(out.fromMap) or not valid_map(out.toMap) or out.fromMap==out.toMap then return nil,"brak obu brzegow na mapie" end
        out.cost=tonumber(out.cost) or 40
        out.transport="ferry"
        out.boardCommand=out.fromHash==SOUTH and "wsiadz na statek" or "wejdz na prom"
        return out
    end
    function api.catalogue()
        local result={}
        for _,pair in ipairs({{SOUTH,NORTH},{NORTH,SOUTH}}) do
            local link=link_of({fromHash=pair[1],toHash=pair[2],cost=40})
            if link then result[#result+1]=link end
        end
        return result
    end
    api.catalog=api.catalogue

    local function alive(op) return op~=nil and not disposed and active==op and not op.finished end
    local function clear(op,key)
        local handle=op[key];op[key]=nil
        if handle then ctx:cancel(handle) end
    end
    local function activity(op,timeout)
        if alive(op) then ctx:emit("chimera.paczki.travel.activity",{transport="ferry",phase=op.phase,timeout=timeout,target=op.link.toHash,map_room=op.link.toMap}) end
    end
    local function end_drain(reason,unexpected,replaced)
        local pending=drain
        if not pending then return end
        drain=nil;clear(pending,"timer")
        if not replaced then
            ctx:emit("chimera.walk.stopped",{target=pending.record.link.toHash,map_room=pending.record.link.toMap,
                transport="paczki_prom",reason=reason})
        end
        if unexpected then
            remembered=nil
            ctx:emit("chimera.paczki.travel.unexpected",{reason=reason,room=unexpected,
                expected=pending.record.link.toHash,map_room=pending.record.link.toMap})
        end
        ctx:emit("chimera.paczki.travel.settled",{token=pending})
    end
    local function remember(op)
        return {link=copy(op.link),boatHash=op.boatHash,aboard=op.aboard,departed=op.departed,
            arrivalSeen=op.arrivalSeen,leaveSent=op.leaveSent,attempts=op.attempts,
            currentToHash=op.currentToHash or op.link.toHash,currentToMap=op.currentToMap or op.link.toMap}
    end
    local function finish(op,ok,reason,keep)
        if active~=op or op.finished then return end
        local room=here()
        local pendingKind
        local closing=type(ctx.isClosed)=="function" and ctx:isClosed()
        if keep and not disposed and not closing and ((op.aboard and (room.id==op.boatHash or not op.boatHash)) or
            (op.phase=="boarding" and op.attempts>0)) then
            remembered=remember(op)
            if op.leaveSent then pendingKind="landing"
            elseif not op.boatHash then pendingKind="boarding" end
        elseif ok or not keep then remembered=nil end
        op.finished=true;active=nil
        for _,key in ipairs({"bankTimer","replyTimer","retryTimer","sailTimer","landTimer"}) do clear(op,key) end
        local event={target=op.link.toHash,map_room=op.link.toMap,transport="paczki_prom",reason=reason}
        if pendingKind then
            drain={kind=pendingKind,record=remembered}
            local pending=drain
            pending.timer=ctx:timer(LAND_LIMIT,function()
                if drain~=pending then return end
                remembered=nil;end_drain("brak potwierdzenia przerwanej komendy promu",gmcp.room() or {})
            end)
            ctx:emit("chimera.paczki.travel.pending",{token=pending})
        end
        if op.started and not pendingKind then ctx:emit(ok and "chimera.walk.arrived" or "chimera.walk.stopped",event) end
        op.done({ok=ok,reason=reason,fromHash=op.link.fromHash,toHash=op.link.toHash,map_room=op.link.toMap,transport="ferry"})
    end
    local function later(op,key,seconds,callback)
        clear(op,key)
        op[key]=ctx:timer(seconds,function()
            if not alive(op) then return end
            op[key]=nil;callback()
        end)
    end
    local function send(op,command)
        if not alive(op) then return false end
        local ok,result=pcall(sender,command)
        if not ok or result==false then
            finish(op,false,"nie udalo sie wyslac komendy promu: "..tostring(ok and result or result))
            return false
        end
        return alive(op)
    end
    local inspect,land
    local function boarded(op)
        if not alive(op) then return end
        local room=here()
        if boat(room) and room.id and room.id~=op.link.fromHash and room.id~=op.link.toHash then op.boatHash=room.id end
        if op.aboard then inspect(op);return end
        op.aboard=true;op.phase="sailing"
        clear(op,"bankTimer");clear(op,"replyTimer");clear(op,"retryTimer")
        later(op,"sailTimer",SAIL_LIMIT,function() finish(op,false,"brak potwierdzenia przybicia promu") end)
        activity(op,SAIL_LIMIT)
        inspect(op)
    end
    land=function(op)
        if not alive(op) or op.leaveSent or not op.aboard or not op.departed or not op.arrivalSeen then return end
        if op.currentToHash~=op.link.toHash then return end
        local room,map=here()
        if room.id==op.link.toHash and map==op.link.toMap then finish(op,true);return end
        -- A cached departure-bank packet cannot authorize leaving a vessel.
        -- Wait for the boat snapshot, or the confirmed destination bank.
        if room.id==op.link.fromHash or not boat(room) then return end
        op.leaveSent=true;op.phase="disembarking"
        clear(op,"sailTimer")
        later(op,"landTimer",LAND_LIMIT,function() finish(op,false,"brak potwierdzenia zejscia na docelowy brzeg") end)
        activity(op,LAND_LIMIT)
        send(op,"zejdz na brzeg")
    end
    inspect=function(op)
        if not alive(op) then return end
        local room,map=here()
        if room.id==op.link.toHash then
            op.targetSeen=true
            if op.aboard and (op.departed or op.arrivalSeen or op.leaveSent) and map==op.link.toMap then finish(op,true) end
            return
        end
        if boat(room) and room.id and room.id~=op.link.fromHash then
            op.boatHash=room.id
            if not op.aboard then boarded(op);return end
            if op.arrivalSeen then land(op) end
            return
        end
        if op.leaveSent and room.id and room.id~=op.boatHash then
            finish(op,false,"prom doplynal do innego brzegu")
        elseif op.aboard and op.departed and op.boatHash and room.id and room.id~=op.boatHash and room.id~=op.link.fromHash then
            finish(op,false,"niezgodna lokacja podczas przeprawy")
        end
    end
    local attempt
    local function wait_for_vessel(op)
        if not alive(op) or op.aboard then return end
        clear(op,"replyTimer")
        if op.attempts>=MAX_ATTEMPTS then finish(op,false,"nie udalo sie wejsc na prom po trzech probach");return end
        op.phase="waiting"
        activity(op,WAIT_LIMIT)
    end
    attempt=function(op)
        if not alive(op) or op.aboard then return end
        local room,map=here()
        if room.id~=op.link.fromHash or map~=op.link.fromMap then finish(op,false,"zmiana brzegu przed wejsciem na prom");return end
        if op.attempts>=MAX_ATTEMPTS then finish(op,false,"wyczerpano proby wejscia na prom");return end
        op.attempts=op.attempts+1;op.phase="boarding"
        later(op,"replyTimer",BOARD_REPLY,function() wait_for_vessel(op) end)
        activity(op,WAIT_LIMIT)
        send(op,op.link.boardCommand)
    end
    local function absent(text)
        return text:match("^nie ma .-prom") or text:match("^nie widzisz .-prom") or
            text:match("^nie ma .-statku") or text:match("^nie widzisz .-statku") or
            text:match("^nie mozesz wejsc na prom") or text:match("^nie mozesz wsiasc na statek")
    end
    local function departed(record)
        -- A stopped passenger remains on the vessel. A later departure after
        -- docking starts the opposite crossing and invalidates that arrival.
        if record.arrivalSeen then
            if record.currentToHash==record.link.toHash then
                record.currentToHash,record.currentToMap=record.link.fromHash,record.link.fromMap
            else record.currentToHash,record.currentToMap=record.link.toHash,record.link.toMap end
        end
        record.departed=true;record.arrivalSeen=false
    end
    local function passive_line(text)
        local record=remembered
        if not record then return end
        local room=here()
        if drain and drain.kind=="boarding" and (text=="wskakujesz na poklad promu." or text=="na pokladzie promu.") then
            record.aboard=true
        elseif (record.boatHash and room.id==record.boatHash and boat(room)) or
            (drain and drain.kind=="boarding" and record.aboard) then
            if text=="prom powoli odbija od brzegu." then departed(record)
            elseif text=="prom powoli przybija do brzegu." and record.departed then record.arrivalSeen=true end
        end
    end
    local function on_line(raw)
        local op=active
        local text=norm(raw)
        if not alive(op) then passive_line(text);return end
        if text=="wskakujesz na poklad promu." or text=="na pokladzie promu." then
            if op.attempts>0 or op.aboard then boarded(op) end
        elseif text=="prom powoli odbija od brzegu." then
            if op.aboard then departed(op);inspect(op) end
        elseif text=="prom powoli przybija do brzegu." or text=="rzeczny prom przybija do brzegu." then
            if op.aboard then
                -- The river-ferry line describes a vessel at the bank, while
                -- the slow-arrival line is the passenger's arrival protocol.
                if text=="prom powoli przybija do brzegu." and op.departed then op.arrivalSeen=true;land(op) end
            elseif op.phase=="waiting" and not op.retryTimer then
                later(op,"retryTimer",RETRY_DELAY,function() attempt(op) end)
            end
        elseif not op.aboard and op.phase=="boarding" and absent(text) then wait_for_vessel(op)
        elseif op.leaveSent and (text:match("^zejdz gdzie") or text:match("^nie mozesz zejsc")) then
            finish(op,false,"gra odmowila zejscia z promu")
        end
    end
    local function start(link,done,resume)
        done=assert(done,"ferry: callback required")
        if disposed then done({ok=false,reason="przeprawa wylaczona"});return function() end end
        if drain then
            if drain.kind=="landing" and resume==drain.record then
                -- Resuming the same landing adopts its already-sent command.
                -- The resumed operation below never sends another leave.
                end_drain("wznowiono oczekiwanie na zejscie z promu")
            else
                end_drain("nowa przeprawa przed potwierdzeniem poprzedniej komendy")
                remembered=nil
                done({ok=false,reason="poprzednia komenda promu nie zostala jeszcze potwierdzona"});return function() end
            end
        end
        if active then done({ok=false,reason="trwa juz przeprawa"});return function() end end
        local known,why=link_of(link)
        if not known then done({ok=false,reason=why});return function() end end
        local room,map=here()
        if not resume and (room.id~=known.fromHash or map~=known.fromMap) then
            done({ok=false,reason="przeprawe rozpocznij na potwierdzonym brzegu"});return function() end
        end
        if resume and (not resume.boatHash or room.id~=resume.boatHash or not boat(room)) then
            done({ok=false,reason="nie potwierdzono zapamietanego promu"});return function() end
        end
        local op={link=known,done=done,attempts=resume and 1 or 0,phase="boarding",started=true,
            currentToHash=resume and resume.currentToHash or known.toHash,
            currentToMap=resume and resume.currentToMap or known.toMap}
        active=op;remembered=nil
        ctx:emit("chimera.walk.started",{target=known.toHash,map_room=known.toMap,transport="paczki_prom"})
        local function cancel() finish(op,false,"przerwane",true) end
        if not alive(op) then return cancel end
        if resume then
            op.boatHash=resume.boatHash
            boarded(op)
            if not alive(op) then return cancel end
            op.departed=resume.departed;op.arrivalSeen=resume.arrivalSeen;op.leaveSent=resume.leaveSent
            if op.leaveSent then
                op.phase="disembarking";clear(op,"sailTimer")
                later(op,"landTimer",LAND_LIMIT,function() finish(op,false,"brak potwierdzenia zejscia na docelowy brzeg") end)
                activity(op,LAND_LIMIT)
            elseif op.arrivalSeen then land(op) end
        else
            later(op,"bankTimer",WAIT_LIMIT,function() finish(op,false,"limit oczekiwania na prom") end)
            attempt(op)
        end
        return cancel
    end
    function api.run(link,done) return start(link,done) end
    function api.resumable(targetMap)
        local room=here()
        return remembered~=nil and remembered.link.toMap==targetMap and room.id==remembered.boatHash and boat(room)
    end
    function api.resume(targetMap,done)
        if not api.resumable(targetMap) then done({ok=false,reason="brak zapamietanej przeprawy do tego celu"});return function() end end
        local previous=remembered
        return start(previous.link,done,previous)
    end
    local function snapshot(record,phase)
        return {phase=phase,link=copy(record.link),fromHash=record.link.fromHash,toHash=record.link.toHash,
            fromMap=record.link.fromMap,toMap=record.link.toMap,deckId=record.boatHash,boatHash=record.boatHash,
            attempts=record.attempts,aboard=true,departed=record.departed==true,arrived=record.arrivalSeen==true,
            arrivalSeen=record.arrivalSeen==true,leaveSent=record.leaveSent==true,
            currentToHash=record.currentToHash,currentToMap=record.currentToMap}
    end
    function api.state()
        local room=here()
        if active and active.aboard and active.boatHash and room.id==active.boatHash and boat(room) then
            return snapshot(active,active.phase)
        end
        if remembered and room.id==remembered.boatHash and boat(room) then return snapshot(remembered,"paused") end
    end
    function api.status()
        if active then return {phase=active.phase,attempts=active.attempts,aboard=active.aboard==true} end
    end
    ctx:on("chimera.walk.started",function()
        if not active then
            remembered=nil
            if drain then end_drain("inne chodzenie zastapilo przerwana komende promu",nil,true) end
        end
    end)
    ctx:trigger("^",function() on_line(line) end)
    local function passive_room()
        local record=remembered
        if not record then return end
        local room,map=here()
        if drain then
            if drain.kind=="boarding" then
                if room.id==record.link.fromHash then return end
                if boat(room) and room.id and room.id~=record.link.toHash then
                    record.boatHash=room.id;record.aboard=true
                    end_drain("potwierdzono przerwane wejscie na prom")
                else end_drain("nieoczekiwana lokacja po przerwanym wejsciu na prom",room) end
            elseif room.id==record.boatHash and boat(room) then return
            elseif room.id==record.link.toHash then
                if map==record.link.toMap then
                    remembered=nil;end_drain("potwierdzono przerwane zejscie z promu")
                end -- room.info may precede the mapper's update.
            else end_drain("nieoczekiwana lokacja po przerwanym zejsciu z promu",room) end
        elseif room.id~=record.boatHash or not boat(room) then
            remembered=nil
            ctx:emit("chimera.paczki.travel.unexpected",{reason="zmiana lokacji podczas przerwanej przeprawy",room=room})
        end
    end
    for _,event in ipairs({"chimera.room.changed","chimera.room.info","chimera.mapper.moved"}) do
        ctx:on(event,function() if active then inspect(active) else passive_room() end end)
    end
    ctx:on("chimera.session.end",function()
        end_drain("rozlaczenie")
        if active then finish(active,false,"rozlaczenie") end
        remembered=nil
    end)
    ctx:on("chimera.paczki.actor.changed",function()
        end_drain("zmieniono postac")
        if active then finish(active,false,"zmieniono postac") end
        remembered=nil
    end)
    ctx:on("chimera.numpad.pressed",function() if active then finish(active,false,"przerwane klawiszem",true) end end)
    if ctx.cleanup then ctx:cleanup(function()
        disposed=true
        end_drain("przeladowanie przeprawy")
        if active then finish(active,false,"przeladowanie przeprawy") end
        remembered=nil
    end) end
    return api
end
