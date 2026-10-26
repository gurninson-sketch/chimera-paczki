-- Confirmed recipients, shared within this Mudlet profile. Only the caller
-- handling BOTH the actual handover and reward may submit evidence.
-- Numeric map IDs and player/account identity are never persisted.
local SCHEMA=1
local MAX_COUNT=9007199254740990
local ACCENTS={
    ["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z",
    ["Ą"]="a",["Ć"]="c",["Ę"]="e",["Ł"]="l",["Ń"]="n",["Ó"]="o",["Ś"]="s",["Ź"]="z",["Ż"]="z",
}
local function text(value)
    if type(value)~="string" then return nil end
    value=value:gsub("\27%[[%d;]*[mK]",""):gsub(" "," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
    if value=="" or value:find("[%z\1-\31\127]") then return nil end
    return value
end
local function norm(value)
    value=text(value)
    if not value then return nil end
    for accent,ascii in pairs(ACCENTS) do value=value:gsub(accent,ascii) end
    value=value:lower():gsub("[%s%.]+$","")
    return value~="" and value or nil
end
local function hash(value)
    value=text(value)
    return value and value:lower() or nil
end
local function number(value)
    return type(value)=="number" and value>=0 and value<math.huge
end
local function positive_integer(value)
    return number(value) and value>0 and value<=MAX_COUNT and value==math.floor(value)
end
local function identity(value)
    if type(value)~="table" then return nil end
    local id,name=text(value.npcId),text(value.name)
    if not id or not name then return nil end
    local short,title=text(value.short),text(value.title)
    if value.short~=nil and type(value.short)~="string" then return nil end
    if value.title~=nil and type(value.title)~="string" then return nil end
    return {npcId=id,name=name,short=short,title=title}
end
local function copy_record(record)
    local out={recipient=record.recipient,npcId=record.npcId,name=record.name,short=record.short,title=record.title,
        roomHashes={},count=record.count,last=record.last,postal=record.postal==true}
    for _,room in ipairs(record.roomHashes) do out.roomHashes[#out.roomHashes+1]=room end
    return out
end
local function copy_records(records)
    local out={}
    for key,record in pairs(records) do out[key]=copy_record(record) end
    return out
end
local function clean_record(key,record,strict)
    if type(record)~="table" or type(key)~="string" or norm(record.recipient)~=key or
        not positive_integer(record.count) or not number(record.last) or
        (record.postal~=nil and type(record.postal)~="boolean") or type(record.roomHashes)~="table" then
        return nil,"nieprawidlowy wpis adresata"
    end
    local rooms,seen={},{}
    if strict then
        local length=#record.roomHashes
        for index in pairs(record.roomHashes) do
            if type(index)~="number" or index<1 or index~=math.floor(index) or index>length then
                return nil,"nieprawidlowa lista lokacji adresata"
            end
        end
        for index=1,length do
            if not hash(record.roomHashes[index]) then return nil,"nieprawidlowy identyfikator lokacji adresata" end
        end
    end
    for _,room in ipairs(record.roomHashes) do
        local id=hash(room)
        if id and not seen[id] then rooms[#rooms+1]=id;seen[id]=true end
    end
    if #rooms==0 then return nil,"brak lokacji adresata" end
    local clean={recipient=text(record.recipient),roomHashes=rooms,count=record.count,last=record.last,
        postal=record.postal==true}
    local hasIdentity=record.npcId~=nil or record.name~=nil or record.short~=nil or record.title~=nil
    local npc=not clean.postal and identity(record)
    if strict and hasIdentity and not npc then return nil,"nieprawidlowa tozsamosc NPC adresata" end
    if npc then for field,value in pairs(npc) do clean[field]=value end end
    return clean
end
local function same_record(a,b)
    for _,field in ipairs({"recipient","npcId","name","short","title","count","last","postal"}) do
        if a[field]~=b[field] then return false end
    end
    if #a.roomHashes~=#b.roomHashes then return false end
    for index,room in ipairs(a.roomHashes) do if b.roomHashes[index]~=room then return false end end
    return true
end

return function(saved,opts)
    opts=opts or {}
    local records={}
    local clock=opts.now or os.time
    assert(type(clock)=="function","memory.now must be a function")
    assert(opts.save==nil or type(opts.save)=="function","memory.save must be a function")

    -- Reject unknown schema versions and malformed entries rather than
    -- upgrading observations into successful-delivery evidence.
    if type(saved)=="table" and saved.schema==SCHEMA and type(saved.records)=="table" then
        for key,record in pairs(saved.records) do
            local clean=clean_record(key,record,false)
            if clean then records[key]=clean end
        end
    end

    local api={version="1.5.4",schema=SCHEMA}
    local function commit(candidate)
        if opts.save then
            -- Give persistence a separate allowlisted copy. It cannot mutate
            -- the in-memory records through a retained table reference.
            local ok,result=pcall(opts.save,{schema=SCHEMA,records=copy_records(candidate)})
            if not ok or result==false then return false,"nie udalo sie zapisac sprawdzonych adresatow" end
        end
        records=candidate
        return true
    end

    function api.remember(evidence)
        if type(evidence)~="table" or evidence.verified~=true or evidence.handover~=true or evidence.reward~=true then
            return false,"wymagane sa potwierdzone doreczenie, nagroda i zweryfikowana lokacja"
        end
        local recipient,key=text(evidence.recipient),norm(evidence.recipient)
        local room=hash(evidence.roomHash)
        if not recipient or not key then return false,"brak pelnej nazwy adresata" end
        if not room or not positive_integer(evidence.map) then return false,"brak potwierdzonego identyfikatora lokacji i pokoju mapy" end
        if evidence.postal~=nil and type(evidence.postal)~="boolean" then return false,"nieprawidlowy rodzaj adresata" end
        local postal=evidence.postal==true
        local npc
        if evidence.npc~=nil then
            npc=identity(evidence.npc)
            if not npc or postal then return false,"nieprawidlowa tozsamosc NPC adresata" end
        end
        local previous=records[key]
        if previous and previous.postal~=postal then return false,"sprzeczny rodzaj zapamietanego adresata" end
        local ok,last=pcall(clock)
        if not ok or not number(last) then return false,"nie udalo sie ustalic czasu potwierdzenia" end
        if previous and previous.count>=MAX_COUNT then return false,"licznik doreczen przekracza zakres" end
        local record=previous and copy_record(previous) or {roomHashes={},count=0,postal=postal}
        record.recipient,record.count,record.last=recipient,record.count+1,last
        local rooms={room}
        for _,old in ipairs(record.roomHashes) do if old~=room then rooms[#rooms+1]=old end end
        record.roomHashes=rooms
        if npc then
            record.npcId,record.name,record.short,record.title=npc.npcId,npc.name,npc.short,npc.title
        end
        local candidate=copy_records(records)
        candidate[key]=record
        return commit(candidate)
    end

    function api.find(fullName)
        local key=norm(fullName)
        return key and records[key] and copy_record(records[key]) or nil
    end
    function api.all()
        local keys,out={},{}
        for key in pairs(records) do keys[#keys+1]=key end
        table.sort(keys)
        for _,key in ipairs(keys) do out[#out+1]=copy_record(records[key]) end
        return out
    end
    function api.exportState()
        return {schema=SCHEMA,records=copy_records(records)}
    end
    function api.importState(snapshot)
        if type(snapshot)~="table" or snapshot.schema~=SCHEMA or type(snapshot.records)~="table" then
            return false,"nieprawidlowy format lub wersja bazy adresatow"
        end
        local incoming={}
        for key,record in pairs(snapshot.records) do
            local clean,why=clean_record(key,record,true)
            if not clean then return false,why end
            incoming[key]=clean
        end
        local candidate=copy_records(records)
        local summary={added=0,updated=0,unchanged=0,total=0}
        for key,record in pairs(incoming) do
            local previous=candidate[key]
            if not previous then
                candidate[key]=copy_record(record);summary.added=summary.added+1
            else
                if previous.postal~=record.postal then return false,"sprzeczny rodzaj zapamietanego adresata: "..record.recipient end
                local merged=copy_record(previous)
                merged.count=math.max(previous.count,record.count)
                merged.last=math.max(previous.last,record.last)
                local first,second=previous.roomHashes,record.roomHashes
                if record.last>previous.last then first,second=second,first end
                local rooms,seen={},{}
                for _,list in ipairs({first,second}) do
                    for _,room in ipairs(list) do if not seen[room] then rooms[#rooms+1]=room;seen[room]=true end end
                end
                merged.roomHashes=rooms
                if not identity(previous) and identity(record) then
                    for _,field in ipairs({"npcId","name","short","title"}) do merged[field]=record[field] end
                end
                if same_record(previous,merged) then summary.unchanged=summary.unchanged+1
                else candidate[key]=merged;summary.updated=summary.updated+1 end
            end
        end
        for _ in pairs(candidate) do summary.total=summary.total+1 end
        if summary.added>0 or summary.updated>0 then
            local ok,why=commit(candidate)
            if not ok then return false,why end
        end
        return true,summary
    end
    function api.forget(fullName)
        local key=norm(fullName)
        if not key or not records[key] then return false,"nie ma takiego sprawdzonego adresata" end
        local candidate=copy_records(records);candidate[key]=nil
        return commit(candidate)
    end
    function api.clear() return commit({}) end
    function api.count()
        local count=0;for _ in pairs(records) do count=count+1 end;return count
    end
    return api
end
