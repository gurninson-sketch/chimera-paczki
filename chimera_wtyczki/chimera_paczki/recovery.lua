-- Autonomous stationary recovery after an interrupted courier journey.
-- Fresh observations are numbered as received; no raw/cached GMCP replay.
local POLL,QUIET,READY_RETRY,COMBAT_REFRESH=10,1,30,30
local function name(value) return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end
local function present(value) return type(value)=="string" and value~="" end
local function number(value)
    value=tonumber(value)
    return value and value>=0 and value<=100 and value or nil
end
local function map_id(value) return type(value)=="number" and value>0 and value<math.huge and value==math.floor(value) end

return function(ctx,opts)
    opts=opts or {}
    local gmcp,mapper=assert(opts.gmcp),assert(opts.mapper)
    assert(type(opts.send)=="function" and type(opts.allow)=="function","recovery sender and ownership are required")
    local api,operation,disposed,sending={},nil,false,false
    local combatSeq,vitalsSeq=0,0
    local combats,combatOrder,lastVitals={}, {},nil
    local marks=setmetatable({},{__mode="k"})
    local checkReady,poll,refresh

    local function actor()
        local char=gmcp.char()
        if type(char)~="table" or not present(char.name) or not present(char.id) then return end
        return name(char.name),char.id
    end
    local function sameActor(op)
        local currentName,currentId=actor()
        return currentName==op.actorName and currentId==op.actorId
    end
    local function allowed()
        local ok,value=pcall(opts.allow)
        return not disposed and ok and value==true
    end
    local function hash(map)
        local ok,value=pcall(mapper.chimera_id,map)
        return ok and value or nil
    end
    local function position(op)
        local room=gmcp.room()
        if type(gmcp.connected)=="function" and not gmcp.connected() then return false end
        return type(room)=="table" and room.id==op.id and (not op.key or room.key==op.key) and
            mapper.current_room()==op.map and hash(op.map)==op.id
    end
    local function cancelTimer(op,key)
        if op[key] then ctx:cancel(op[key]);op[key]=nil end
    end
    local function finish(op,reason,notify)
        if operation~=op then return end
        operation=nil
        for _,key in ipairs({"pollTimer","quietTimer","readyTimer","refreshTimer"}) do cancelTimer(op,key) end
        if notify and opts.onFailure then opts.onFailure(reason) end
    end
    function api.cancel(reason)
        if not operation then return false end
        finish(operation,reason or "Odpoczynek anulowany.",false);return true
    end
    function api.active() return operation~=nil end
    function api.phase() return operation and "recovering" or "idle" end
    local function safe(op)
        if operation~=op then return false end
        if not allowed() then finish(op,"Utracono sterowanie podczas odpoczynku.",true);return false end
        if not sameActor(op) then finish(op,"Zmieniono postac podczas odpoczynku.",true);return false end
        if not position(op) then finish(op,"Lokacja nie potwierdza bezpiecznego odpoczynku.",true);return false end
        return true
    end
    local function limits()
        local ok,value=pcall(opts.limits or function() return {} end)
        value=ok and type(value)=="table" and value or {}
        local hp,start=tonumber(value.hp),tonumber(value.start or value.fatigue)
        if not hp or hp~=hp or math.abs(hp)==math.huge then hp=80 end
        if not start or start~=start or math.abs(start)==math.huge then start=20 end
        return math.max(80,math.min(100,hp)),math.max(0,math.min(100,start))
    end
    local function vitalReady(op)
        local hp,fatigue=limits()
        return op.vitals and op.vitals.hp>=hp and op.vitals.fatigue<=fatigue
    end
    checkReady=function(op)
        if not safe(op) then return end
        if not op.clear or not op.quiet or not vitalReady(op) then cancelTimer(op,"readyTimer");return end
        if op.readyTimer then return end
        op.readyTimer=ctx:timer(op.retryReady and READY_RETRY or 0.05,function()
            op.readyTimer=nil
            if not safe(op) or not op.clear or not op.quiet or not vitalReady(op) then return end
            -- Keep the lease while the caller replans. Returning false means
            -- no verified route is currently available, so try later in place.
            -- The callback transfers the existing owned lease back to courier
            -- execution and can synchronously send its first verified action.
            -- That send is not manual input and must not cancel the transfer.
            sending=true
            local ok,result=pcall(opts.onReady or function() return false end)
            sending=false
            if operation~=op then return end
            if not ok then finish(op,"Nie udalo sie wznowic kuriera po odpoczynku.",true)
            elseif result==true then op.completed=true;finish(op,nil,false)
            else op.retryReady=true;checkReady(op) end
        end)
    end
    local function observeVitals(op,record)
        if not record or record.seq<=op.vitalsMark or record.actorName~=op.actorName or record.actorId~=op.actorId then return end
        op.vitals=record.hp and record.fatigue and {hp=record.hp,fatigue=record.fatigue} or nil
        checkReady(op)
    end
    local function ownCombat(record,op)
        if record.primary~="" then return true end
        for _,relation in ipairs(record.relations) do
            if type(relation)=="table" and (relation.attacker==op.actorId or relation.defender==op.actorId) then return true end
        end
        return false
    end
    local function observeCombat(op,record)
        if not record or record.seq<=op.combatMark or record.room~=op.id or
            record.actorName~=op.actorName or record.actorId~=op.actorId then return end
        if ownCombat(record,op) then
            op.clear,op.quiet,op.vitals=false,false,nil
            -- Damage and fatigue observations from before this new attack
            -- cannot authorize continuation after the next clear packet.
            op.vitalsMark=vitalsSeq
            cancelTimer(op,"quietTimer");cancelTimer(op,"readyTimer")
        elseif not op.clear then
            op.clear=true;op.quiet=false
            op.quietTimer=ctx:timer(QUIET,function()
                op.quietTimer=nil
                if operation~=op then return end
                op.quiet=true;checkReady(op)
            end)
        end
        checkReady(op)
    end
    function api.mark()
        local actorName,actorId=actor()
        local token={combat=combatSeq,vitals=vitalsSeq}
        marks[token]={combat=combatSeq,vitals=vitalsSeq,actorName=actorName,actorId=actorId}
        return token
    end
    refresh=function(op)
        if not safe(op) then return end
        if type(opts.refreshCombat)=="function" then pcall(opts.refreshCombat) end
        if operation==op then op.refreshTimer=ctx:timer(COMBAT_REFRESH,function() op.refreshTimer=nil;refresh(op) end) end
    end
    poll=function(op)
        if not safe(op) then return end
        sending=true
        local ok,result=pcall(opts.send,"stan")
        sending=false
        if operation~=op then return end
        if not ok or result==false then finish(op,"Nie udalo sie sprawdzic stanu podczas odpoczynku.",true);return end
        op.pollTimer=ctx:timer(POLL,function() op.pollTimer=nil;poll(op) end)
    end
    function api.start(token)
        if operation then return false,"Odpoczynek jest juz w toku." end
        if not allowed() then return false,"Brak sterowania do odpoczynku." end
        local actorName,actorId=actor()
        local room,map=gmcp.room(),mapper.current_room()
        if not actorName or not map_id(map) or type(room)~="table" or not present(room.id) or hash(map)~=room.id or
            (type(gmcp.connected)=="function" and not gmcp.connected()) then
            return false,"Brak aktualnej postaci lub polozenia do odpoczynku."
        end
        local marker
        if token then marker=marks[token];marks[token]=nil
        else marker={combat=combatSeq,vitals=vitalsSeq,actorName=actorName,actorId=actorId} end
        if not marker or marker.actorName~=actorName or marker.actorId~=actorId then return false,"Nieaktualny znacznik odpoczynku postaci." end
        local op={id=room.id,key=room.key,map=map,actorName=actorName,actorId=actorId,
            combatMark=marker.combat,vitalsMark=marker.vitals,clear=false,quiet=false}
        operation=op
        if opts.say then opts.say("Odpoczywam po walce; kurier wznowi sie automatycznie po ustaniu walki i odzyskaniu sil.") end
        observeCombat(op,combats[op.id]);observeVitals(op,lastVitals)
        if operation==op then refresh(op) end
        if operation==op then poll(op) end
        return operation==op or op.completed==true
    end
    ctx:on("chimera.char.vitals",function(vitals)
        vitalsSeq=vitalsSeq+1
        local actorName,actorId=actor()
        local value=type(vitals)=="table" and vitals or {}
        lastVitals={seq=vitalsSeq,actorName=actorName,actorId=actorId,hp=number(value.hp),fatigue=number(value.fatigue)}
        if operation then observeVitals(operation,lastVitals) end
    end)
    ctx:on("chimera.combat.state",function(state)
        combatSeq=combatSeq+1
        if type(state)~="table" or not present(state.room) or type(state.primary)~="string" or type(state.relations)~="table" then
            -- An incomplete fresh packet cannot preserve an earlier "clear"
            -- authorization through an uncertain combat transition.
            local op=operation
            if op then
                op.clear,op.quiet,op.vitals=false,false,nil;op.vitalsMark=vitalsSeq
                cancelTimer(op,"quietTimer");cancelTimer(op,"readyTimer")
            end
            return
        end
        local actorName,actorId=actor()
        local record={seq=combatSeq,room=state.room,primary=state.primary,relations={},actorName=actorName,actorId=actorId}
        for _,relation in ipairs(state.relations) do
            if type(relation)=="table" then table.insert(record.relations,{attacker=relation.attacker,defender=relation.defender}) end
        end
        if not combats[state.room] then
            combatOrder[#combatOrder+1]=state.room
            if #combatOrder>16 then combats[table.remove(combatOrder,1)]=nil end
        end
        combats[state.room]=record
        if operation then observeCombat(operation,record) end
    end)
    ctx:on("chimera.room.info",function(room)
        local op=operation
        if op and (type(room)~="table" or room.id~=op.id or op.key and room.key~=op.key) then
            finish(op,"Zmiana lokacji przerwala odpoczynek.",true)
        end
    end)
    ctx:on("chimera.mapper.moved",function(map,room)
        local op=operation
        if op and (map~=op.map or type(room)~="table" or room.id~=op.id or hash(map)~=op.id) then
            finish(op,"Zmiana polozenia mapy przerwala odpoczynek.",true)
        end
    end)
    ctx:on("chimera.char.info",function()
        if operation and not sameActor(operation) then finish(operation,"Zmieniono postac; odpoczynek anulowany.",true) end
    end)
    ctx:on("sysDataSendRequest",function()
        if operation and not sending then finish(operation,"Reczna komenda przerwala odpoczynek.",true) end
    end)
    for _,event in ipairs({"chimera.session.end","sysDisconnectionEvent","chimera.mapper.lost","chimera.numpad.pressed",
        "chimera.step.manual","chimera.locations.key"}) do
        ctx:on(event,function() if operation then finish(operation,"Odpoczynek przerwany: "..event..".",true) end end)
    end
    ctx:trigger("^",function(text)
        local normalized=name(text or line):gsub("\27%[[%d;]*[mK]", "")
        if operation and normalized=="umierasz." then finish(operation,"Smierc postaci; odpoczynek anulowany.",true) end
    end)
    ctx:cleanup(function() disposed=true;api.cancel("Przeladowanie kuriera.") end)
    return api
end
