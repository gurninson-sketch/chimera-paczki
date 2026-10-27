-- Read-only routes for a courier looking for a recipient inside one city.
-- Public world metadata fixes the boundary; mapped shortcuts cannot enlarge it.
-- No special exits, guessed city names or mutations of the map are used.
local DIRECTIONS = {
    north={cmd="n",lock="n"}, south={cmd="s",lock="s"},
    east={cmd="e",lock="e"}, west={cmd="w",lock="w"},
    northeast={cmd="ne",lock="ne"}, northwest={cmd="nw",lock="nw"},
    southeast={cmd="se",lock="se"}, southwest={cmd="sw",lock="sw"},
    up={cmd="u",lock="up"}, down={cmd="d",lock="down"},
    ["in"]={cmd="in",lock="in"}, out={cmd="out",lock="out"},
}
local ALIASES = {}
for name, value in pairs(DIRECTIONS) do
    value.long=name
    ALIASES[name], ALIASES[value.cmd]=value, value
end
local function finite(value)
    return type(value)=="number" and value==value and value>=0 and value<math.huge
end
local function map_id(value)
    return finite(value) and value>0 and value==math.floor(value)
end
local function text(value)
    return type(value)=="string" and value~="" and not value:find("[%z\1-\31\127]")
end

local bundled
-- Public hashes and ordinary links match the patrol observed on 2026-10-27.
-- These three outdoor city rooms lack terrain in 5.0.1; the river crossing
-- itself remains excluded. Never override an explicit terrain or other area.
local PATROL_AREA = "b96cb35a938e6b50"
local PATROL_ROOMS = {
    ["4fa405b9e7ecef09"] = true, -- southern bridge approach
    ["4679c95a3bd909d6"] = true, -- street to the garrison
    ["5f8910ee564c903e"] = true, -- garrison courtyard
}
local function public_room(hash)
    if bundled==nil then
        local ok,value=pcall(require,"chimera_paczki.city_data")
        bundled=ok and type(value)=="table" and type(value.room)=="function" and value or false
    end
    if not bundled then return nil end
    local ok,value=pcall(bundled.room,hash)
    return ok and value or nil
end

return function(opts)
    opts=opts or {}
    local world, mapper=opts.world, opts.mapper
    local limit=finite(opts.maxNodes) and math.max(1,math.min(2048,math.floor(opts.maxNodes))) or 2048
    local api={version="1.5.11"}

    local function checkpoint() if opts.cooperate then opts.cooperate() end end
    local function metadata(hash)
        checkpoint()
        local work=opts.planningCache and opts.planningCache()
        local cached=work and work.cityMetadata and work.cityMetadata[hash]
        if cached then return cached.data,cached.source end
        local function result(data,source)
            if work then
                work.cityMetadata=work.cityMetadata or {}
                work.cityMetadataCount=work.cityMetadataCount or 0
                if work.cityMetadataCount<2048 then
                    work.cityMetadata[hash]={data=data,source=source}
                    work.cityMetadataCount=work.cityMetadataCount+1
                end
            end
            return data,source
        end
        if type(world)=="table" and type(world.room)=="function" then
            local ok,data=pcall(world.room,hash)
            -- A service error or explicit current record is authoritative.
            -- Never override a current forest, mountain, bad identity or area
            -- with a more permissive bundled room of the same hash.
            if not ok then return result(nil,"world_error") end
            if data~=nil then return result(data,"world") end
        end
        return result(public_room(hash),"bundled")
    end

    local function room(map)
        if not map_id(map) or type(mapper)~="table" or type(mapper.chimera_id)~="function" then return nil end
        local ok, hash=pcall(mapper.chimera_id,map)
        if not ok or not text(hash) then return nil end
        if type(getRoomIDbyHash)~="function" then return nil end
        local reverseOk, reverse=pcall(getRoomIDbyHash,hash)
        if not reverseOk or reverse~=map then return nil end
        local data,source=metadata(hash)
        if PATROL_ROOMS[hash] then
            if data==nil and source=="bundled" then
                data={id=hash,area_id=PATROL_AREA,area="Kreutzhofen",terrain="miasto",indoors=false}
                source="verified_patrol"
            elseif type(data)=="table" and (data.id==nil or data.id==hash) and
                data.area_id==PATROL_AREA and data.terrain==nil and data.indoors==false then
                local copy={};for key,value in pairs(data) do copy[key]=value end
                copy.terrain="miasto";data=copy;source="verified_patrol"
            end
        end
        if type(data)~="table" or (data.id~=nil and data.id~=hash) or
            not (data.terrain=="miasto" or (data.terrain==nil and data.indoors==true)) or
            not text(data.area_id) then return nil end
        if type(roomLocked)=="function" then
            local lockOk, locked=pcall(roomLocked,map)
            if not lockOk or locked~=false then return nil end
        end
        if type(opts.blockRoom)=="function" then
            local blockOk, reason=pcall(opts.blockRoom,map,hash)
            if not blockOk or (reason~=nil and reason~=false) then return nil end
        end
        return {map=map,hash=hash,data=data,metadataSource=source}
    end

    local function valid_scope(scope)
        if type(scope)~="table" or not text(scope.areaId) or not text(scope.anchorHash) or
            not map_id(scope.anchorMap) then return nil end
        local anchor=room(scope.anchorMap)
        if not anchor or anchor.hash~=scope.anchorHash or anchor.data.area_id~=scope.areaId then return nil end
        -- Interiors often have no terrain. They belong to the city only
        -- through a separately verified urban room, never through its name.
        local urban=room(scope.urbanMap or scope.anchorMap)
        if not urban or urban.hash~=(scope.urbanHash or scope.anchorHash) or
            urban.data.terrain~="miasto" or urban.data.area_id~=scope.areaId then return nil end
        return anchor
    end

    local read_exits
    local function urban_witness(anchor)
        if anchor.data.terrain=="miasto" then return anchor end
        local scope={areaId=anchor.data.area_id}
        local queue,seen,head={anchor.map},{[anchor.map]=true},1
        while queue[head] do
            checkpoint()
            local map=queue[head]
            head=head+1
            local exits=read_exits(scope,map)
            if not exits then return nil end
            for _,edge in ipairs(exits) do
                if not seen[edge.map] then
                    local destination=room(edge.map)
                    if destination and destination.data.terrain=="miasto" then return destination end
                    if #queue>=limit then return nil end
                    seen[edge.map]=true
                    queue[#queue+1]=edge.map
                end
            end
        end
    end

    function api.scope(route)
        if type(route)~="table" or route.postal or type(route.rooms)~="table" or type(route.roomIds)~="table" then
            return nil,"brak miejskich lokacji adresata"
        end
        for _, map in ipairs(route.rooms) do
            local known=room(map)
            if known and route.roomIds[map]==known.hash then
                local urban=urban_witness(known)
                if urban then
                    return {areaId=known.data.area_id,anchorHash=known.hash,anchorMap=map,name=known.data.area or "miasto",
                        urbanHash=urban.hash,urbanMap=urban.map,
                        metadataSource=known.metadataSource==urban.metadataSource and known.metadataSource or "mixed"}
                end
            end
        end
        return nil,"brak potwierdzonego obszaru miasta adresata"
    end

    function api.contains(scope,map)
        if not valid_scope(scope) then return false end
        local known=room(map)
        return known~=nil and known.data.area_id==scope.areaId
    end

    read_exits=function(scope,from)
        if type(getRoomExits)~="function" or type(getRoomWeight)~="function" then
            return nil,"brak API miejskiej mapy"
        end
        local source=room(from)
        if not source or source.data.area_id~=scope.areaId then return nil,"lokacja poza obszarem miasta" end
        local ok, exits=pcall(getRoomExits,from)
        if not ok or type(exits)~="table" then return nil,"nie mozna odczytac miejskich wyjsc" end
        local weights={}
        if type(getExitWeights)=="function" then
            local weightOk, value=pcall(getExitWeights,from)
            if not weightOk or type(value)~="table" then return nil,"nie mozna odczytac wag miejskich wyjsc" end
            weights=value
        end
        local out={}
        for raw,target in pairs(exits) do
            checkpoint()
            local entry=type(raw)=="string" and ALIASES[raw:lower()]
            if entry and map_id(target) and target~=from then
                local destination=room(target)
                local locked=false
                if type(hasExitLock)=="function" then
                    local lockOk, value=pcall(hasExitLock,from,entry.lock)
                    locked=not lockOk or value~=false
                end
                if destination and destination.data.area_id==scope.areaId and not locked then
                    local weight=weights[raw]
                    if weight==nil then weight=weights[entry.cmd] end
                    if weight==nil then weight=weights[entry.lock] end
                    if weight==nil then weight=weights[entry.long] end
                    if weight==nil or weight==0 then
                        local weightOk, value=pcall(getRoomWeight,target)
                        weight=weightOk and value or false
                    end
                    if finite(weight) then
                        out[#out+1]={cmd=entry.cmd,map=target,id=destination.hash,weight=weight}
                    end
                end
            end
        end
        table.sort(out,function(a,b) return a.map<b.map or (a.map==b.map and a.cmd<b.cmd) end)
        return out
    end

    function api.rooms(scope)
        local anchor=valid_scope(scope)
        if not anchor then return nil,"niepotwierdzony obszar miasta" end
        local queue,seen,head={anchor.map},{[anchor.map]=true},1
        while queue[head] do
            checkpoint()
            local map=queue[head]
            head=head+1
            local exits,why=read_exits(scope,map)
            if not exits then return nil,why end
            for _, edge in ipairs(exits) do
                if not seen[edge.map] then
                    if #queue>=limit then return nil,"przekroczono limit miejskich lokacji" end
                    seen[edge.map]=true
                    queue[#queue+1]=edge.map
                end
            end
        end
        return queue
    end

    function api.plan(scope,from,target)
        if not valid_scope(scope) or not api.contains(scope,from) or not api.contains(scope,target) then
            return nil,"trasa wyszukiwania wychodzi poza potwierdzone miasto"
        end
        local source,destination=room(from),room(target)
        local plan={from=from,fromId=source.hash,target=target,targetId=destination.hash,cost=0,
            steps={},commands={},rooms={},weights={}}
        if from==target then return plan end
        local distance,previous,settled={[from]=0},{},{}
        local queue,count={from},1
        while #queue>0 do
            checkpoint()
            local selected=1
            for i=2,#queue do
                local a,b=queue[i],queue[selected]
                if distance[a]<distance[b] or (distance[a]==distance[b] and a<b) then selected=i end
            end
            local map=table.remove(queue,selected)
            if not settled[map] then
                settled[map]=true
                if map==target then break end
                local exits,why=read_exits(scope,map)
                if not exits then return nil,why end
                for _, edge in ipairs(exits) do
                    local value=distance[map]+edge.weight
                    if not settled[edge.map] and (distance[edge.map]==nil or value<distance[edge.map]) then
                        if distance[edge.map]==nil then
                            if count>=limit then return nil,"przekroczono limit miejskiego planowania" end
                            count=count+1
                            queue[#queue+1]=edge.map
                        end
                        distance[edge.map]=value
                        previous[edge.map]={from=map,edge=edge}
                    end
                end
            end
        end
        if not settled[target] then return nil,"brak dostepnej drogi wewnatrz miasta" end
        local reverse,map={},target
        while map~=from do
            local step=previous[map]
            if not step then return nil,"niepelna miejska trasa" end
            reverse[#reverse+1]=step.edge
            map=step.from
        end
        for index=#reverse,1,-1 do
            local edge=reverse[index]
            local count=#plan.steps+1
            plan.steps[count]={cmd=edge.cmd,map=edge.map,id=edge.id,weight=edge.weight}
            plan.commands[count],plan.rooms[count],plan.weights[count]=edge.cmd,edge.map,edge.weight
        end
        plan.cost=distance[target]
        if plan.cost<=0 then plan.cost=#plan.steps end
        return plan
    end

    return api
end
