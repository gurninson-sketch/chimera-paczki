-- Predicted work-cycle time, kept separately from the portable NPC memory.
-- A route's map weight is deliberately never interpreted as seconds.
local SCHEMA,MAX_ACTORS,MAX_ROUTES,MAX_SAMPLES=1,32,512,1000000
local MAX_SECONDS,MAX_STEPS=604800,50000
local MAX_PACED=MAX_STEPS*3+2000
local ACCENTS={
    ["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z",
    ["Ą"]="a",["Ć"]="c",["Ę"]="e",["Ł"]="l",["Ń"]="n",["Ó"]="o",["Ś"]="s",["Ź"]="z",["Ż"]="z",
}
local DEFAULTS={ack=0.35,gate=15,ferry=180,handling=8,periodic=60}
local function finite(value,maximum)
    return type(value)=="number" and value>=0 and value<math.huge and (not maximum or value<=maximum)
end
local function integer(value,maximum) return finite(value,maximum) and value==math.floor(value) end
local function text(value,maximum)
    if type(value)~="string" or value:find("[%z\1-\31\127]") then return nil end
    value=value:gsub(" "," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
    if value=="" or #value>(maximum or 256) then return nil end
    return value
end
local function norm(value)
    value=text(value)
    if not value then return nil end
    for accent,ascii in pairs(ACCENTS) do value=value:gsub(accent,ascii) end
    value=value:lower():gsub("[%s%.]+$","")
    return value~="" and value or nil
end
local function source(value)
    value=text(value,128)
    return value and value:lower() or nil
end
local function part(value) value=tostring(value);return #value..":"..value end
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for key,item in pairs(value) do out[key]=copy(item) end;return out
end
local function nonnegative(value,default,maximum)
    if value==nil then return default end
    return finite(value,maximum) and value or nil
end
local function metrics(query)
    local raw=query.timing
    if raw==nil then raw=query.metrics end
    if raw==nil and type(query.route)=="table" then raw=query.route.timing end
    if raw==nil and query.steps~=nil then raw=query end
    if type(raw)=="table" and type(raw.cycle)=="table" then raw=raw.cycle end
    if type(raw)~="table" then return nil,"brak metryk czasu trasy" end
    local steps=raw.steps
    if steps==nil then steps=raw.roadSteps end
    local units=raw.delayUnits
    if units==nil then units=raw.delays end
    if units==nil and integer(steps,MAX_STEPS) then units=math.max(0,steps-1) end
    local gates,ferries=raw.gates,raw.ferries
    if gates==nil then gates=0 end
    if ferries==nil then ferries=0 end
    if not integer(steps,MAX_STEPS) or not integer(units,MAX_STEPS+1000) or
        not integer(gates,MAX_STEPS) or not integer(ferries,1024) then
        return nil,"nieprawidlowe metryki czasu trasy"
    end
    local keys={}
    if raw.ferryKeys~=nil then
        if type(raw.ferryKeys)~="table" or #raw.ferryKeys>1024 then return nil,"nieprawidlowe przeprawy trasy" end
        for key in pairs(raw.ferryKeys) do
            if not integer(key,#raw.ferryKeys) or key<1 then return nil,"nieprawidlowa lista przepraw" end
        end
        for index=1,#raw.ferryKeys do
            local value=text(raw.ferryKeys[index],256)
            if not value then return nil,"nieprawidlowy identyfikator przeprawy" end
            keys[index]=value
        end
        if #keys>ferries then return nil,"liczba przepraw nie zgadza sie z trasa" end
        table.sort(keys)
    end
    local signature=raw.signature
    if signature~=nil then
        signature=text(signature,1024)
        if not signature then return nil,"nieprawidlowa sygnatura trasy" end
    end
    local out={steps=steps,delayUnits=units,gates=gates,ferries=ferries,ferryKeys=keys,signature=signature}
    out.minimumDelayUnits=raw.minimumDelayUnits
    if out.minimumDelayUnits==nil then out.minimumDelayUnits=0 end
    out.minimumDelaySeconds=raw.minimumDelaySeconds
    if out.minimumDelaySeconds==nil then out.minimumDelaySeconds=0.5 end
    if not integer(out.minimumDelayUnits,MAX_PACED) or out.minimumDelayUnits>units+gates or
        not finite(out.minimumDelaySeconds,60) then return nil,"nieprawidlowa minimalna zwloka trasy" end
    for _,field in ipairs({"handlingSeconds","transportSeconds","npcWaitSeconds"}) do
        if raw[field]~=nil then
            if not finite(raw[field],MAX_SECONDS) then return nil,"nieprawidlowy czas skladowy trasy" end
            out[field]=raw[field]
        end
    end
    return out
end
local function fingerprint(timing,postal,periodic)
    local parts={postal and "postal" or "npc",periodic and "periodic" or "fixed",timing.steps,timing.delayUnits,timing.gates,timing.ferries,
        timing.minimumDelayUnits,timing.minimumDelaySeconds}
    for _,key in ipairs(timing.ferryKeys) do parts[#parts+1]=key end
    parts[#parts+1]=timing.signature or ""
    for index,value in ipairs(parts) do parts[index]=part(value) end
    return table.concat(parts)
end
local function query_data(query,allowPrior)
    if type(query)~="table" then return nil,"nieprawidlowe zapytanie o czas" end
    local actor,origin,recipient=norm(query.actor),source(query.sourceId),norm(query.recipient)
    if not recipient or (not actor and (not allowPrior or query.actor~=nil)) or
        (not origin and (not allowPrior or query.sourceId~=nil)) then
        return nil,"brak postaci, urzedu lub pelnego adresata"
    end
    if (query.postal~=nil and type(query.postal)~="boolean") or
        (query.periodic~=nil and type(query.periodic)~="boolean") then return nil,"nieprawidlowy rodzaj kursu" end
    local timing,why=metrics(query)
    if not timing then return nil,why end
    local delay=query.delay
    if not finite(delay,60) then return nil,"nieprawidlowe tempo kuriera" end
    local postal,periodic=query.postal==true,query.periodic==true
    local signature=fingerprint(timing,postal,periodic)
    return {actor=actor,sourceId=origin,recipient=recipient,postal=postal,periodic=periodic,timing=timing,
        delay=delay,signature=signature,key=actor and origin and (part(origin)..part(recipient)..part(signature)) or nil}
end
local function clean_record(key,value)
    if type(value)~="table" then return nil end
    local query={actor="saved",sourceId=value.sourceId,recipient=value.recipient,postal=value.postal,periodic=value.periodic,
        timing=value.timing,delay=0}
    local data=query_data(query)
    if not data or data.key~=key or not finite(value.nonDelaySeconds,MAX_SECONDS) or value.nonDelaySeconds<=0 or
        not integer(value.samples,MAX_SAMPLES) or value.samples<1 or not finite(value.last) then return nil end
    local pacedUnits,minimumUnits=value.pacedUnits,value.minimumDelayUnits
    if pacedUnits==nil then pacedUnits=data.timing.delayUnits+data.timing.gates end
    if minimumUnits==nil then minimumUnits=data.timing.minimumDelayUnits end
    if not finite(pacedUnits,MAX_PACED) or not finite(minimumUnits,MAX_PACED) or minimumUnits>pacedUnits then return nil end
    return {sourceId=data.sourceId,recipient=data.recipient,postal=data.postal,periodic=data.periodic,
        timing=data.timing,nonDelaySeconds=value.nonDelaySeconds,pacedUnits=pacedUnits,minimumDelayUnits=minimumUnits,
        samples=value.samples,last=value.last}
end
local function count(records) local n=0;for _ in pairs(records) do n=n+1 end;return n end
local function trim(records,maximum)
    while count(records)>maximum do
        local oldest,stamp
        for key,value in pairs(records) do
            if stamp==nil or value.last<stamp or value.last==stamp and key<oldest then oldest,stamp=key,value.last end
        end
        records[oldest]=nil
    end
end
local function trim_actors(actors)
    while count(actors)>MAX_ACTORS do
        local oldest,stamp
        for actor,records in pairs(actors) do
            local newest=0;for _,record in pairs(records) do newest=math.max(newest,record.last) end
            if stamp==nil or newest<stamp or newest==stamp and actor<oldest then oldest,stamp=actor,newest end
        end
        actors[oldest]=nil
    end
end

return function(saved,opts)
    opts=opts or {}
    assert(opts.save==nil or type(opts.save)=="function","eta.save must be a function")
    local clock=opts.now or os.time
    assert(type(clock)=="function","eta.now must be a function")
    local actors={}
    if type(saved)=="table" and saved.schema==SCHEMA and type(saved.actors)=="table" then
        for actor,records in pairs(saved.actors) do
            if norm(actor)==actor and type(records)=="table" then
                local clean={}
                for key,value in pairs(records) do local record=clean_record(key,value);if record then clean[key]=record end end
                trim(clean,MAX_ROUTES)
                if next(clean) then actors[actor]=clean end
            end
        end
        trim_actors(actors)
    end
    local defaults={}
    for field,value in pairs(DEFAULTS) do
        defaults[field]=nonnegative(type(opts.defaults)=="table" and opts.defaults[field],value,MAX_SECONDS) or value
    end
    local api={version="1.5.6",schema=SCHEMA}
    local function prior(data)
        local t=data.timing
        local movement=t.steps*defaults.ack
        local units=t.delayUnits+t.gates
        local pace=units*data.delay+t.minimumDelayUnits*math.max(0,t.minimumDelaySeconds-data.delay)
        local gates=t.gates*defaults.gate
        local ferry=t.transportSeconds
        if ferry==nil then ferry=t.ferries*defaults.ferry end
        local handling=t.handlingSeconds
        if handling==nil then handling=defaults.handling end
        local waiting=t.npcWaitSeconds
        if waiting==nil then waiting=data.periodic and defaults.periodic or 0 end
        return {movement=movement,pace=pace,gates=gates,transport=ferry,handling=handling,npcWait=waiting},
            movement+gates+ferry+handling+waiting,units,t.minimumDelayUnits
    end
    function api.estimate(query)
        local data,why=query_data(query,true)
        if not data then return nil,why end
        local breakdown,residual,units,minimumUnits=prior(data)
        local priorResidual=residual
        local records=data.actor and data.sourceId and actors[data.actor]
        local record=records and data.key and records[data.key]
        local samples,weight=record and record.samples or 0,0
        if record then
            weight=math.min(1,samples/3)
            residual=(1-weight)*residual+weight*record.nonDelaySeconds
            units=(1-weight)*units+weight*record.pacedUnits
            minimumUnits=(1-weight)*minimumUnits+weight*record.minimumDelayUnits
        end
        breakdown.pace=units*data.delay+minimumUnits*math.max(0,data.timing.minimumDelaySeconds-data.delay)
        local seconds=math.max(1,breakdown.pace+1,residual+breakdown.pace)
        breakdown.learnedAdjustment=residual-priorResidual
        breakdown.minimumAdjustment=seconds-(residual+breakdown.pace)
        return {seconds=seconds,method=record and "learned" or "estimate",samples=samples,
            confidence=samples>=5 and "high" or (samples>=2 and "medium" or "low"),
            breakdown=breakdown,learnedWeight=weight,nonDelaySeconds=residual,pacedUnits=units,
            minimumDelayUnits=minimumUnits,signature=data.signature}
    end
    function api.remember(evidence)
        if type(evidence)~="table" or evidence.verified~=true or evidence.handover~=true or
            evidence.reward~=true or evidence.completed~=true then
            return false,"wymagane sa cztery potwierdzenia zakonczonego kursu"
        end
        local data,why=query_data(evidence)
        if not data then return false,why end
        local seconds=evidence.seconds
        local pacedUnits=evidence.pacedUnits
        if pacedUnits==nil then pacedUnits=data.timing.delayUnits+data.timing.gates end
        local minimumUnits=evidence.minimumDelayUnits
        if minimumUnits==nil then minimumUnits=data.timing.minimumDelayUnits end
        if not integer(pacedUnits,MAX_PACED) or not integer(minimumUnits,MAX_PACED) or minimumUnits>pacedUnits then
            return false,"nieprawidlowa liczba wykonanych zwlok kursu"
        end
        local expectedPace=pacedUnits*data.delay+minimumUnits*math.max(0,data.timing.minimumDelaySeconds-data.delay)
        local delays=evidence.delaySeconds
        if delays==nil then delays=expectedPace end
        if not finite(seconds,MAX_SECONDS) or seconds<=0 or not finite(delays,MAX_SECONDS) or
            seconds<=delays or seconds<=expectedPace then
            return false,"nieprawidlowy zmierzony czas kursu"
        end
        local ok,last=pcall(clock)
        if not ok or not finite(last) then return false,"nie udalo sie ustalic czasu pomiaru" end
        local candidate=copy(actors)
        candidate[data.actor]=candidate[data.actor] or {}
        local records=candidate[data.actor]
        local previous=records[data.key]
        local residual=seconds-delays
        if previous then
            residual=previous.nonDelaySeconds*2/3+residual/3
            pacedUnits=previous.pacedUnits*2/3+pacedUnits/3
            minimumUnits=previous.minimumDelayUnits*2/3+minimumUnits/3
        end
        records[data.key]={sourceId=data.sourceId,recipient=data.recipient,postal=data.postal,periodic=data.periodic,
            timing=data.timing,nonDelaySeconds=residual,pacedUnits=pacedUnits,minimumDelayUnits=minimumUnits,
            samples=math.min(MAX_SAMPLES,(previous and previous.samples or 0)+1),last=last}
        trim(records,MAX_ROUTES);trim_actors(candidate)
        if opts.save then
            local savedOk,result=pcall(opts.save,{schema=SCHEMA,actors=copy(candidate)})
            if not savedOk or result==false then return false,"nie udalo sie zapisac pomiarow czasu" end
        end
        actors=candidate
        return true
    end
    function api.exportState() return {schema=SCHEMA,actors=copy(actors)} end
    function api.summary(actor)
        local records=actors[norm(actor)] or {};local samples=0
        for _,record in pairs(records) do samples=samples+record.samples end
        return {routes=count(records),samples=samples}
    end
    function api.count(actor) local result=api.summary(actor);return result.routes,result.samples end
    return api
end
