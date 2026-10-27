-- Candidate selection only: no commands, timers or movement.
-- Exact office room hashes/names from Chimera 5.0.0-beta.13 data/world.
-- Vestibules, streets and squares around the post offices are excluded.
local postal = require("chimera_paczki.postal")
local OFFICES = postal.catalogue()
local BY_ID={}
for _,office in ipairs(OFFICES) do BY_ID[office.id]=office end

local function copy(record)
    local out={}
    for key,value in pairs(record) do out[key]=value end
    return out
end
local function valid_map(value)
    return type(value)=="number" and value>0 and value<math.huge and value==math.floor(value)
end
local function valid_cost(value)
    return type(value)=="number" and value>=0 and value<math.huge
end
local function key(source)
    if type(source)=="table" then return source.id end
    if type(source)=="string" then return source end
end
local function capability_id(source)
    local id=key(source)
    if type(id)=="string" and #id==16 and id:match("^[%da-fA-F]+$") then return id:lower() end
end
local ACCENTS={
    ["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z",
    ["Ą"]="a",["Ć"]="c",["Ę"]="e",["Ł"]="l",["Ń"]="n",["Ó"]="o",["Ś"]="s",["Ź"]="z",["Ż"]="z",
}
local function norm(value)
    local text=tostring(value or ""):gsub("\27%[[%d;]*[mK]",""):gsub(" "," ")
    for accent,ascii in pairs(ACCENTS) do text=text:gsub(accent,ascii) end
    return (text:lower():gsub("%s+"," "):gsub("^%s+",""):gsub("[%s%.]+$",""))
end

return function(ctx,navigator,config,now)
    config=config or {}
    now=now or os.time
    local emptyUntil={}
    local noDispatch={}
    local capabilitiesDirty=false
    local api={version="1.5.11"}

    -- Only confirmed absence of a parcel board should enter this map. Empty
    -- boards use the separate, temporary cooldown and never persist here.
    if type(config.loadCapabilities)=="function" then
        local ok,saved=pcall(config.loadCapabilities)
        if ok and type(saved)=="table" and saved.schema==1 and type(saved.noDispatch)=="table" then
            for id,disabled in pairs(saved.noDispatch) do
                local valid=capability_id(id)
                if valid and disabled==true then noDispatch[valid]=true end
            end
        end
    end

    local function cooldown()
        local seconds=tonumber(config.officeCooldown or config.cooldown)
        if not valid_cost(seconds) or seconds<1 then return 600 end
        return seconds
    end
    local function current(source)
        if source then return source end
        return navigator.current and navigator.current() or nil
    end
    local function map_room(id)
        if type(getRoomIDbyHash)~="function" then return nil end
        local ok,value=pcall(getRoomIDbyHash,id)
        if ok and valid_map(value) then return value end
    end
    local function safe_cost(from,to)
        local calculate=navigator.safeCost or navigator.cost
        if type(calculate)~="function" then return nil end
        -- A managed worker is protected by coroutine.resume, and must be
        -- able to yield inside a long route search even on Lua 5.1.
        if config.planning and config.planning() then
            local value=calculate(from,to)
            return valid_cost(value) and value or nil
        end
        local ok,value=pcall(calculate,from,to)
        if ok and valid_cost(value) then return value end
    end

    function api.catalogue()
        local out={}
        for _,office in ipairs(OFFICES) do out[#out+1]=copy(office) end
        return out
    end
    api.catalog=api.catalogue

    function api.markEmpty(source)
        local id=key(current(source))
        if type(id)~="string" or id=="" then return false end
        emptyUntil[id]=now()+cooldown()
        return true
    end

    function api.canDispatch(source)
        local id=key(current(source))
        local office=type(id)=="string" and BY_ID[id:lower()] or nil
        if office and office.deliveryOnly then
            return false,"urzad przyjmuje doreczenia, ale nie nadaje paczek kurierskich"
        end
        if noDispatch[capability_id(id)] then
            return false,"w tym urzedzie potwierdzono brak tablicy nadan paczek kurierskich"
        end
        return true
    end

    function api.markNoDispatch(source)
        local id=capability_id(current(source))
        if not id then return false,"brak poprawnego identyfikatora urzedu" end
        if noDispatch[id] and not capabilitiesDirty then return true end
        noDispatch[id]=true
        if type(config.saveCapabilities)=="function" then
            capabilitiesDirty=true
            local snapshot={schema=1,noDispatch={}}
            for hash in pairs(noDispatch) do snapshot.noDispatch[hash]=true end
            local ok,saved,why=pcall(config.saveCapabilities,snapshot)
            if not ok or saved==false then
                return false,why or "nie udalo sie zapisac informacji o braku nadan"
            end
            capabilitiesDirty=false
        end
        return true
    end

    function api.clear(source)
        if source==nil then emptyUntil={};return end
        local id=key(source)
        if id then emptyUntil[id]=nil end
    end
    function api.clearAll() emptyUntil={} end

    function api.remaining(source)
        local id=key(current(source))
        local expires=id and emptyUntil[id]
        if not expires then return 0 end
        local seconds=expires-now()
        if seconds<=0 then emptyUntil[id]=nil;return 0 end
        return seconds
    end

    local NO_CANDIDATES="brak innej dostepnej poczty nadajacej paczki z bezpieczna droga w obie strony (mapa, ostatnie puste urzedy lub limit drogi)"
    local function selection(source,visited)
        source=current(source)
        if type(source)~="table" or not valid_map(source.map) or type(source.id)~="string" or source.id=="" then
            return nil,"brak potwierdzonej pozycji na mapie"
        end
        if type(navigator.safeCost or navigator.cost)~="function" then
            return nil,"nawigator nie udostepnia bezpiecznego kosztu drogi"
        end
        visited=type(visited)=="table" and visited or {}
        local maximum=tonumber(config.maxOfficeCost)
        if not valid_cost(maximum) then maximum=nil end
        return {source=source,visited=visited,maximum=maximum}
    end
    -- Cost is ONE WAY for relocation. A return route must also exist so the
    -- selector never sends the courier into a one-way map trap. The cost
    -- function is supplied by the navigator, including its transport filter.
    local function candidate(office,search)
        if not api.canDispatch(office) then return nil end
        local source,visited=search.source,search.visited
        local map=map_room(office.id)
        if map and map~=source.map and office.id~=source.id and
            not visited[office.id] and not visited[map] and api.remaining(office)==0 then
            local outward=safe_cost(source.map,map)
            if outward and (not search.maximum or outward<=search.maximum) then
                local back=safe_cost(map,source.map)
                if not back then return nil end
                local result=copy(office)
                result.map=map;result.cost=outward;result.returnCost=back
                result.roundTripCost=outward+back
                result.staticNuln=office.staticNuln==true
                return result
            end
        end
    end

    -- Diagnostics include every eligible office, sorted by outward cost.
    function api.candidates(source,visited)
        local search,reason=selection(source,visited)
        if not search then return {},reason end
        local out={}
        for _,office in ipairs(OFFICES) do
            local result=candidate(office,search)
            if result then out[#out+1]=result end
        end
        table.sort(out,function(a,b)
            if a.cost~=b.cost then return a.cost<b.cost end
            return a.id<b.id
        end)
        if #out==0 then
            return out,NO_CANDIDATES
        end
        return out
    end

    function api.next(source,visited)
        local search,reason=selection(source,visited)
        if not search then return nil,reason end
        -- Prefer the first available office in stable registry order. Avoid
        -- planning every distant office just to find a global minimum.
        for _,office in ipairs(OFFICES) do
            local result=candidate(office,search)
            if result then return result end
        end
        return nil,NO_CANDIDATES
    end

    -- An explicit player choice ignores the automatic empty-office cooldown
    -- and distance limit. It still requires an unambiguous known office and
    -- a safe route in both directions from the player's CURRENT position.
    -- A courier's remembered issuing office must never replace that position.
    function api.resolve(query,source)
        local wanted=norm(query)
        if wanted=="" then return nil,"podaj miasto lub pelna nazwe urzedu pocztowego" end
        local matches={}
        for _,office in ipairs(OFFICES) do
            if wanted==norm(office.city) or wanted==norm(office.name) or wanted==office.id then
                matches[#matches+1]=office
            end
        end
        if #matches==0 then
            -- Preserve exact manual city forms, including the old regional
            -- label and Karak-Varn spelling, without fuzzy name matching.
            local office=postal.resolve(query) or postal.resolve("Poczta w "..tostring(query))
            if office then matches[1]=office end
        end
        if #matches==0 then return nil,"nie ma takiego urzedu na liscie znanych poczt" end
        if #matches>1 then
            local cities={}
            for _,office in ipairs(matches) do cities[#cities+1]=office.city end
            table.sort(cities)
            return nil,"niejednoznaczna nazwa poczty; podaj miasto: "..table.concat(cities,", ")
        end
        local dispatch,dispatchReason=api.canDispatch(matches[1])
        if not dispatch then return nil,dispatchReason end
        local here=source
        if type(navigator.current)=="function" then
            local ok,position=pcall(navigator.current)
            here=ok and position or nil
        end
        if type(here)~="table" or not valid_map(here.map) or type(here.id)~="string" or here.id=="" then
            return nil,"brak potwierdzonej aktualnej pozycji na mapie"
        end
        local office=matches[1]
        local map=map_room(office.id)
        if not map then return nil,"wybranego urzedu nie ma na mapie profilu" end
        local outward,back
        if map==here.map or office.id==here.id then
            if map~=here.map or office.id~=here.id then
                return nil,"niespojna pozycja urzedu na mapie i w GMCP"
            end
            outward,back=0,0
        else
            outward=safe_cost(here.map,map)
            back=outward and safe_cost(map,here.map)
            if not outward or not back then
                return nil,"brak bezpiecznej drogi do wybranej poczty i z powrotem z aktualnej pozycji"
            end
        end
        local candidate=copy(office)
        candidate.map=map;candidate.cost=outward;candidate.returnCost=back
        candidate.roundTripCost=outward+back;candidate.staticNuln=office.staticNuln==true
        return candidate
    end

    return api
end
