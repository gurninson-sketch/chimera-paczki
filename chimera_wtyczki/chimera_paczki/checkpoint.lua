-- Durable courier intent, partitioned by the canonical character name supplied
-- from GMCP. This module never parses login prompts or executes saved data.
local SCHEMA,MAX_NUMBER=1,9007199254740990
local FLAGS={"awaitingPickup","awaitingDelivery","awaitingReturn","awaitingReward","manualPickup","manualDelivery"}
local COUNTERS={"delivered","gold","silver","copper"}
local ACCENTS={
    ["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z",
    ["Ą"]="a",["Ć"]="c",["Ę"]="e",["Ł"]="l",["Ń"]="n",["Ó"]="o",["Ś"]="s",["Ź"]="z",["Ż"]="z",
}
local function text(value)
    if type(value)~="string" or value:find("[%z\1-\31\127]") then return nil end
    value=value:gsub(" "," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
    return value~="" and value or nil
end
local function actor(value)
    value=text(value)
    if not value or value:find("[@:;]") then return nil end
    for accent,ascii in pairs(ACCENTS) do value=value:gsub(accent,ascii) end
    value=value:lower()
    if value:find("podaj haslo",1,true) or value:find("password",1,true) or value:match("^witaj[, ]") then return nil end
    return value
end
local function finite(value) return type(value)=="number" and value>=0 and value<=MAX_NUMBER end
local function integer(value) return finite(value) and value==math.floor(value) end
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for key,item in pairs(value) do out[key]=copy(item) end;return out
end
local function optional_text(value)
    if value==nil then return true,nil end
    local clean=text(value)
    return clean~=nil,clean
end
local function optional_bool(value)
    return value==nil or type(value)=="boolean"
end
local function office(value)
    if type(value)~="table" then return nil end
    local id=text(value.id)
    if not id or not optional_bool(value.staticNuln) then return nil end
    local nameOk,name=optional_text(value.name)
    local cityOk,city=optional_text(value.city)
    if not nameOk or not cityOk then return nil end
    return {id=id:lower(),name=name,city=city,staticNuln=value.staticNuln==true}
end
local function container(value)
    if type(value)~="table" then return nil end
    local out={}
    for _,field in ipairs({"b","d","name","open","close","containerWord","openWord"}) do
        local ok,clean=optional_text(value[field])
        if not ok or clean and clean:find("[;#]") then return nil end
        out[field]=clean
    end
    if not out.d or not optional_bool(value.detected) then return nil end
    out.detected=value.detected==true
    if out.open and (not out.b or out.open~="otworz "..out.b) then return nil end
    if out.close and (not out.b or out.close~="zamknij "..out.b) then return nil end
    return out
end
local function sanitize(state)
    if type(state)~="table" then return nil,"nieprawidlowy zapis kursu" end
    local out={}
    if state.bank~=nil then
        local bank=state.bank
        if type(bank)~="table" or not finite(bank.nextAt) or not optional_bool(bank.requested) or
            (bank.stage~=nil and not ({travel=true,exchange=true,["return"]=true})[bank.stage]) then
            return nil,"nieprawidlowy zapis wizyty w banku"
        end
        out.bank={nextAt=bank.nextAt,requested=bank.requested==true,stage=bank.stage}
    end
    for _,field in ipairs({"source","pendingManualSource"}) do
        if state[field]~=nil then
            out[field]=office(state[field])
            if not out[field] then return nil,"nieprawidlowy urzad w zapisie kursu" end
        end
    end
    if state.job~=nil then
        local job=state.job
        if type(job)~="table" or not text(job.name) then return nil,"brak adresata zapamietanej paczki" end
        for _,field in ipairs({"recipientConfirmed","delivered","coinsPending","returningUndelivered"}) do
            if not optional_bool(job[field]) then return nil,"nieprawidlowy stan zapamietanej paczki" end
        end
        out.job={name=text(job.name),recipientConfirmed=job.recipientConfirmed==true,
            delivered=job.delivered==true,coinsPending=job.coinsPending==true,
            returningUndelivered=job.returningUndelivered==true}
        if job.searchElapsed~=nil then
            if not finite(job.searchElapsed) then return nil,"nieprawidlowy czas szukania adresata" end
            out.job.searchElapsed=job.searchElapsed
        end
        if job.source~=nil then
            out.job.source=office(job.source)
            if not out.job.source then return nil,"nieprawidlowy urzad nadania paczki" end
        end
    end
    if state.relocation~=nil then
        local relocation=state.relocation
        if type(relocation)~="table" or not optional_bool(relocation.manual) then return nil,"nieprawidlowe przejscie do urzedu" end
        local to=office(relocation.to)
        if not to then return nil,"brak urzedu docelowego przejscia" end
        out.relocation={to=to,manual=relocation.manual==true}
    end
    if state.flags~=nil and type(state.flags)~="table" then return nil,"nieprawidlowe potwierdzenia operacji" end
    out.flags={}
    for _,field in ipairs(FLAGS) do
        local value=state.flags and state.flags[field]
        if not optional_bool(value) then return nil,"nieprawidlowe potwierdzenie operacji: "..field end
        out.flags[field]=value==true
    end
    if state.selectedName~=nil then
        out.selectedName=text(state.selectedName)
        if not out.selectedName then return nil,"nieprawidlowy wybrany adresat" end
    end
    if state.stats~=nil then
        if type(state.stats)~="table" then return nil,"nieprawidlowe statystyki kursu" end
        out.stats={}
        for _,field in ipairs(COUNTERS) do
            local value=state.stats[field]
            if value~=nil and not integer(value) then return nil,"nieprawidlowy licznik kursu" end
            out.stats[field]=value or 0
        end
        if state.stats.started~=nil then
            if not finite(state.stats.started) then return nil,"nieprawidlowy czas rozpoczecia kursu" end
            out.stats.started=state.stats.started
        end
    end
    if state.stopAt~=nil then
        if not integer(state.stopAt) then return nil,"nieprawidlowy limit kursu" end
        out.stopAt=state.stopAt
    end
    if state.inventory~=nil then
        local inventory=state.inventory
        if type(inventory)~="table" or not ({hands=true,bag=true,unknown=true})[inventory.state] or
            not optional_bool(inventory.coinsUncertain) then return nil,"nieprawidlowy stan pojemnika" end
        out.inventory={state=inventory.state,coinsUncertain=inventory.coinsUncertain==true}
        if inventory.container~=nil then
            if inventory.state~="bag" then return nil,"pojemnik paczki wymaga potwierdzonego stanu bag" end
            out.inventory.container=container(inventory.container)
            if not out.inventory.container then return nil,"nieprawidlowy opis potwierdzonego pojemnika" end
        end
    end
    if state.savedAt~=nil then
        if not finite(state.savedAt) then return nil,"nieprawidlowy czas zapisu kursu" end
        out.savedAt=state.savedAt
    end
    return out
end

return function(saved,opts)
    opts=opts or {}
    local clock=opts.now or os.time
    assert(type(clock)=="function","checkpoint.now must be a function")
    assert(opts.save==nil or type(opts.save)=="function","checkpoint.save must be a function")
    local actors={}
    if type(saved)=="table" and saved.schema==SCHEMA and type(saved.actors)=="table" then
        for key,state in pairs(saved.actors) do
            if type(key)=="string" and actor(key)==key then
                local clean=sanitize(state)
                if clean then actors[key]=clean end
            end
        end
    end
    local api={version="1.5.0",schema=SCHEMA}
    local function commit(candidate)
        if opts.save then
            local ok,result=pcall(opts.save,{schema=SCHEMA,actors=copy(candidate)})
            if not ok or result==false then return false,"nie udalo sie zapisac biezacego kursu" end
        end
        actors=candidate
        return true
    end
    function api.put(canonicalActor,state)
        local key=actor(canonicalActor)
        if not key then return false,"brak kanonicznej nazwy postaci z GMCP" end
        local clean,why=sanitize(state)
        if not clean then return false,why end
        local ok,time=pcall(clock)
        if not ok or not finite(time) then return false,"nie udalo sie ustalic czasu zapisu kursu" end
        clean.savedAt=time
        local candidate=copy(actors);candidate[key]=clean
        return commit(candidate)
    end
    function api.get(canonicalActor)
        local key=actor(canonicalActor)
        return key and actors[key] and copy(actors[key]) or nil
    end
    function api.forget(canonicalActor)
        local key=actor(canonicalActor)
        if not key or not actors[key] then return false,"brak zapisanego kursu tej postaci" end
        local candidate=copy(actors);candidate[key]=nil
        return commit(candidate)
    end
    function api.count()
        local count=0;for _ in pairs(actors) do count=count+1 end;return count
    end
    return api
end
