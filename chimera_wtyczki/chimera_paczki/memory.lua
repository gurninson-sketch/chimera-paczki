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

-- Public, data-only shared address catalogue. Code updates remain independent.
local SHARED_URL="https://raw.githubusercontent.com/gurninson-sketch/chimera-paczki/main/data/addresses.json"
local SHARED_LIMIT=4*1024*1024
local function sharedFs()
    local fs=require("chimera.core.fs")
    return {exists=fs.exists,isDir=fs.is_dir,mkdir=fs.mkdir,remove=os.remove,
        isLink=function(path) return type(lfs)=="table" and type(lfs.symlinkattributes)=="function" and lfs.symlinkattributes(path,"mode")=="link" end,
        read=function(path,limit)
            local file=io.open(path,"rb");if not file then return nil end
            local body=file:read(limit and limit+1 or "*a");file:close();return body
        end,
        write=function(path,body)
            local file=io.open(path,"wb");if not file then return false end
            local wrote=file:write(body);local closed=file:close();return wrote~=nil and closed~=nil
        end}
end
local function sharedPath(value)
    if type(value)~="string" or value=="" or value:find("[%z\1-\31\127]") then return nil end
    value=value:gsub("\\","/"):gsub("/+$","")
    if not (value:sub(1,1)=="/" or value:match("^%a:/")) then return nil end
    for part in value:gmatch("[^/]+") do if part=="." or part==".." then return nil end end
    return value
end
local function createSharedSync(memory,ctx,options)
    options=options or {}
    local json=options.json or require("chimera.core.json")
    local fs=options.fs or sharedFs()
    local now=options.now or function() return type(getEpoch)=="function" and getEpoch() or os.time() end
    local setting=ctx:saved("baza_synchronizacja",{})
    local enabled=type(setting)~="table" or setting.enabled~=false
    local home=sharedPath(options.home or ctx.app and ctx.app.paths and ctx.app.paths.home)
    local work=home and home.."/chimera_paczki_updates"
    local instance=tostring({}):gsub("[^%w]","").."-"..tostring(math.floor(now()*1000000))
    local disposed,sequence,waiting,pending=false,0,nil,nil
    local timeout,retry,start,periodic
    local retired={}
    local lastCheck,lastImport,lastBackup,lastSummary,reason
    local controller={url=SHARED_URL}
    local function log(message) ctx.log.info("Wspolna baza Paczek: "..message) end
    local function cancel(id) if id then ctx:cancel(id) end end
    local function remove(path) if path then pcall(fs.remove,path) end end
    local function finish(message)
        if waiting then retired[waiting.path]=true;remove(waiting.path) end
        waiting=nil;cancel(timeout);timeout=nil
        if message then reason=message;log(message) end
    end
    local function pathOK()
        return home and work and fs.isDir(home) and not fs.isLink(work)
    end
    local function validate(package)
        if type(package)~="table" or package.format~="chimera_paczki_baza" or package.version~=1 or
            type(package.memory)~="table" or package.memory.schema~=SCHEMA or type(package.memory.records)~="table" then
            return nil,"nieprawidlowy format wspolnej bazy"
        end
        local clean={schema=SCHEMA,records={}}
        for key,record in pairs(package.memory.records) do
            local value,why=clean_record(key,record,true)
            if not value then return nil,why end
            local existing=memory.find(value.recipient)
            if existing and existing.postal~=value.postal then return nil,"sprzeczny rodzaj adresata: "..value.recipient end
            clean.records[key]=value
        end
        return clean
    end
    local apply
    local function defer()
        cancel(retry)
        retry=ctx:timer(15,function() retry=nil;if not disposed then apply() end end)
    end
    apply=function()
        if disposed or not pending then return end
        if pending.automatic and not enabled then pending=nil;return end
        if not pathOK() then pending=nil;finish("nieprawidlowy katalog danych; baza lokalna zachowana");return end
        local ok,ready,why=pcall(options.safe or function() return false end)
        if not ok or ready~=true then reason=why or "czekam na zatrzymanie kuriera";defer();return end
        local candidate=pending
        -- Save a separate, allowlisted snapshot before the merge. The backup
        -- is outside plugin discovery and contains no course/account state.
        sequence=sequence+1
        local backup=work.."/addresses-backup-"..instance.."-"..sequence..".json"
        if fs.exists(backup) or fs.isLink(backup) then pending=nil;finish("plik kopii juz istnieje; baza lokalna zachowana");return end
        local encoded,body=pcall(json.encode,{format="chimera_paczki_baza",version=1,memory=memory.exportState()},true)
        local wrote,saved=false,false
        if encoded and type(body)=="string" then wrote,saved=pcall(fs.write,backup,body.."\n") end
        if not wrote or saved~=true then remove(backup);pending=nil;finish("nie zapisano kopii bazy; import anulowany");return end
        lastBackup=backup
        local imported,summary=memory.importState(candidate.snapshot)
        pending=nil;cancel(retry);retry=nil
        if not imported then finish("nie zaimportowano: "..tostring(summary).."; kopia: "..backup);return end
        reason=nil;lastImport=now();lastSummary=summary
        log("scalono: dodano "..summary.added..", uzupelniono "..summary.updated..", bez zmian "..summary.unchanged.."; razem "..summary.total..". Kopia: "..backup)
    end
    function controller.check(automatic)
        if disposed or (automatic and not enabled) then return false end
        if waiting or pending then if not automatic then log("pobieranie lub import juz oczekuje") end;return false end
        if not pathOK() or not fs.mkdir(work) or fs.isLink(work) then finish("nie mozna przygotowac katalogu pobierania");return false end
        sequence=sequence+1
        local path=work.."/addresses-download-"..instance.."-"..sequence..".tmp"
        if fs.exists(path) or fs.isLink(path) then finish("plik pobierania juz istnieje");return false end
        waiting={path=path,automatic=automatic==true};reason=nil;lastCheck=now()
        timeout=ctx:timer(60,function() timeout=nil;if not disposed and waiting then finish("timeout pobierania (60 s); baza lokalna zachowana") end end)
        local ok,result=pcall(options.downloadFile or downloadFile,path,SHARED_URL)
        if not ok or result==false then finish("nie mozna rozpoczac pobierania; baza lokalna zachowana");return false end
        if not automatic then log("pobieram katalog adresow z GitHuba") end
        return true
    end
    ctx:on("sysDownloadDone",function(_,path,size)
        path=sharedPath(path)
        if path and retired[path] then retired[path]=nil;remove(path);return end
        if disposed or not waiting or waiting.path~=path then return end
        local request=waiting;waiting=nil;cancel(timeout);timeout=nil
        if not pathOK() or fs.isDir(path) or fs.isLink(path) or not fs.exists(path) or
            (type(size)=="number" and size>SHARED_LIMIT) then remove(path);finish("nieprawidlowy plik lub przekroczony limit 4 MiB; baza lokalna zachowana");return end
        local read,body=pcall(fs.read,path,SHARED_LIMIT);remove(path)
        if not read or type(body)~="string" or #body==0 or #body>SHARED_LIMIT then finish("nie mozna odczytac bazy lub przekroczony limit 4 MiB");return end
        local decoded,package=pcall(json.decode,body)
        if not decoded then finish("nieprawidlowy JSON; baza lokalna zachowana");return end
        local snapshot,why=validate(package)
        if not snapshot then finish(why.."; baza lokalna zachowana");return end
        pending={snapshot=snapshot,automatic=request.automatic};apply()
    end)
    ctx:on("sysDownloadError",function(_,message,path)
        path=sharedPath(path)
        if path and retired[path] then retired[path]=nil;remove(path);return end
        if not disposed and waiting and waiting.path==path then finish("blad pobierania: "..tostring(message).."; baza lokalna zachowana") end
    end)
    function controller.setEnabled(value)
        if disposed then return false end
        value=value==true
        local ok,saved=pcall(ctx.save,ctx,"baza_synchronizacja",{schema=1,enabled=value})
        if not ok or saved==false then log("nie zapisano ustawienia synchronizacji");return false end
        enabled=value
        if not enabled then
            if waiting and waiting.automatic then finish(nil) end
            if pending and pending.automatic then pending=nil;cancel(retry);retry=nil end
        end
        log("automatyczne pobieranie "..(enabled and "wlaczone" or "wylaczone"));return true
    end
    function controller.status()
        return {enabled=enabled,busy=waiting~=nil,pending=pending~=nil,reason=reason,url=SHARED_URL,
            lastCheck=lastCheck,lastImport=lastImport,backup=lastBackup,summary=lastSummary,count=memory.count()}
    end
    function controller.show()
        local status=controller.status()
        log("auto: "..(enabled and "on" or "off").."; adresatow "..status.count..
            (status.busy and "; pobieranie" or "")..(status.pending and "; import oczekuje" or "")..
            (reason and "; "..reason or "")..". /paczki baza aktualizuj | /paczki baza synchronizacja on|off")
    end
    start=ctx:timer(45,function() start=nil;controller.check(true) end)
    periodic=ctx:timer(6*60*60,function() controller.check(true) end,true)
    ctx:cleanup(function()
        disposed=true;cancel(timeout);cancel(retry);cancel(start);cancel(periodic)
        remove(waiting and waiting.path)
        for path in pairs(retired) do remove(path) end
        waiting=nil;pending=nil
    end)
    return controller
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
    function api.createSharedSync(ctx,options) return createSharedSync(api,ctx,options) end
    return api
end
