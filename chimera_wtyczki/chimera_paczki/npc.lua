-- Chimera 5.0.0-beta.13, courier 1.5.12.
-- Use the /npc catalogue, but keep the search owned and cancellable here:
-- upstream npcs.search cannot cancel its stationary entity-wait interval.
local ENTITY_WAIT = 1.5
local PROBE_WAIT = 4.5 -- upstream NPC NAME_WAIT is 4 seconds
local PROBE_REFRESH = 0.3
local SEARCH_LIMIT = 180 -- inactivity bound; valid movement extends long routes
local PERIODIC_NAME = "annibale malacresta lettore"
local PERIODIC_POLL = 10
local CLOSED_LOCAL_REASON = "lokal zamkniety do rana; krok nie zostal wykonany"
local CITY_RETRY = 30
local CITY_SEARCH_BUDGET = 300 -- total active city search; room activity never refreshes it
local postal = require("chimera_paczki.postal")
local function disabled_postal(id) return postal.disabled(id) end
local ACCENTS = {
    ["ą"] = "a", ["ć"] = "c", ["ę"] = "e", ["ł"] = "l", ["ń"] = "n",
    ["ó"] = "o", ["ś"] = "s", ["ź"] = "z", ["ż"] = "z",
    ["Ą"] = "a", ["Ć"] = "c", ["Ę"] = "e", ["Ł"] = "l", ["Ń"] = "n",
    ["Ó"] = "o", ["Ś"] = "s", ["Ź"] = "z", ["Ż"] = "z",
}

local function norm(value)
    local text = tostring(value or ""):gsub("\27%[[%d;]*[mK]", ""):gsub(" ", " ")
    for accent, ascii in pairs(ACCENTS) do text = text:gsub(accent, ascii) end
    return (text:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("[%s%.]+$", ""))
end

local function phrase(text, wanted)
    text, wanted = norm(text), norm(wanted)
    if wanted == "" then return false end
    local at = 1
    while true do
        local first, last = text:find(wanted, at, true)
        if not first then return false end
        local before, after = text:sub(first - 1, first - 1), text:sub(last + 1, last + 1)
        if not before:match("[%w_]") and not after:match("[%w_]") then return true end
        at = first + 1
    end
end

-- Some postal labels use an occupation instead of the NPC's introduction.
-- Keep these as explicit, complete identities supported by both a successful
-- handover and the public catalogue; never infer them from a first name.
-- New variants can be added here once their complete identity is verified.
local POSTAL_IDENTITIES = {
    ["fryderik miecznik"] = { ["fryderik z nuln"] = true },
}
local function postal_identity(title, full)
    local aliases = POSTAL_IDENTITIES[norm(full)]
    local head = norm(tostring(title or ""):match("^(.-),") or title)
    return aliases and aliases[head] == true or false
end

-- The postal board can omit an NPC's place of origin: e.g. Boreg
-- Khrazaksson / Boreg Khrazaksson z Karak Izor. Accept only that anchored
-- locative suffix, never an arbitrary longer surname or a first-name prefix.
local function title_matches(title, full)
    local head = norm(tostring(title or ""):match("^(.-),") or title)
    local wanted = norm(full)
    if wanted == "" then return false end
    if head == wanted or postal_identity(title, full) then return true end
    -- Confirmed introductions use an honorific omitted by the postal board:
    -- "Don Michael Tommasino, Burmistrz Campogrotty, czlowiek". Strip only
    -- this explicit one-word honorific, never an arbitrary title prefix.
    -- An addressee that itself begins with Don remains a complete name.
    if head:sub(1,4)=="don " and wanted:sub(1,4)~="don " then
        head=head:sub(5)
        if head==wanted then return true end
    end
    if head:sub(1, #wanted) ~= wanted then return false end
    local tail = head:sub(#wanted + 1)
    local place = tail:match("^ z (.+)$") or tail:match("^ ze (.+)$")
    if not place then return false end
    for word in place:gmatch("%S+") do
        if not word:match("^[%a][%a'%-]*$") then return false end
    end
    return true
end

-- Full postal addressees observed in successful deliveries. An alias only
-- supplies a catalogue name; multiple records must still be disambiguated.
local ALIASES = {
    ["rolph ederson"] = "Rolph", ["athelstan shergison"] = "Athelstan",
    ["johan kornwalz"] = "Johan", ["mortimer blatterburn"] = "Mortimer",
    ["gottschalk dahrendorf"] = "Gottschalk", ["elmer golebiarz"] = "Elmer",
    ["berta leibentropp"] = "Berta", ["fryderik miecznik"] = "Fryderik",
    ["henry schmidt"] = "Henry", ["joachim eisenberg"] = "Joachim",
    ["ludwig golebiarz"] = "Ludwig", ["olaf hubner"] = "Olaf",
    ["olaff meier mlodszy"] = "Olaff", ["reinhard fleischer"] = "Reinhard",
    ["rudolf karczmarz"] = "Rudolf",
}

local DIRECTION = {
    n = "polnoc", s = "poludnie", e = "wschod", w = "zachod",
    ne = "polnocny-wschod", nw = "polnocny-zachod",
    se = "poludniowy-wschod", sw = "poludniowy-zachod", u = "gora", d = "dol",
}

local function unsafe_command(command)
    local raw = tostring(command or "")
    if raw:find("[\r\n;]") then return true end
    local text, verb = norm(raw), norm(raw):match("^(%S+)")
    local boarding = { wsiadz = true, zejdz = true, wejdz = true, wyjdz = true,
        wjedz = true, usiadz = true, wysiadz = true }
    if not boarding[verb] then return false end
    for _, vessel in ipairs({ "statek", "statku", "prom", "tratw", "dylizans", "powoz", "woz", "bark", "kryp", "brycz" }) do
        if text:find(vessel, 1, true) then return true end
    end
    return false
end

return function(ctx, bots, gmcp_api, walker, mapper, npcs, locations, sendProbe, idzFn, options)
    local api = { inProgress = false, version = "1.5.12" }
    local operation
    local entityVersion, roomVersions, absentSince = 0, {}, {}
    local entryVersions, sightings, searchAbsences = {}, {}, {}
    local city, cityCombat = options and options.city, false
    options = options or {}
    if not city and options.world then
        city=require("chimera_paczki.city")({world=options.world,mapper=mapper,blockRoom=options.blockRoom,
            cooperate=options.cooperate,planningCache=options.planningCache})
    end
    sendProbe = sendProbe or function(command) return ctx:send(command) end
    local journey
    if not idzFn then
        journey=require("chimera_paczki.journey")(ctx,{gmcp=gmcp_api,mapper=mapper,locations=locations,
            send=sendProbe,delay=options.delay,say=options.say,blockRoom=options.blockRoom,
            prepareFare=options.prepareFare,finishFare=options.finishFare,
            actor=options.actor,loadTransport=options.loadTransport,saveTransport=options.saveTransport,
            coinReceipt=options.coinReceipt,coinsUncertain=options.coinsUncertain,
            cooperate=options.cooperate,planning=options.planning,planningCache=options.planningCache,
            gates=require("chimera_paczki.transport_data").gates})
        idzFn=journey.idz
    end
    local function origin()
        return (journey and journey.originForCost()) or mapper.current_room()
    end
    function api.clearIntent() if journey then journey.clearIntent() end end
    function api.lastEdge() return journey and journey.lastEdge() or nil end
    function api.continueAfterAttack()
        local advanced=false
        if operation and operation.cityScope then
            cityCombat=true
            if operation.cityPace then operation.cityPace(0.05);advanced=true
            elseif not operation.moving and operation.cityAdvance then advanced=operation.cityAdvance() end
        end
        return (journey and journey.continueAfterAttack()) or advanced
    end
    function api.endCombatTransit() cityCombat=false;if journey then journey.endCombatTransit() end end

    function api.current()
        local room = gmcp_api.room() or {}
        return { map = mapper.current_room(), id = room.id, name = room.name }
    end

    function api.source()
        local here = api.current()
        if type(here.map) == "number" and here.map > 0 and here.id and
            norm(here.name):find("poczt", 1, true) then return here end
        return nil
    end

    function api.isPeriodic(route)
        if type(route) ~= "table" or route.native ~= true or route.postal then return false end
        return norm(route.name) == PERIODIC_NAME or
            (norm(route.name) == "annibale" and norm(route.npcName) == "annibale" and phrase(route.npcTitle, PERIODIC_NAME))
    end

    function api.canWaitFor(route)
        if not api.isPeriodic(route) then return false end
        local here = api.current()
        return type(here.map) == "number" and here.map > 0 and type(here.id) == "string" and
            type(route.roomIds) == "table" and route.roomIds[here.map] == here.id and
            type(mapper.chimera_id) == "function" and mapper.chimera_id(here.map) == here.id or false
    end

    local function map_room(id)
        if type(getRoomIDbyHash) ~= "function" then return nil end
        local map = getRoomIDbyHash(id)
        return type(map) == "number" and map > 0 and map or nil
    end

    local function cost(from, to, fromCurrent)
        if journey then
            return journey.quote(from,to,fromCurrent)
        end
        if from == to then return 0 end
        local value = walker.cost(from, to)
        if type(value) ~= "number" or value < 0 or value >= math.huge then return nil end
        -- walker.cost/getPath leaves the selected commands in speedWalkDir.
        -- Chimera's transport module offers hints, not autonomous transfers.
        for _, command in ipairs(speedWalkDir or {}) do
            if unsafe_command(command) then return nil end
        end
        return value
    end
    function api.safeCost(...)
        local value=cost(...)
        return value
    end

    local function catalogue()
        return npcs.all and npcs.all() or {}
    end

    local function find(arg)
        local result = {}
        for _, npc in ipairs(npcs.find(arg) or {}) do result[#result + 1] = npc end
        -- Native find only lowercases ASCII. Include folded catalogue names
        -- as well, including collisions that normalization makes ambiguous.
        local wanted = norm(arg)
        for _, npc in pairs(catalogue()) do
            if norm(npc.name) == wanted or norm(npc.id) == wanted then result[#result + 1] = npc end
        end
        return result
    end

    local function unique(list, full)
        local seen, rows, titles = {}, {}, {}
        for _, npc in ipairs(list or {}) do
            local key = npc.id or (tostring(npc.name) .. "|" .. tostring(npc.short))
            if not seen[key] then
                seen[key], rows[#rows + 1] = true, npc
                if phrase(npc.title, full) or postal_identity(npc.title, full) then titles[#titles + 1] = npc end
            end
        end
        if #titles == 1 then return titles[1] end
        if #titles > 1 or #rows > 1 then return nil, "kilku NPC pasuje do adresata; uzyj /npc " .. full end
        return rows[1]
    end

    local function resolve_npc(name)
        local list = find(name)
        if #list > 0 then return unique(list, name) end
        local by_title = {}
        for _, npc in pairs(catalogue()) do
            if phrase(npc.title, name) or postal_identity(npc.title, name) then by_title[#by_title + 1] = npc end
        end
        if #by_title > 0 then return unique(by_title, name) end
        local first = ALIASES[norm(name)] or tostring(name):match("^%s*(%S+)")
        if first then
            -- A first name is a fallback only when the catalogue has exactly
            -- one such record (or a full title positively disambiguates it).
            local npc, problem = unique(find(first), name)
            if npc and norm(npc.title) ~= "" and not phrase(npc.title, name) and not postal_identity(npc.title, name) then
                local head = norm(tostring(npc.title):match("^(.-),") or npc.title)
                if head ~= norm(npc.name) then
                    return nil, "tytul NPC nie potwierdza pelnego adresata; uzyj /npc " .. name
                end
            end
            return npc, problem
        end
        return nil
    end

    -- A successful delivery binds the complete postal addressee to an NPC,
    -- independently of ambiguous first names in the current /npc catalogue.
    -- Only that exact identity may contribute additional wandering locations.
    local function learned_identity(record, full)
        local identity = {
            id = record.npcId, name = record.npcName or record.name,
            short = record.npcShort or record.short, title = record.npcTitle or record.title,
        }
        -- memory.lua only persists an identity with both a catalogue ID and
        -- name. Partial imported metadata remains a room-only observation.
        if type(identity.id) ~= "string" or norm(identity.id) == "" or
            type(identity.name) ~= "string" or norm(identity.name) == "" then return {} end
        local matched, seen = {}, {}
        local rows = {}
        for _, npc in pairs(catalogue()) do rows[#rows + 1] = npc end
        local lookup = identity.id or identity.name
        if lookup then for _, npc in ipairs(find(lookup)) do rows[#rows + 1] = npc end end
        for _, npc in ipairs(rows) do
            local same = norm(npc.id) == norm(identity.id) and norm(npc.name) == norm(identity.name) and
                (norm(identity.short) == "" or norm(npc.short) == norm(identity.short))
            local key = npc.id or (norm(npc.name) .. "|" .. norm(npc.short))
            local title = norm(npc.title)
            local head = norm(tostring(npc.title or ""):match("^(.-),") or npc.title)
            local contradiction = same and title ~= "" and not phrase(npc.title, full) and
                not postal_identity(npc.title, full) and head ~= norm(npc.name)
            if contradiction then identity.titleConflict = true end
            if same and not contradiction and not seen[key] then seen[key], matched[#matched + 1] = true, npc end
        end
        if #matched == 1 and not identity.titleConflict then
            local npc = matched[1]
            identity.id = identity.id or npc.id
            identity.name = identity.name or npc.name
            identity.short = identity.short or npc.short
            identity.title = identity.title or npc.title
            identity.rooms = npc.rooms
        end
        for _, npc in ipairs(rows) do
            if norm(identity.name) ~= "" and norm(npc.name) == norm(identity.name) and
                ((norm(identity.id) ~= "" and norm(npc.id) ~= norm(identity.id)) or
                (norm(identity.short) ~= "" and norm(npc.short) ~= norm(identity.short))) then
                identity.ambiguousName = true
            end
        end
        return identity
    end

    local function room_only(record)
        if type(record)~="table" or record.postal==true then return false end
        for _,field in ipairs({"npcId","npcName","name","npcShort","short","npcTitle","title"}) do
            if record[field]~=nil and norm(record[field])~="" then return false end
        end
        return true
    end

    -- An older successful delivery may contain a room without an NPC identity.
    -- A unique full name from the current catalogue can enrich that runtime
    -- route; partial or conflicting imported identities are never rebound.
    local function exact_current_identity(full)
        local wanted=norm(full)
        local rows,seen,matched={},{},{}
        for _,npc in pairs(catalogue()) do rows[#rows+1]=npc end
        for _,npc in ipairs(find(full)) do rows[#rows+1]=npc end
        local first=tostring(full or ""):match("^%s*(%S+)")
        if first then for _,npc in ipairs(find(first)) do rows[#rows+1]=npc end end
        for _,npc in ipairs(rows) do
            if type(npc.id)=="string" and norm(npc.id)~="" and type(npc.name)=="string" and norm(npc.name)~="" then
                local title=norm(tostring(npc.title or ""):match("^(.-),") or npc.title)
                local name=norm(npc.name)
                local fullName=name==wanted
                local fullTitle=title_matches(npc.title,full)
                local contradiction=fullName and title~="" and not fullTitle and title~=name
                if (fullName or fullTitle) and not contradiction then
                    local key=norm(npc.id).."|"..name.."|"..norm(npc.short)
                    if not seen[key] then seen[key]=true;matched[#matched+1]=npc end
                end
            end
        end
        if #matched==1 then
            local npc=matched[1]
            return learned_identity({npcId=npc.id,name=npc.name,short=npc.short,title=npc.title},full)
        end
        return nil,#matched>1 and "kilku NPC ma te sama pelna tozsamosc adresata" or
            "brak jednoznacznej pelnej tozsamosci adresata w bazie /npc"
    end

    local function learned_hashes(record)
        local hashes, seen = {}, {}
        local function add(id)
            if type(id) == "string" and id ~= "" and not seen[id] then
                seen[id], hashes[#hashes + 1] = true, id
            end
        end
        -- memory.lua orders this list by the last confirmed delivery.
        for _, id in ipairs(record.roomHashes or {}) do add(id) end
        -- Accept the richer room-set shape too; never interpret a map number
        -- as a portable room identity.
        local extra = {}
        for id, proof in pairs(record.rooms or {}) do
            if type(id) == "string" and proof then extra[#extra + 1] = { id = id, proof = proof } end
        end
        table.sort(extra, function(a, b)
            local ap, bp = type(a.proof) == "table" and a.proof or {}, type(b.proof) == "table" and b.proof or {}
            local ac, bc = tonumber(ap.count) or 0, tonumber(bp.count) or 0
            local al, bl = tonumber(ap.lastSuccess) or 0, tonumber(bp.lastSuccess) or 0
            return ac > bc or (ac == bc and (al > bl or (al == bl and a.id < b.id)))
        end)
        for _, item in ipairs(extra) do add(item.id) end
        return hashes
    end

    local function identity_key(npc)
        if type(npc)~="table" or type(npc.id or npc.npcId)~="string" or
            norm(npc.name or npc.npcName)=="" then return nil end
        return norm(npc.id or npc.npcId).."|"..norm(npc.name or npc.npcName).."|"..norm(npc.short or npc.npcShort)
    end
    local function route_key(route)
        return route and identity_key({id=route.npcId,name=route.npcName,short=route.npcShort})
    end
    local function search_key(route)
        if route and route.roomOnlyIdentity and norm(route.name)~="" then return "recipient:"..norm(route.name) end
        return route_key(route)
    end
    local function sighting(route,hash)
        local key,identity=search_key(route),route_key(route)
        local first=key and sightings[key] and sightings[key][hash]
        local second=identity and sightings[identity] and sightings[identity][hash]
        if not first then return second end
        if second and second.version>first.version then return second end
        return first
    end
    local function upgrade_route_identity(route)
        if type(route)~="table" or not route.roomOnlyIdentity or route.postal or route_key(route) then return false end
        local identity,why=exact_current_identity(route.name)
        if not identity or not identity.id or norm(identity.name)=="" or identity.titleConflict then
            route.identityUpgradeReason=why or "sprzeczna pelna tozsamosc adresata w bazie /npc"
            return false
        end
        route.npcId,route.npcName,route.npcShort,route.npcTitle=identity.id,identity.name,identity.short,identity.title
        route.ambiguousName,route.identityConflict=identity.ambiguousName or nil,nil
        route.locationVerified=nil
        route.identityUpgraded,route.identityUpgradeReason=true,nil
        route.rooms,route.roomIds=route.rooms or {},route.roomIds or {}
        local known={}
        for _,map in ipairs(route.rooms) do known[map]=true end
        for hash,present in pairs(identity.rooms or {}) do
            if present and type(hash)=="string" then
                local map=map_room(hash)
                if map and not known[map] and mapper.chimera_id(map)==hash then
                    known[map]=true;route.rooms[#route.rooms+1]=map;route.roomIds[map]=hash
                end
            end
        end
        return true
    end
    local function city_scope(route)
        if type(route)~="table" or not route.native then return nil,"brak natywnej trasy adresata" end
        if route.postal then return nil,"adresatem jest poczta" end
        if api.isPeriodic(route) then return nil,"adresat okresowy; oczekiwanie w znanym miejscu" end
        if not city then return nil,"brak danych obszarow miasta" end
        upgrade_route_identity(route)
        if route.identityConflict then return nil,"sprzeczna tozsamosc adresata w bazie /npc" end
        if route.learned and route_key(route) then
            local title=norm(tostring(route.npcTitle or ""):match("^(.-),") or route.npcTitle)
            local fullTitle=title_matches(route.npcTitle,route.name)
            local explicitConflict=title~="" and title~=norm(route.npcName) and not fullTitle
            if explicitConflict or (not phrase(route.name,route.npcName) and not fullTitle) then
                route.cityIdentityConflict=true
                return nil,"zapisana tozsamosc NPC nie potwierdza pelnego adresata"
            end
            route.cityIdentityConflict=nil
        end
        if not search_key(route) then return nil,route.identityUpgradeReason or "brak pelnej tozsamosci NPC adresata" end
        if not (journey and journey.runLocal) and not options.runLocal then return nil,"brak wykonawcy miejskich krokow" end
        if route.cityScope then return route.cityScope end
        local scope,why=city.scope(route)
        if scope then
            route.cityScope=scope
            if #route.rooms>1 then route.searchSeconds=CITY_RETRY end
        end
        return scope,why or "brak potwierdzonego obszaru miasta adresata"
    end
    function api.searchStatus(route)
        -- Diagnostics may discover newly available catalogue identity, but
        -- must not upgrade or extend the active courier's actual route.
        local probe
        if type(route)=="table" then
            probe={}
            for key,value in pairs(route) do
                if type(value)=="table" and (key=="rooms" or key=="roomIds" or key=="cityScope") then
                    local detached={}
                    for nested,item in pairs(value) do detached[nested]=item end
                    probe[key]=detached
                else probe[key]=value end
            end
        end
        local scope,why=city_scope(probe)
        return {mode=scope and "city" or "known",reason=scope and "autonomiczne poszukiwanie w potwierdzonym miescie" or why,
            identity=route_key(probe)~=nil and not (probe and (probe.identityConflict or probe.cityIdentityConflict)) or false,
            area=scope and scope.areaId,name=scope and scope.name,npcId=probe and probe.npcId,
            metadataSource=scope and scope.metadataSource,
            knownRooms=probe and type(probe.rooms)=="table" and #probe.rooms or 0,
            upgraded=probe and probe.identityUpgraded==true or false}
    end
    function api.canSearchFor(route)
        local scope=city_scope(route)
        local here=api.current()
        return scope and type(here.map)=="number" and city.contains(scope,here.map) and
            mapper.chimera_id(here.map)==here.id or false
    end

    local function combine_timing(outbound,returning,postal)
        if type(outbound)~="table" or (not postal and type(returning)~="table") then return nil end
        local combined={steps=0,delayUnits=0,gates=0,ferries=0,fareCopper=0,ferryKeys={}}
        local included=postal and {outbound} or {outbound,returning}
        local signatures={postal and "postal" or "npc"}
        for _,part in ipairs(included) do
            if part.fareUnknown then combined.fareUnknown=true end
            for _,field in ipairs({"steps","delayUnits","gates","ferries","fareCopper"}) do combined[field]=combined[field]+(part[field] or 0) end
            for _,key in ipairs(part.ferryKeys or {}) do combined.ferryKeys[#combined.ferryKeys+1]=key end
            signatures[#signatures+1]=part.signature or "unknown"
        end
        combined.delays=combined.delayUnits
        combined.signature=table.concat(signatures,"|")
        return combined
    end
    local function timing_snapshot(candidates,postal,source,from)
        local selected
        for _,candidate in ipairs(candidates) do
            if not selected or candidate.priority<selected.priority or
                (candidate.priority==selected.priority and (candidate.outbound<selected.outbound or
                (candidate.outbound==selected.outbound and candidate.map<selected.map))) then selected=candidate end
        end
        if not selected then return nil end
        local cycle=combine_timing(selected.outboundTiming,selected.returnTiming,postal)
        if not cycle then return nil end
        return {outbound=selected.outboundTiming,returning=selected.returnTiming,cycle=cycle,
            targetId=selected.id,sourceId=source.id,fromId=mapper.chimera_id(from),
            candidateCount=#candidates,uncertain=#candidates>1}
    end
    function api.timing(route,source)
        if not journey or type(route)~="table" or route.native~=true then return nil,"brak geometrii natywnej trasy" end
        source=source or api.current()
        local from=origin()
        if not from or type(source)~="table" or type(source.map)~="number" then return nil,"poza mapa" end
        local candidates={}
        for _,map in ipairs(route.rooms or {}) do
            local outbound,outboundTiming=cost(from,map,true)
            local back,returnTiming=cost(map,source.map)
            if outbound and back then
                candidates[#candidates+1]={map=map,id=route.roomIds and route.roomIds[map] or mapper.chimera_id(map),
                    priority=route.roomPriority and route.roomPriority[map] or 0,outbound=outbound,
                    outboundTiming=outboundTiming,returnTiming=returnTiming}
            end
        end
        return timing_snapshot(candidates,route.postal==true,source,from)
    end

    -- source is optional, but when supplied all candidate rooms must have a
    -- path back to that exact office. cost is outbound + return in map weights.
    function api.resolve(name, source)
        if norm(name) == "" then return nil, "brak adresata" end
        local here = api.current()
        source = source or here
        local from=origin()
        if type(from) ~= "number" or from <= 0 or type(source.map) ~= "number" or source.map <= 0 then
            return nil, "poza mapa"
        end
        local wanted, npc, problem = norm(name)
        -- A verified registry label fixes both the postal kind and its exact
        -- destination. Old memory must not turn it into an NPC or another room.
        local office = postal.resolve(name)
        local memory = options.memory
        local learned
        if not office and memory and type(memory.find) == "function" then
            local ok, record = pcall(memory.find, name)
            if not ok then return nil, "nie mozna odczytac pamieci adresatow" end
            if type(record) == "table" then
                local recipient = record.recipient or record.fullName
                if recipient and norm(recipient) ~= wanted then return nil, "pamiec wskazuje innego adresata" end
                learned = record
            end
        end
        local postal = office ~= nil or (learned and learned.postal == true) or false
        local hashes, learned_ids = {}, {}
        local roomOnlyIdentity,identityUpgraded,identityUpgradeReason=false,false,nil
        if learned then
            npc = learned_identity(learned, name)
            local prior = learned_hashes(learned)
            roomOnlyIdentity=room_only(learned) and #prior>0
            if city and roomOnlyIdentity and not postal and not identity_key(npc) then
                local upgraded,why=exact_current_identity(name)
                if upgraded and upgraded.id and not upgraded.titleConflict then npc=upgraded;identityUpgraded=true
                else identityUpgradeReason=why end
            end
            for rank, id in ipairs(prior) do hashes[id], learned_ids[id] = rank, true end
            for id, exists in pairs(npc.rooms or {}) do
                if exists and type(id) == "string" and not hashes[id] then hashes[id] = #prior + 1 end
            end
        elseif office then
            if office.id == source.id then return nil, "poczta docelowa jest tutaj" end
            hashes[office.id] = 0
        else
            npc, problem = resolve_npc(name)
            if not npc then return nil, problem or "nie ma adresata w bazie /npc" end
            for id, present in pairs(npc.rooms or {}) do
                if present and type(id) == "string" then hashes[id] = 0 end
            end
        end
        -- Session observations are stronger than a historic delivery. They
        -- never overwrite the portable, successful-delivery memory.
        local observed=not postal and sightings[identity_key(npc)] or nil
        if observed then
            for id,seen in pairs(observed) do
                if seen.positive then hashes[id]=-1000000-seen.version
                elseif hashes[id]~=nil then hashes[id]=1000000+hashes[id] end
            end
        end
        local candidates, room_ids, by_map = {}, {}, {}
        for id, priority in pairs(hashes) do
            if options.cooperate then options.cooperate() end
            local map = map_room(id)
            if map and (not postal or (not disabled_postal(id) and map ~= source.map and id ~= source.id)) then
                local outbound,outboundTiming=cost(from,map,true)
                local back,returnTiming=cost(map,source.map)
                if outbound and back then
                    local old = by_map[map]
                    if not old or priority < old.priority or (priority == old.priority and id < old.id) then
                        by_map[map] = { map = map, id = id, priority = priority,
                            outbound = outbound, back = back, total = outbound + back,
                            outboundTiming=outboundTiming,returnTiming=returnTiming }
                    end
                end
            end
        end
        for map, item in pairs(by_map) do candidates[#candidates + 1], room_ids[map] = item, item.id end
        table.sort(candidates, function(a, b)
            return a.priority < b.priority or (a.priority == b.priority and
                (a.total < b.total or (a.total == b.total and a.map < b.map)))
        end)
        if #candidates == 0 then return nil, "brak drogi do adresata i z powrotem do poczty" end
        local best, rooms, priorities, learned_rooms = candidates[1], {}, {}, {}
        for _, candidate in ipairs(candidates) do
            rooms[#rooms + 1], priorities[candidate.map] = candidate.map, candidate.priority
            if learned_ids[candidate.id] then learned_rooms[candidate.map] = true end
        end
        local route = {
            native = true, name = name, npcId = npc and npc.id, commands = {},
            cost = postal and best.outbound or best.total, roundTripCost=best.total,
            outboundCost = best.outbound, returnCost = best.back,
            rooms = rooms, roomIds = room_ids,
            npcName = npc and npc.name, npcShort = npc and npc.short,
            npcTitle = npc and npc.title, postal = postal,
            ambiguousName = learned and npc and npc.ambiguousName or nil,
            identityConflict = learned and npc and npc.titleConflict or nil,
            targetId = office and office.id or (postal and best.id), targetName = office and office.name,
            learned = learned ~= nil, learnedRooms = learned and learned_rooms or nil,
            roomOnlyIdentity=roomOnlyIdentity or nil,identityUpgraded=identityUpgraded or nil,
            identityUpgradeReason=identityUpgradeReason,
            roomPriority = (learned or observed) and priorities or nil,
            locationVerified = learned ~= nil and (norm(npc and npc.name) == "" or npc.titleConflict == true) or nil,
        }
        route.periodic = api.isPeriodic(route) or nil
        if city_scope(route) and #rooms>1 then route.searchSeconds=CITY_RETRY end
        route.timing=timing_snapshot(candidates,postal,source,from)
        return route
    end

    local function clear_timer(op, key)
        local handle = op[key]
        op[key] = nil
        if handle then ctx:cancel(handle) end
    end

    local function finish(op, ok, reason, detail)
        if operation ~= op then return end
        -- Invalidate callbacks before cancel() can synchronously emit stopped.
        operation, api.inProgress = nil, false
        op.moving, op.waiting = false, false
        clear_timer(op, "waitTimer")
        clear_timer(op, "probeRefreshTimer")
        clear_timer(op, "limitTimer")
        clear_timer(op, "searchBudgetTimer")
        clear_timer(op, "periodicProbeTimer")
        clear_timer(op, "cityPaceTimer")
        local cancel = op.cancelAction
        op.cancelAction = nil
        if cancel then cancel() end
        op.done(ok, reason, detail)
    end

    local function watch_limit(op,seconds)
        if operation~=op then return end
        clear_timer(op,"limitTimer")
        op.limitTimer=ctx:timer(seconds or op.transportLimit or SEARCH_LIMIT,function()
            finish(op,false,"limit czasu poszukiwania adresata")
        end)
    end

    local function begin(done)
        if operation then finish(operation, false, "zastapiono nawigacje") end
        local op = { done = done, visited = {}, probed = {} }
        operation, api.inProgress = op, true
        watch_limit(op)
        return op, function() finish(op, false, "przerwane") end
    end

    local function identified(route, snapshot)
        local here = api.current()
        -- The cached entity list can belong to the previous room.
        if not snapshot or not here.id or snapshot.room ~= here.id then return nil end
        local found
        for _, entity in ipairs(snapshot.entities or {}) do
            local name = norm(entity.name)
            -- Catalogue IDs and GMCP entity IDs are different namespaces.
            -- A descriptor (npcShort) alone never establishes identity.
            local descriptor = norm(route.npcShort) ~= "" and name == norm(route.npcShort)
            local full = not route.ambiguousName or norm(route.name) ~= norm(route.npcName)
            local matches = name ~= "" and not descriptor and
                ((not route.ambiguousName and norm(route.npcName) ~= "" and name == norm(route.npcName)) or
                (full and (name == norm(route.name) or phrase(entity.title, route.name) or postal_identity(entity.title, route.name))))
            if matches then
                if entity.kind == "player" then return nil end
                if entity.kind == "npc" and entity.relation ~= "ally" then
                    if found then return nil end
                    found = entity
                end
            end
        end
        return found
    end

    local function present(route, snapshot)
        -- Room-only memories authorize one server-verified handover at their
        -- exact destination, never an identity search along the road.
        return not route.locationVerified and identified(route, snapshot) ~= nil
    end

    local function current_proof(route)
        local proof={}
        for key,value in pairs(route) do proof[key]=value end
        local identity=learned_identity({npcId=route.npcId,name=route.npcName,
            short=route.npcShort,title=route.npcTitle},route.name)
        proof.ambiguousName=identity.ambiguousName or route.ambiguousName
        proof.identityConflict=identity.titleConflict or route.identityConflict
        return proof
    end
    local function city_ready(route,snapshot)
        if not api.canSearchFor(route) then return false end
        local here,key=api.current(),search_key(route)
        local barrier=math.max(entryVersions[here.id] or -1,
            searchAbsences[key] and searchAbsences[key][here.id] or -1)
        if (roomVersions[here.id] or -1)<=barrier then return false end
        if type(snapshot)~="table" or snapshot.room~=here.id then return false end
        local wanted,knownName=norm(route.name),norm(route.npcName)
        for _,entity in ipairs(snapshot.entities or {}) do
            local name=norm(entity.name)
            if name==wanted or (knownName~="" and name==knownName) then
                local title=norm(tostring(entity.title or ""):match("^(.-),") or entity.title)
                -- A current full-title contradiction outweighs an otherwise
                -- matching first name from the catalogue. A generic first
                -- name title is useful only with an already known identity.
                if title~="" and title~=knownName and not title_matches(entity.title,route.name) then return false end
            end
        end
        if not route_key(route) then
            -- A room-only record can authorize a city patrol, not a guessed
            -- first name. Before catalogue enrichment only an exact full
            -- entity name/title is sufficient for this handover.
            local found=nil
            for _,entity in ipairs(snapshot.entities or {}) do
                if norm(entity.name)==wanted or title_matches(entity.title,route.name) then
                    if entity.kind=="player" then return false end
                    if entity.kind=="npc" and entity.relation~="ally" then
                        if found then return false end
                        found=true
                    end
                end
            end
            return found==true
        end
        local proof=current_proof(route)
        return not proof.identityConflict and identified(proof,snapshot)~=nil
    end
    local function observe(snapshot)
        local here=api.current()
        if not city or type(mapper.chimera_id)~="function" or type(snapshot)~="table" or snapshot.room~=here.id or type(here.map)~="number" or
            mapper.chimera_id(here.map)~=here.id then return end
        local rows,counts={},{}
        for _,npc in pairs(catalogue()) do
            rows[#rows+1]=npc
            counts[norm(npc.name)]=(counts[norm(npc.name)] or 0)+1
        end
        for _,npc in ipairs(rows) do
            local key=identity_key(npc)
            if key then
                local title=tostring(npc.title or "")
                local full=title:match("^(.-),") or title
                if norm(full)=="" then full=npc.name end
                local proof={name=full,npcId=npc.id,npcName=npc.name,npcShort=npc.short,
                    npcTitle=npc.title,ambiguousName=counts[norm(npc.name)]>1}
                local seen=identified(proof,snapshot)~=nil
                local previous=sightings[key] and sightings[key][here.id]
                if seen or previous then
                    sightings[key]=sightings[key] or {}
                    sightings[key][here.id]={positive=seen,version=entityVersion,map=here.map}
                end
            end
        end
    end

    local function periodic_proof(route)
        local proof = {}
        for key, value in pairs(route) do proof[key] = value end
        local identity = learned_identity({ npcId = route.npcId, name = route.npcName,
            short = route.npcShort, title = route.npcTitle }, route.name)
        proof.ambiguousName = identity.ambiguousName or identity.titleConflict or nil
        -- A room-only memory can acquire a positively identified /npc entry
        -- later. A matching first name or descriptor alone is insufficient.
        if not proof.npcId or norm(proof.npcName) == "" then
            local npc = resolve_npc(PERIODIC_NAME)
            if npc and (norm(npc.name) == PERIODIC_NAME or phrase(npc.title, PERIODIC_NAME)) then
                proof.npcId, proof.npcName, proof.npcShort, proof.npcTitle = npc.id, npc.name, npc.short, npc.title
            end
        end
        return proof
    end

    local function periodic_ready(route, snapshot)
        if not api.canWaitFor(route) then return false end
        local id = api.current().id
        if absentSince[id] and (roomVersions[id] or 0) <= absentSince[id] then return false end
        return identified(periodic_proof(route), snapshot) ~= nil
    end

    function api.deliveryReady(route)
        local scope=city_scope(route)
        if route and route.cityIdentityConflict then return false end
        if scope then return city_ready(route,gmcp_api.entities()) end
        return not api.isPeriodic(route) or periodic_ready(route, gmcp_api.entities())
    end

    function api.recipientAbsent(route)
        if api.canSearchFor(route) then
            local here,key=api.current(),search_key(route)
            searchAbsences[key]=searchAbsences[key] or {}
            searchAbsences[key][here.id]=entityVersion
            sightings[key]=sightings[key] or {}
            sightings[key][here.id]={positive=false,version=entityVersion,map=here.map}
            return true
        end
        if not api.canWaitFor(route) then return false end
        -- Set the freshness barrier before the next navigation can refresh
        -- GMCP synchronously. The current cached named row cannot retry a gift.
        absentSince[api.current().id] = entityVersion
        return true
    end

    function api.phase()
        local op = operation
        return op and (op.periodicWaiting and "waiting_recipient" or
            (op.cityWaiting and "searching_city" or (op.moving and "moving" or "checking"))) or nil
    end

    -- Capture this at handover, before the reward may arrive in another room.
    -- The core adds the actual handover/payment proof; this method alone does
    -- not make a successful delivery or a persistent memory entry.
    function api.deliveryEvidence(route)
        if type(route) ~= "table" or norm(route.name) == "" then return nil end
        local here = api.current()
        if type(here.map) ~= "number" or here.map <= 0 or type(here.id) ~= "string" or here.id == "" then return nil end
        local evidence = { recipient = route.name, roomHash = here.id, map = here.map,
            postal = route.postal == true, verified = false }
        if type(mapper.chimera_id) == "function" then
            evidence.verified = mapper.chimera_id(here.map) == here.id
        end
        -- A long trip can introduce additional /npc records. Recheck the
        -- current catalogue when capturing proof, without changing the plan.
        local proofRoute = {}
        for key, value in pairs(route) do proofRoute[key] = value end
        local identity = learned_identity({ npcId = route.npcId, name = route.npcName,
            short = route.npcShort, title = route.npcTitle }, route.name)
        proofRoute.ambiguousName, proofRoute.identityConflict = identity.ambiguousName, identity.titleConflict
        local entity = identified(proofRoute, gmcp_api.entities())
        if entity and not route.postal and not proofRoute.identityConflict and
            type(route.npcId) == "string" and norm(route.npcId) ~= "" then
            evidence.npc = { npcId = route.npcId, name = route.npcName or entity.name,
                short = route.npcShort, title = route.npcTitle or entity.title }
        end
        return evidence
    end

    -- This establishes a candidate to ask the server about, never identity.
    -- Descriptors are only useful at the exact mapped catalogue destination;
    -- the same descriptor encountered along the route proves nothing.
    local function candidate(op, snapshot)
        local route, here = op.route, api.current()
        if not route or route.postal or not op.target or here.map ~= op.target or
            not route.roomIds or route.roomIds[op.target] ~= here.id or
            not snapshot or snapshot.room ~= here.id then return false end
        local count = 0
        for _, entity in ipairs(snapshot.entities or {}) do
            local descriptor = norm(route.npcShort) ~= "" and norm(entity.name) == norm(route.npcShort)
            local ambiguous = route.learned and route.ambiguousName and norm(route.npcName) ~= "" and
                norm(entity.name) == norm(route.npcName)
            if descriptor or ambiguous then
                if entity.kind == "player" then return false end
                if entity.kind == "npc" and entity.relation ~= "ally" then count = count + 1 end
            end
        end
        return count == 1
    end

    local function city_candidate(op,snapshot)
        local route,here=op.route,api.current()
        if not op.cityScope or not city.contains(op.cityScope,here.map) or
            type(snapshot)~="table" or snapshot.room~=here.id then return false end
        if not route_key(route) and route.roomOnlyIdentity then
            for _,entity in ipairs(snapshot.entities or {}) do
                if entity.kind=="npc" and entity.relation~="ally" then return true end
            end
            return false
        end
        if norm(route.npcShort)=="" then return false end
        local count=0
        for _,entity in ipairs(snapshot.entities or {}) do
            if norm(entity.name)==norm(route.npcShort) then
                if entity.kind=="player" then return false end
                if entity.kind=="npc" and entity.relation~="ally" then count=count+1 end
            end
        end
        -- This permits an introduction on an urban street, never a gift.
        return count==1
    end

    local function walk(op, map, callback)
        op.moving = true
        local completed = false
        local cancel = idzFn(map, function(result)
            completed = true
            if operation ~= op then return end
            op.cancelAction, op.moving = nil, false
            callback(result or { ok = false, reason = "brak wyniku chodzika" })
        end)
        -- idz can complete synchronously when already at the destination.
        if operation == op and not completed then op.cancelAction = cancel
        elseif not completed and cancel then cancel() end
    end

    local function periodic_refresh(op)
        if operation == op and op.periodicWaiting and type(gmcp_api.refresh_entities) == "function" then
            pcall(gmcp_api.refresh_entities)
        end
    end

    local function periodic_check(op, snapshot)
        if operation ~= op or not op.periodicWaiting then return end
        if not api.canWaitFor(op.route) then
            finish(op, false, "zmiana lub brak potwierdzenia lokacji oczekiwania")
            return
        end
        if periodic_ready(op.route, snapshot) then finish(op, true); return end
        local here, proof = api.current(), periodic_proof(op.route)
        if type(snapshot) ~= "table" or snapshot.room ~= here.id then return end
        -- Shared addresses may contain only a server-confirmed delivery room.
        -- At that exact berth, introduce to the anonymous NPCs so native /npc
        -- can learn the captain's full identity. This is a probe, never proof
        -- for handing over a parcel or permission to follow a ship.
        local roomOnly = op.route.roomOnlyIdentity and not route_key(proof)
        local count, player, candidates = 0, false, {}
        for _, entity in ipairs(snapshot.entities or {}) do
            if roomOnly then
                if entity.kind == "npc" and entity.relation ~= "ally" then
                    count = count + 1
                    candidates[#candidates + 1] = tostring(entity.id or "") .. ":" .. norm(entity.name)
                end
            elseif norm(proof.npcShort) ~= "" and norm(entity.name) == norm(proof.npcShort) then
                if entity.kind == "player" then player = true
                elseif entity.kind == "npc" and entity.relation ~= "ally" then count = count + 1 end
            end
        end
        if count == 0 and not player then op.periodicIntroduced = nil end
        table.sort(candidates)
        local presence = roomOnly and table.concat(candidates, "|") or true
        if count == 0 or (not roomOnly and count ~= 1) or player or
            op.periodicIntroduced == presence or op.periodicProbeBlocked then return end
        -- Introduce once for this observed presence, with a rate limit even
        -- if rapid snapshots alternate absent/present. A descriptor never
        -- completes the wait or authorizes handing over a parcel.
        op.periodicIntroduced, op.periodicProbeBlocked = presence, true
        local sent, result = pcall(sendProbe, "przedstaw sie")
        if operation ~= op then return end
        if not sent or result == false then finish(op, false, "nie udalo sie przedstawic adresatowi"); return end
        op.periodicProbeTimer = ctx:timer(PERIODIC_POLL, function()
            if operation ~= op then return end
            op.periodicProbeTimer, op.periodicProbeBlocked = nil, false
        end)
        periodic_refresh(op)
        if operation ~= op then return end
        clear_timer(op, "probeRefreshTimer")
        op.probeRefreshTimer = ctx:timer(PROBE_REFRESH, function()
            if operation ~= op then return end
            op.probeRefreshTimer = nil
            periodic_refresh(op)
        end)
    end

    local function periodic_wait(op)
        if operation ~= op or not api.canWaitFor(op.route) then
            if operation == op then finish(op, false, "brak potwierdzonej lokacji oczekiwania") end
            return
        end
        clear_timer(op, "limitTimer")
        clear_timer(op, "waitTimer")
        clear_timer(op, "probeRefreshTimer")
        op.moving, op.waiting, op.periodicWaiting, op.atId = false, true, true, api.current().id
        if not op.waitAnnounced then
            op.waitAnnounced = true
            if type(options.onWait) == "function" then pcall(options.onWait, op.route, api.current()) end
            if operation ~= op then return end
        end
        local poll
        poll = function()
            if operation ~= op then return end
            periodic_check(op, gmcp_api.entities())
            if operation ~= op then return end
            periodic_refresh(op)
            if operation ~= op then return end
            periodic_check(op, gmcp_api.entities())
            if operation ~= op then return end
            op.waitTimer = ctx:timer(PERIODIC_POLL, function()
                if operation ~= op then return end
                op.waitTimer = nil
                poll()
            end)
        end
        poll()
    end

    -- Search remains inside one verified urban area. Each ordinary edge is
    -- acknowledged by the same road engine before checking the next room;
    -- seeing an entity before that ACK never hands over a parcel in transit.
    local function search_city(op)
        if operation~=op then return end
        if op.cityInspect then op.cityInspect();return true end
        local route,scope=op.route,city_scope(op.route)
        if not scope or not api.canSearchFor(route) then return false end
        -- Same-area urban rooms can belong to disconnected patrol components:
        -- for example Kreutzhofen's streets on opposite sides of the Soll.
        -- The ordinary bridge has no urban terrain metadata. A known delivery
        -- destination still has a verified road quotation, so reach one of its
        -- known rooms through the normal owned journey before starting a city
        -- patrol. Keep the stricter city boundary unchanged for exploration.
        local here,connected=api.current(),false
        for _,map in ipairs(route.rooms or {}) do
            if route.roomIds and mapper.chimera_id(map)==route.roomIds[map] and city.contains(scope,map) and
                (map==here.map or city.plan(scope,here.map,map)) then connected=true;break end
        end
        if not connected then return false end
        if not op.cityBudgetStarted then
            op.cityBudgetStarted=true
            if options.onSearchStart then
                local ok=pcall(options.onSearchStart,route,scope)
                if not ok then finish(op,false,"nie mozna rozpoczac limitu szukania adresata");return true end
            end
            if operation~=op then return true end
            local seconds=CITY_SEARCH_BUDGET
            if options.searchBudget then
                local ok,value=pcall(options.searchBudget,route)
                if not ok or type(value)~="number" or value~=value or value>=math.huge then
                    finish(op,false,"nie mozna ustalic limitu szukania adresata");return true
                end
                seconds=value
            end
            if seconds<=0 then finish(op,false,"limit czasu szukania adresata w miescie");return true end
            op.searchBudgetTimer=ctx:timer(seconds,function()
                if operation~=op then return end
                op.searchBudgetTimer=nil
                finish(op,false,"limit czasu szukania adresata w miescie")
            end)
        end
        op.cityScope,op.cityVisited,op.cityProbed=scope,{},{}
        op.cityClosed=op.cityClosed or {}
        local function available_plan(plan)
            for _,step in ipairs(plan and plan.steps or {}) do
                if op.cityClosed[step.map] then return nil end
            end
            return plan
        end
        local key=search_key(route)
        local inspect,choose,probe,wait_round
        local function valid_here()
            local here=api.current()
            return type(here.map)=="number" and mapper.chimera_id(here.map)==here.id and city.contains(scope,here.map)
        end
        local function ready()
            if op.cityEscapeRoom and api.current().id==op.cityEscapeRoom then return false end
            if not city_ready(route,gmcp_api.entities()) then return false end
            if options.onRoadArrival and options.onRoadArrival()==true then return true end
            finish(op,true)
            return true
        end
        local function refresh_known()
            local identity=learned_identity({npcId=route.npcId,name=route.npcName,
                short=route.npcShort,title=route.npcTitle},route.name)
            if identity.titleConflict then route.identityConflict=true;return end
            if identity.ambiguousName then route.ambiguousName=true end
            local seen={}
            for _,map in ipairs(route.rooms) do seen[map]=true end
            local function add(id)
                local map=map_room(id)
                if map and not seen[map] and mapper.chimera_id(map)==id and city.contains(scope,map) then
                    seen[map]=true;route.rooms[#route.rooms+1]=map
                    route.roomIds[map]=id
                end
            end
            for id,present in pairs(identity.rooms or {}) do if present then add(id) end end
            for id,record in pairs(sightings[key] or {}) do if record.positive then add(id) end end
            local identityKey=route_key(route)
            for id,record in pairs(identityKey and sightings[identityKey] or {}) do if record.positive then add(id) end end
        end
        local function stop_checks()
            clear_timer(op,"waitTimer")
            clear_timer(op,"probeRefreshTimer")
            op.waiting,op.cityWaiting=false,false
        end
        local function move(plan)
            if operation~=op then return end
            local step=plan.steps and plan.steps[1]
            if not step then inspect();return end
            local one={from=plan.from,fromId=plan.fromId,target=step.map,targetId=step.id,
                cost=step.weight or 1,steps={step},commands={step.cmd},rooms={step.map},weights={step.weight or 1}}
            local function execute()
                if operation~=op then return end
                op.cityPace=nil
                if not valid_here() then finish(op,false,"opuszczono potwierdzony obszar poszukiwan");return end
                -- Locks/hazards may change during the pace timer. Rebuild this
                -- single edge instead of executing the old multi-step plan.
                local live=city.plan(scope,api.current().map,one.target)
                if not live or not live.steps or #live.steps~=1 then choose();return end
                op.moving=true
                local completed=false
                local run=options.runLocal or (journey and journey.runLocal)
                local cancel=run(live,function(result)
                    completed=true
                    if operation~=op then return end
                    op.cancelAction,op.moving=nil,false
                    if not result or not result.ok then
                        if result and result.reason==CLOSED_LOCAL_REASON then
                            local here=api.current()
                            if here.map==one.from and here.id==one.fromId then
                                op.cityClosed[one.target]=true
                                op.cityVisited[one.target]=true
                                inspect();return
                            end
                        end
                        finish(op,false,result and result.reason or "krok poszukiwan niepotwierdzony");return
                    end
                    local here=api.current()
                    if here.map~=one.target or here.id~=one.targetId then finish(op,false,"niezgodna lokacja po kroku poszukiwan");return end
                    if op.cityEscapeRoom~=here.id then op.cityEscapeRoom=nil end
                    op.localPaced=true
                    inspect()
                end)
                if operation==op and not completed then op.cancelAction=cancel
                elseif not completed and cancel then cancel() end
            end
            local function pace(seconds)
                if operation~=op or op.moving then return end
                clear_timer(op,"cityPaceTimer")
                seconds=tonumber(seconds) or 0.5
                if seconds~=seconds or seconds<0 or seconds>=math.huge then seconds=0.5 end
                op.cityPaceTimer=ctx:timer(seconds,function()
                    op.cityPaceTimer=nil
                    if operation~=op then return end
                    ctx:emit("chimera.paczki.timing.delay",{seconds=seconds})
                    execute()
                end)
            end
            op.cityPace=pace
            if op.localPaced or cityCombat then pace(cityCombat and 0.05 or (options.delay and options.delay() or 0.5))
            else execute() end
        end
        wait_round=function()
            if operation~=op then return end
            stop_checks()
            watch_limit(op)
            op.waiting,op.cityWaiting,op.atId=true,true,api.current().id
            if options.onSearchWait then pcall(options.onSearchWait,route,scope) end
            if operation~=op then return end
            op.waitTimer=ctx:timer(CITY_RETRY,function()
                op.waitTimer=nil
                if operation~=op then return end
                op.waiting,op.cityWaiting=false,false
                op.cityVisited,op.cityProbed,op.cityRooms={},{},nil
                watch_limit(op)
                inspect()
            end)
        end
        choose=function()
            if operation~=op then return end
            stop_checks()
            if not valid_here() then finish(op,false,"brak potwierdzenia miejskiego obszaru poszukiwan");return end
            local avoidCurrent=op.cityAvoidCurrent
            op.cityAvoidCurrent=nil
            if not avoidCurrent and ready() then return end
            refresh_known()
            if route.identityConflict and not cityCombat then finish(op,false,"baza NPC wskazuje sprzeczna tozsamosc adresata");return end
            local here,bestPlan,bestRank=api.current()
            for _,map in ipairs(route.rooms) do
                if not op.cityVisited[map] and not op.cityClosed[map] and city.contains(scope,map) then
                    local record=sighting(route,route.roomIds[map])
                    local rank=route.roomPriority and route.roomPriority[map] or 0
                    if record then rank=record.positive and (-1000000-record.version) or (1000000+rank) end
                    local plan=available_plan(city.plan(scope,here.map,map))
                    if plan and (not bestPlan or rank<bestRank or (rank==bestRank and plan.cost<bestPlan.cost)) then
                        bestPlan,bestRank=plan,rank
                    end
                end
            end
            if not bestPlan then
                -- BFS enumeration avoids computing a separate shortest path
                -- for every urban room after each ACK in a large city.
                if not op.cityRooms then op.cityRooms=city.rooms(scope) or {} end
                for _,map in ipairs(op.cityRooms) do
                    if not op.cityVisited[map] and not op.cityClosed[map] then
                        bestPlan=available_plan(city.plan(scope,here.map,map))
                        if bestPlan then break end
                        op.cityVisited[map]=true
                    end
                end
            end
            if bestPlan then move(bestPlan) else wait_round() end
        end
        probe=function()
            if operation~=op then return end
            local here=api.current()
            if op.cityProbed[here.map] or not city_candidate(op,gmcp_api.entities()) then choose();return end
            op.cityProbed[here.map]=true
            op.waiting,op.atId=true,here.id
            local sent,result=pcall(sendProbe,"przedstaw sie")
            if operation~=op then return end
            if not sent or result==false then finish(op,false,"nie udalo sie przedstawic adresatowi");return end
            if gmcp_api.refresh_entities then pcall(gmcp_api.refresh_entities) end
            if operation~=op then return end
            op.probeRefreshTimer=ctx:timer(PROBE_REFRESH,function()
                op.probeRefreshTimer=nil
                if operation==op and gmcp_api.refresh_entities then pcall(gmcp_api.refresh_entities) end
            end)
            op.waitTimer=ctx:timer(PROBE_WAIT,function()
                op.waitTimer=nil
                if operation~=op then return end
                op.waiting=false
                if not ready() then choose() end
            end)
        end
        inspect=function()
            if operation~=op or op.moving then return end
            stop_checks()
            watch_limit(op)
            if not valid_here() then finish(op,false,"brak potwierdzenia miejskiego obszaru poszukiwan");return end
            if ready() then return end
            local here=api.current()
            op.cityVisited[here.map],op.target=true,here.map
            refresh_known()
            if route.identityConflict and not cityCombat then finish(op,false,"baza NPC wskazuje sprzeczna tozsamosc adresata");return end
            op.waiting,op.atId=true,here.id
            if gmcp_api.refresh_entities then pcall(gmcp_api.refresh_entities) end
            if operation~=op then return end
            if ready() then return end
            op.waitTimer=ctx:timer(ENTITY_WAIT,function()
                op.waitTimer=nil
                if operation~=op then return end
                op.waiting=false
                if not ready() then probe() end
            end)
        end
        op.cityInspect=inspect
        op.cityReady=ready
        op.cityAdvance=function()
            if operation~=op or op.moving then return false end
            stop_checks()
            clear_timer(op,"cityPaceTimer")
            op.cityPace=nil
            local here=api.current()
            -- An NPC attack ends stationary recipient checks. The current
            -- room is excluded for this immediate choice, even if it was a
            -- full-round pause or the intended recipient is also present.
            op.cityVisited={[here.map]=true}
            op.cityEscapeRoom=here.id
            op.cityAvoidCurrent=true
            choose()
            return operation==op
        end
        inspect()
        return true
    end

    function api.navigate(route, done)
        local op, cancel = begin(done)
        op.route = route
        if type(route) ~= "table" or not route.native or not route.rooms or #route.rooms == 0 then
            finish(op, false, "brak lokacji adresata")
            return cancel
        end
        local next_room, probe
        probe = function()
            if operation ~= op or op.probed[op.target] or not candidate(op, gmcp_api.entities()) then return false end
            op.probed[op.target] = true
            clear_timer(op, "waitTimer")
            op.waiting, op.atId = true, api.current().id
            -- The adapter injects the core's owned-send function. A plain
            -- standalone context can use the default sender above.
            local sent, result = pcall(sendProbe, "przedstaw sie")
            if operation ~= op then return true end
            if not sent or result == false then
                finish(op, false, "nie udalo sie przedstawic adresatowi")
                return true
            end
            -- Introductions can finish after the first refresh. Request one
            -- bounded follow-up, then wait for the normal NPC/GMCP listeners.
            if gmcp_api.refresh_entities then gmcp_api.refresh_entities() end
            if operation ~= op then return true end
            op.probeRefreshTimer = ctx:timer(PROBE_REFRESH, function()
                op.probeRefreshTimer = nil
                if operation == op and gmcp_api.refresh_entities then gmcp_api.refresh_entities() end
            end)
            op.waitTimer = ctx:timer(PROBE_WAIT, function()
                op.waitTimer, op.waiting = nil, false
                if operation ~= op then return end
                if present(route, gmcp_api.entities()) then finish(op, true)
                elseif candidate(op, gmcp_api.entities()) then
                    local here = api.current()
                    -- Reaching this candidate is not a delivery. The core
                    -- may attempt oddaj paczke once; only the game's handover
                    -- and payment responses can confirm delivery and profit.
                    finish(op, true, nil, { candidate = true, map = here.map, id = here.id, npcId = route.npcId })
                else next_room() end
            end)
            return true
        end
        local function inspect()
            if operation ~= op then return end
            local here = api.current()
            if route.postal then
                local expected = route.learned and route.roomIds and route.roomIds[op.target] or route.targetId
                if here.id == expected then finish(op, true)
                else finish(op, false, "niezgodna lokacja poczty docelowej") end
                return
            end
            if api.isPeriodic(route) then
                if periodic_ready(route, gmcp_api.entities()) then finish(op, true)
                else periodic_wait(op) end
                return
            end
            if city_scope(route) and api.canSearchFor(route) and search_city(op) then return end
            if (route.locationVerified or route.ambiguousName) and route.learnedRooms and route.learnedRooms[op.target] and
                route.roomIds and here.map == op.target and here.id == route.roomIds[op.target] then
                finish(op, true, nil, { candidate = true, locationVerified = true, map = here.map, id = here.id })
                return
            end
            if present(route, gmcp_api.entities()) then finish(op, true); return end
            if probe() then return end
            op.waiting, op.atId = true, here.id
            -- Refresh via GMCP, not a MUD command that could be mistaken for
            -- manual takeover; the refresh does not move the character.
            if gmcp_api.refresh_entities then gmcp_api.refresh_entities() end
            if operation ~= op then return end
            op.waitTimer = ctx:timer(ENTITY_WAIT, function()
                op.waitTimer, op.waiting = nil, false
                if operation ~= op then return end
                if present(route, gmcp_api.entities()) then finish(op, true)
                elseif not probe() then next_room() end
            end)
        end
        next_room = function()
            if operation ~= op then return end
            local from, target, best, priority = origin()
            for _, map in ipairs(route.rooms) do
                if not op.visited[map] then
                    local distance = from and cost(from, map,true)
                    local rank = route.roomPriority and route.roomPriority[map] or 0
                    if distance and (not best or rank < priority or
                        (rank == priority and (distance < best or (distance == best and map < target)))) then
                        target, best, priority = map, distance, rank
                    end
                end
            end
            if not target then finish(op, false, "nie znaleziono adresata w znanych lokacjach"); return end
            op.visited[target], op.target = true, target
            walk(op, target, function(result)
                if not result.ok then finish(op, false, result.reason or "chodzik zatrzymany"); return end
                local here = api.current()
                if here.map ~= target or (route.roomIds and here.id ~= route.roomIds[target]) then
                    finish(op, false, "niezgodna lokacja po dojsciu")
                    return
                end
                if options.onRoadArrival and options.onRoadArrival()==true then return end
                inspect()
            end)
        end
        if api.isPeriodic(route) and api.canWaitFor(route) then
            op.target = api.current().map
            if periodic_ready(route, gmcp_api.entities()) then finish(op, true)
            else periodic_wait(op) end
        elseif city_scope(route) and api.canSearchFor(route) then
            if not search_city(op) then next_room() end
        elseif not api.isPeriodic(route) and not route.postal and present(route, gmcp_api.entities()) then finish(op, true)
        else next_room() end
        return cancel
    end

    function api.returnTo(source, done)
        local op, cancel = begin(done)
        if type(source) ~= "table" or type(source.map) ~= "number" or source.map <= 0 or not source.id then
            finish(op, false, "brak zapamietanej poczty zrodlowej")
            return cancel
        end
        local from = origin()
        if not from or not cost(from, source.map,true) then
            finish(op, false, "brak bezpiecznej drogi powrotnej do poczty")
            return cancel
        end
        walk(op, source.map, function(result)
            if not result.ok then finish(op, false, result.reason or "powrot przerwany"); return end
            local here = api.current()
            if here.map == source.map and here.id == source.id then finish(op, true)
            else finish(op, false, "niezgodna lokacja poczty zrodlowej") end
        end)
        return cancel
    end

    -- beta.13 has no pre-send event or public walker state. This is a narrow
    -- command allowlist, not proof of origin: manual numpad/stopped/room-change
    -- events must still cancel the courier in the adapter.
    function api.permits(command)
        local op = operation
        if not op or not op.moving then return false end
        if unsafe_command(command) then return false end
        local text = norm(command)
        if text == "stan" then return true end
        local room = gmcp_api.room() or {}
        for exit in pairs(room.exits or {}) do
            if text == norm(exit) or DIRECTION[text] == norm(exit) then return true end
        end
        local gate = locations and locations.gate and room.id and locations.gate(room.id)
        return gate and text == norm(gate.command) or false
    end
    api.ownSend = api.permits

    ctx:on("chimera.room.entities", function(snapshot)
        entityVersion = entityVersion + 1
        if type(snapshot) == "table" and type(snapshot.room) == "string" then roomVersions[snapshot.room] = entityVersion end
        observe(snapshot)
        local op = operation
        if op and op.cityScope then
            if not op.moving and op.cityReady then op.cityReady() end
        elseif op and op.route and api.isPeriodic(op.route) then
            if op.periodicWaiting then periodic_check(op, snapshot)
            elseif (not op.moving or not city) and periodic_ready(op.route, snapshot) then finish(op, true) end
        elseif op and (not op.moving or not city) and op.route and not op.route.postal and present(op.route, snapshot) then finish(op, true) end
    end)
    ctx:on("chimera.paczki.travel.activity",function(state)
        local op=operation
        if op and op.moving and type(state)=="table" and type(state.timeout)=="number" then
            op.transportLimit=math.max(SEARCH_LIMIT,math.min(900,state.timeout))
            watch_limit(op)
        end
    end)
    ctx:on("chimera.walk.stopped", function(event)
        local op = operation
        -- The local city-step callback owns this confirmed no-move refusal.
        -- All other stopped events keep their original cancellation semantics.
        if op and op.cityScope and op.moving and event and event.reason==CLOSED_LOCAL_REASON then return end
        if op then finish(op, false, event and event.reason or "chodzik zatrzymany") end
    end)
    ctx:on("chimera.numpad.pressed", function()
        if operation then finish(operation, false, "przerwane klawiszem") end
    end)
    ctx:on("chimera.room.changed", function()
        if city then
            local here=api.current()
            if here.id then entryVersions[here.id]=entityVersion end
        end
        local op = operation
        if op and op.waiting and api.current().id ~= op.atId then
            finish(op, false, "zmiana lokacji podczas sprawdzania adresata")
        elseif op and op.moving then
            -- A long intercity walk must not expire merely because its
            -- total duration exceeds three minutes while rooms keep changing.
            watch_limit(op)
        end
    end)
    ctx:on("chimera.session.end", function()
        if operation then finish(operation, false, "rozlaczenie") end
        entryVersions,sightings,searchAbsences,roomVersions,absentSince={},{},{},{},{}
        cityCombat=false
    end)
    ctx:on("chimera.paczki.actor.changed", function()
        if operation then finish(operation, false, "zmiana postaci") end
        roomVersions, absentSince, entryVersions, sightings, searchAbsences = {}, {}, {}, {}, {}
        cityCombat=false
    end)
    ctx:on("chimera.fight.started", function(state)
        if options.onCombat then options.onCombat("fight",state);return end
        if operation and operation.periodicWaiting then finish(operation, false, "rozpoczela sie walka") end
    end)
    ctx:on("chimera.combat.state", function(state)
        if options.onCombat then options.onCombat("state",state);return end
        if operation and operation.periodicWaiting and type(state) == "table" and
            ((state.primary and tostring(state.primary) ~= "") or (type(state.relations) == "table" and next(state.relations))) then
            finish(operation, false, "walka podczas oczekiwania")
        end
    end)
    if ctx.cleanup then ctx:cleanup(function()
        if operation then finish(operation, false, "przeladowanie kuriera") end
    end) end
    return api
end
