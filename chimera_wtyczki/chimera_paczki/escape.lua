-- A single emergency step back along the last *acknowledged* courier edge.
-- This is deliberately separate from delivery execution: the caller cancels
-- forward travel first and retains an explicit emergency ownership lease.
local TIMEOUT = 5
local DIRECTIONS = {
    n="n",s="s",e="e",w="w",ne="ne",nw="nw",se="se",sw="sw",u="u",d="d",
    north="n",south="s",east="e",west="w",northeast="ne",northwest="nw",southeast="se",southwest="sw",
    up="u",down="d",polnoc="n",poludnie="s",wschod="e",zachod="w",
    ["polnocny-wschod"]="ne",["polnocny-zachod"]="nw",["poludniowy-wschod"]="se",["poludniowy-zachod"]="sw",
    gora="u",dol="d",
}
local ASCII = { ["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z",
    ["Ą"]="a",["Ć"]="c",["Ę"]="e",["Ł"]="l",["Ń"]="n",["Ó"]="o",["Ś"]="s",["Ź"]="z",["Ż"]="z" }
local function norm(value)
    local text=tostring(value or ""):gsub("\27%[[%d;]*[mK]", "")
    for accent,ascii in pairs(ASCII) do text=text:gsub(accent,ascii) end
    return (text:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end
local function map_id(value)
    return type(value)=="number" and value>0 and value<math.huge and value==math.floor(value)
end
local function nonempty(value) return type(value)=="string" and value~="" end

return function(ctx,opts)
    opts=opts or {}
    local gmcp,mapper=assert(opts.gmcp),assert(opts.mapper)
    assert(type(opts.send)=="function","escape.send is required")
    assert(type(opts.allow)=="function","escape.allow is required")
    local api,operation,disposed,sending={},nil,false,false

    local function allowed()
        local ok,value=pcall(opts.allow)
        return ok and value==true and not disposed
    end
    local function hash(map)
        local ok,value=pcall(mapper.chimera_id,map)
        return ok and nonempty(value) and value or nil
    end
    local function finish(op,ok,reason)
        if operation~=op then return end
        operation=nil
        if op.timer then ctx:cancel(op.timer);op.timer=nil end
        ctx:emit(ok and "chimera.walk.arrived" or "chimera.walk.stopped",{
            target=op.proof.fromId,map_room=op.proof.fromMap,reason=reason,emergency=true,
        })
        if opts.onDone then opts.onDone({ok=ok,reason=reason,attempts=op.sent and 1 or 0}) end
    end
    function api.cancel(reason)
        if not operation then return false end
        finish(operation,false,reason or "Wycofanie anulowane.")
        return true
    end
    function api.active() return operation~=nil end
    function api.phase() return operation and "escaping" or "idle" end

    local function validate(proof)
        if type(proof)~="table" or not map_id(proof.fromMap) or not map_id(proof.toMap) or
            proof.fromMap==proof.toMap or not nonempty(proof.fromId) or not nonempty(proof.toId) or proof.fromId==proof.toId then
            return nil,"Brak potwierdzonego poprzedniego kroku do wycofania."
        end
        if hash(proof.fromMap)~=proof.fromId or hash(proof.toMap)~=proof.toId then
            return nil,"Mapa nie potwierdza poprzedniego kroku do wycofania."
        end
        if type(gmcp.connected)=="function" and gmcp.connected()~=true then
            return nil,"Brak polaczenia; wycofanie niemozliwe."
        end
        local room=gmcp.room()
        if type(room)~="table" or room.id~=proof.toId or mapper.current_room()~=proof.toMap then
            return nil,"Aktualna lokacja nie potwierdza kroku do wycofania."
        end
        local commands={}
        for command,target in pairs(type(room.exits)=="table" and room.exits or {}) do
            local direction=type(command)=="string" and DIRECTIONS[norm(command)]
            if target==proof.fromId and direction then commands[direction]=true end
        end
        local command
        for direction in pairs(commands) do
            if not command or direction<command then command=direction end
        end
        if not command then return nil,"GMCP nie potwierdza zwyklego wyjscia do poprzedniej lokacji; brak wycofania." end
        return command,room
    end

    function api.start(proof)
        if operation then return false,"Wycofanie jest juz w toku." end
        if not allowed() then return false,"Brak sterowania do awaryjnego wycofania." end
        local command,room=validate(proof)
        if not command then return false,room end
        local character=type(gmcp.char)=="function" and gmcp.char() or nil
        local op={proof={fromId=proof.fromId,fromMap=proof.fromMap,toId=proof.toId,toMap=proof.toMap},
            command=command,key=room.key,actorName=type(character)=="table" and norm(character.name) or nil,
            actorId=type(character)=="table" and character.id or nil}
        operation=op
        ctx:emit("chimera.walk.started",{target=proof.fromId,map_room=proof.fromMap,emergency=true})
        if operation~=op then return false,"Wycofanie zostalo anulowane przed krokiem." end
        -- An event listener can synchronously revoke ownership or change the
        -- room while the walk marker is emitted. Recheck before the sole send.
        local rechecked,why=validate(op.proof)
        if not allowed() or rechecked~=command then
            finish(op,false,not allowed() and "Utracono sterowanie przed wycofaniem." or why)
            return false,"Wycofanie nie zostalo wyslane."
        end
        op.timer=ctx:timer(TIMEOUT,function()
            if operation==op then finish(op,false,"Brak potwierdzenia wycofania; krok nie zostanie powtorzony.") end
        end)
        sending=true;op.sent=true
        local ok,result=pcall(opts.send,command)
        sending=false
        if operation==op and (not ok or result==false) then
            finish(op,false,"Nie udalo sie wyslac awaryjnego wycofania.")
            return false,"Nie udalo sie wyslac awaryjnego wycofania."
        end
        return true
    end

    ctx:on("chimera.room.info",function(room)
        local op=operation
        if not op or type(room)~="table" then return end
        if room.id==op.proof.fromId then
            op.acknowledged=true
            if mapper.current_room()==op.proof.fromMap and hash(op.proof.fromMap)==room.id then finish(op,true,"Wycofano do poprzedniej lokacji. Kurier pozostaje wstrzymany.") end
        elseif room.id~=op.proof.toId or (op.key and room.key~=op.key) then
            finish(op,false,"Lokacja zmienila sie poza potwierdzonym wycofaniem.")
        end
    end)
    ctx:on("chimera.mapper.moved",function(map,room)
        local op=operation
        if not op then return end
        if type(room)~="table" or hash(map)~=room.id then
            finish(op,false,"Mapa nie potwierdza lokacji podczas wycofania.")
        elseif map==op.proof.fromMap and room.id==op.proof.fromId then
            -- The native mapper can emit moved *inside an earlier listener*
            -- of the same Room.Info, before our room.info callback runs.
            -- GMCP has already stored that fresh packet. Verify it directly
            -- rather than depending on listener registration order.
            local current=gmcp.room()
            if type(current)=="table" and current.id==op.proof.fromId and mapper.current_room()==op.proof.fromMap then
                finish(op,true,"Wycofano do poprzedniej lokacji. Kurier pozostaje wstrzymany.")
            else
                finish(op,false,"Biezace GMCP nie potwierdza wycofania na mapie.")
            end
        elseif map~=op.proof.toMap or room.id~=op.proof.toId then
            finish(op,false,"Lokacja zmienila sie poza potwierdzonym wycofaniem.")
        end
    end)
    ctx:on("chimera.char.info",function(character)
        local op=operation
        if not op or type(character)~="table" then return end
        if (op.actorName and norm(character.name)~=op.actorName) or
            (op.actorId and character.id~=op.actorId) or (not op.actorName and not op.actorId) then
            finish(op,false,"Zmieniono postac; wycofanie anulowane.")
        end
    end)
    ctx:on("sysDataSendRequest",function()
        if not sending then api.cancel("Reczna komenda anulowala awaryjne wycofanie.") end
    end)
    for _,event in ipairs({"chimera.session.end","sysDisconnectionEvent","chimera.mapper.lost",
        "chimera.numpad.pressed","chimera.step.manual","chimera.locations.key"}) do
        ctx:on(event,function() api.cancel("Wycofanie anulowane: "..event..".") end)
    end
    ctx:trigger("^",function(text)
        if norm(text or line)=="umierasz." then api.cancel("Smierc postaci; wycofanie anulowane.") end
    end)
    ctx:cleanup(function() disposed=true;api.cancel("Przeladowanie; wycofanie anulowane.") end)
    return api
end
