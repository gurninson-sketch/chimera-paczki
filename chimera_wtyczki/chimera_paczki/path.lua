-- Read-only fallback when Mudlet's preferred route contains a command the
-- courier cannot execute. Search the LIVE mapped graph without changing any
-- map exits, weights, locks or speedWalk globals.
local DIRECTIONS={
    north={cmd="n",lock="n"},south={cmd="s",lock="s"},east={cmd="e",lock="e"},west={cmd="w",lock="w"},
    northeast={cmd="ne",lock="ne"},northwest={cmd="nw",lock="nw"},southeast={cmd="se",lock="se"},southwest={cmd="sw",lock="sw"},
    up={cmd="u",lock="up"},down={cmd="d",lock="down"},["in"]={cmd="in",lock="in"},out={cmd="out",lock="out"},
}
for long,entry in pairs(DIRECTIONS) do entry.long=long end
local ALIASES={}
for long,entry in pairs(DIRECTIONS) do ALIASES[long]=entry;ALIASES[entry.cmd]=entry end

local function finite(value) return type(value)=="number" and value>=0 and value<math.huge end
local function map_id(value) return finite(value) and value>0 and value==math.floor(value) end
local function bound(value,fallback,maximum)
    if not finite(value) or value<1 then return fallback end
    return math.min(maximum,math.floor(value))
end
local function before(a,b)
    return a.cost<b.cost or (a.cost==b.cost and a.map<b.map)
end
local function push(heap,item)
    local index=#heap+1
    while index>1 do
        local parent=math.floor(index/2)
        if not before(item,heap[parent]) then break end
        heap[index]=heap[parent];index=parent
    end
    heap[index]=item
end
local function pop(heap)
    local first,last=heap[1],table.remove(heap)
    if #heap==0 then return first end
    local index=1
    while index*2<=#heap do
        local child=index*2
        if child<#heap and before(heap[child+1],heap[child]) then child=child+1 end
        if not before(heap[child],last) then break end
        heap[index]=heap[child];index=child
    end
    heap[index]=last
    return first
end

return function(opts)
    opts=opts or {}
    assert(type(opts.hash)=="function","path.hash is required")
    local maxNodes=bound(opts.maxNodes,50000,50000)
    local maxEdges=bound(opts.maxEdges,300000,300000)
    local api={version="1.5.11"}
    local function cooperate()
        -- The owner supplies a no-op outside its managed planning coroutine.
        -- Checkpoints stay outside protected host-API calls for Lua 5.1.
        if type(opts.cooperate)=="function" then opts.cooperate() end
    end

    function api.find(from,target)
        cooperate()
        if not map_id(from) or not map_id(target) then return nil,"nieprawidlowy pokoj mapy" end
        local hashes,weights,locks={}, {}, {}
        local function hash(room)
            if hashes[room]==nil then
                local ok,value=pcall(opts.hash,room)
                hashes[room]=ok and type(value)=="string" and value~="" and value or false
            end
            return hashes[room] or nil
        end
        local fromId,targetId=hash(from),hash(target)
        if not fromId or not targetId then return nil,"brak identyfikatora lokacji na mapie" end
        local plan={from=from,target=target,fromId=fromId,targetId=targetId,cost=0,steps={},commands={},rooms={},weights={}}
        if from==target then return plan end
        local blockedRooms={}
        local function room_blocked(room)
            if blockedRooms[room]~=nil then return blockedRooms[room] end
            if type(opts.blockedRoom)~="function" then return false end
            local ok,reason=pcall(opts.blockedRoom,room)
            blockedRooms[room]=not ok or reason~=nil and reason~=false
            return blockedRooms[room]
        end
        if room_blocked(target) then return nil,"cel prowadzi przez wylaczony niebezpieczny obszar" end
        if type(getRoomExits)~="function" or type(getSpecialExitsSwap)~="function" or type(getRoomWeight)~="function" then
            return nil,"brak API mapy potrzebnego do wyznaczenia objazdu"
        end
        local function room_locked(room)
            if locks[room]==nil then
                if type(roomLocked)~="function" then locks[room]=false
                else
                    local ok,value=pcall(roomLocked,room)
                    locks[room]=not ok or value~=false
                end
            end
            return locks[room]
        end
        if room_locked(from) or room_locked(target) then return nil,"poczatek lub cel objazdu jest zablokowany na mapie" end
        local function blocked(command)
            if type(opts.blocked)~="function" then return false end
            local ok,reason=pcall(opts.blocked,command)
            return not ok or reason~=nil and reason~=false
        end
        local function edge_locked(room,to,command,entry,special)
            if special then
                if type(hasSpecialExitLock)~="function" then return false end
                local ok,value=pcall(hasSpecialExitLock,room,to,command)
                return not ok or value~=false
            end
            if type(hasExitLock)~="function" then return false end
            local ok,value=pcall(hasExitLock,room,entry.lock)
            return not ok or value~=false
        end
        local function room_weight(room)
            if weights[room]==nil then
                local ok,value=pcall(getRoomWeight,room)
                weights[room]=ok and finite(value) and value or false
            end
            return weights[room]
        end
        local function edge_weight(to,raw,command,entry,exitWeights)
            local value=exitWeights[raw]
            if value==nil then value=exitWeights[command] end
            if value==nil and entry then value=exitWeights[entry.lock] end
            if value==nil and entry then value=exitWeights[entry.long] end
            if value~=nil then
                if not finite(value) then return nil end
                if value>0 then return value end
            end
            local destination=room_weight(to)
            return destination~=false and destination or nil
        end
        local distances,previous,settled={[from]=0},{},{}
        local heap={{map=from,cost=0}}
        local nodeCount,edgeCount=1,0
        while #heap>0 do
            cooperate()
            local current=pop(heap)
            local room=current.map
            if not settled[room] and distances[room]==current.cost then
                settled[room]=true
                if room==target then break end
                local ok,ordinary=pcall(getRoomExits,room)
                if not ok or type(ordinary)~="table" then return nil,"nie udalo sie odczytac wyjsc pokoju mapy" end
                local specialOk,special=pcall(getSpecialExitsSwap,room)
                if not specialOk or type(special)~="table" then return nil,"nie udalo sie odczytac przejsc specjalnych mapy" end
                local exitWeights={}
                if type(getExitWeights)=="function" then
                    local weightOk,value=pcall(getExitWeights,room)
                    if not weightOk or type(value)~="table" then return nil,"nie udalo sie odczytac wag wyjsc mapy" end
                    exitWeights=value
                end
                local edges={}
                local function add(raw,to,isSpecial)
                    cooperate()
                    edgeCount=edgeCount+1
                    if edgeCount>maxEdges then return false end
                    if type(raw)~="string" or not map_id(to) or to==room then return true end
                    local entry=not isSpecial and ALIASES[raw:lower()]
                    if not isSpecial and not entry then return true end
                    local command=isSpecial and raw or entry.cmd
                    if blocked(command) or room_blocked(to) or not hash(to) or room_locked(to) or edge_locked(room,to,command,entry,isSpecial) then return true end
                    local weight=edge_weight(to,raw,command,entry,exitWeights)
                    if weight~=nil then edges[#edges+1]={cmd=command,map=to,id=hash(to),weight=weight} end
                    return true
                end
                for direction,to in pairs(ordinary) do
                    if not add(direction,to,false) then return nil,"przekroczono limit krawedzi przy szukaniu objazdu" end
                end
                for command,to in pairs(special) do
                    if not add(command,to,true) then return nil,"przekroczono limit krawedzi przy szukaniu objazdu" end
                end
                table.sort(edges,function(a,b)
                    if a.cmd~=b.cmd then return a.cmd<b.cmd end
                    return a.map<b.map
                end)
                for _,edge in ipairs(edges) do
                    local candidate=current.cost+edge.weight
                    if not settled[edge.map] and finite(candidate) and (distances[edge.map]==nil or candidate<distances[edge.map]) then
                        if distances[edge.map]==nil then
                            nodeCount=nodeCount+1
                            if nodeCount>maxNodes then return nil,"przekroczono limit pokoi przy szukaniu objazdu" end
                        end
                        distances[edge.map]=candidate
                        previous[edge.map]={from=room,edge=edge}
                        push(heap,{map=edge.map,cost=candidate})
                    end
                end
            end
        end
        if not settled[target] then return nil,"brak drogi omijajacej nieobslugiwane przejscia" end
        local reversed,at={},target
        while at~=from do
            cooperate()
            local link=previous[at]
            if not link then return nil,"niepelny wynik szukania objazdu" end
            reversed[#reversed+1]=link.edge;at=link.from
        end
        for index=#reversed,1,-1 do
            cooperate()
            local edge=reversed[index]
            local step={cmd=edge.cmd,map=edge.map,id=edge.id,weight=edge.weight}
            plan.steps[#plan.steps+1]=step;plan.commands[#plan.commands+1]=step.cmd
            plan.rooms[#plan.rooms+1]=step.map;plan.weights[#plan.weights+1]=step.weight
        end
        plan.cost=distances[target]
        return plan
    end
    return api
end
