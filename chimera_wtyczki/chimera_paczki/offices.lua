-- Candidate selection only: no commands, timers or movement.
-- Exact office room hashes/names from Chimera 5.0.0-beta.13 data/world.
-- Vestibules, streets and squares around the post offices are excluded.
local postal = require("chimera_paczki.postal")
local OFFICES = postal.catalogue()

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
    local api={version="1.5.11"}

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

    -- Cost is ONE WAY for relocation. A return route must also exist so the
    -- selector never sends the courier into a one-way map trap. The cost
    -- function is supplied by the navigator, including its transport filter.
    function api.candidates(source,visited)
        source=current(source)
        if type(source)~="table" or not valid_map(source.map) or type(source.id)~="string" or source.id=="" then
            return {},"brak potwierdzonej pozycji na mapie"
        end
        if type(navigator.safeCost or navigator.cost)~="function" then
            return {},"nawigator nie udostepnia bezpiecznego kosztu drogi"
        end
        visited=type(visited)=="table" and visited or {}
        local out={}
        local maximum=tonumber(config.maxOfficeCost)
        if not valid_cost(maximum) then maximum=nil end
        for _,office in ipairs(OFFICES) do
            local map=map_room(office.id)
            if map and map~=source.map and office.id~=source.id and
                not visited[office.id] and not visited[map] and api.remaining(office)==0 then
                local outward=safe_cost(source.map,map)
                local back=outward and safe_cost(map,source.map)
                if outward and back and (not maximum or outward<=maximum) then
                    local candidate=copy(office)
                    candidate.map=map;candidate.cost=outward;candidate.returnCost=back
                    candidate.roundTripCost=outward+back
                    candidate.staticNuln=office.staticNuln==true
                    out[#out+1]=candidate
                end
            end
        end
        table.sort(out,function(a,b)
            if a.cost~=b.cost then return a.cost<b.cost end
            return a.id<b.id
        end)
        if #out==0 then
            return out,"brak innej dostepnej poczty z bezpieczna droga w obie strony (mapa, ostatnie puste urzedy lub limit drogi)"
        end
        return out
    end

    function api.next(source,visited)
        local candidates,reason=api.candidates(source,visited)
        return candidates[1],reason
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
