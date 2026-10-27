-- Paczki GitHub updates. Download/check while running; replace only at a verified idle point.
-- Profile state, learned addresses and all databases live outside this code directory.
-- SHA-256 below is self-contained Lua 5.1+, advanced in small timer-owned slices.
-- SHA-256, Lua 5.1+. No external module and no dynamic code execution.
-- The asynchronous interface yields every 16 blocks to keep Mudlet responsive.
local S = {}
local MOD = 4294967296
local floor = math.floor
local xor4, and4 = {}, {}
for a=0,15 do
  xor4[a], and4[a] = {}, {}
  for b=0,15 do
    local x, y, xor, band, place = a, b, 0, 0, 1
    for _=1,4 do
      local xb, yb = x%2, y%2
      if xb ~= yb then xor = xor + place end
      if xb == 1 and yb == 1 then band = band + place end
      x, y, place = floor(x/2), floor(y/2), place*2
    end
    xor4[a][b], and4[a][b] = xor, band
  end
end
local function op(a,b,lookup)
  local result, place = 0,1
  for _=1,8 do
    result = result + lookup[a%16][b%16]*place
    a,b,place = floor(a/16),floor(b/16),place*16
  end
  return result
end
local function bxor(a,b,c)
  local result = op(a,b,xor4)
  return c and op(result,c,xor4) or result
end
local function band(a,b) return op(a,b,and4) end
local function rshift(a,n) return floor(a/2^n) end
local function ror(a,n) return (rshift(a,n) + (a%2^n)*2^(32-n))%MOD end
local constants = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local function word(n)
  return string.char(floor(n/16777216)%256, floor(n/65536)%256, floor(n/256)%256, n%256)
end
function S.new(data)
  local bits = #data*8
  return {data=data .. "\128" .. string.rep("\0", (55-#data)%64)
    .. word(floor(bits/MOD)) .. word(bits%MOD), offset=1,
    h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}}
end
function S.step(state, blocks)
  for _=1,blocks or 16 do
    if state.offset > #state.data then return true end
    local w, hash, offset = {}, state.h, state.offset
    for j=0,15 do
      local a,b,c,d = state.data:byte(offset+j*4, offset+j*4+3)
      w[j] = a*16777216+b*65536+c*256+d
    end
    for j=16,63 do
      local a,b=w[j-15],w[j-2]
      local s0=bxor(ror(a,7),ror(a,18),rshift(a,3))
      local s1=bxor(ror(b,17),ror(b,19),rshift(b,10))
      w[j]=(w[j-16]+s0+w[j-7]+s1)%MOD
    end
    local a,b,c,d,e,f,g,h=hash[1],hash[2],hash[3],hash[4],hash[5],hash[6],hash[7],hash[8]
    for j=0,63 do
      local s1=bxor(ror(e,6),ror(e,11),ror(e,25))
      local choose=bxor(band(e,f),band(MOD-1-e,g))
      local t1=(h+s1+choose+constants[j+1]+w[j])%MOD
      local s0=bxor(ror(a,2),ror(a,13),ror(a,22))
      local majority=bxor(band(a,b),band(a,c),band(b,c))
      local t2=(s0+majority)%MOD
      h,g,f,e,d,c,b,a=g,f,e,(d+t1)%MOD,c,b,a,(t1+t2)%MOD
    end
    local values={a,b,c,d,e,f,g,h}
    for j=1,8 do hash[j]=(hash[j]+values[j])%MOD end
    state.offset=offset+64
  end
  return state.offset > #state.data
end
function S.finish(state)
  local result={}
  for _,value in ipairs(state.h) do result[#result+1]=string.format("%08x",value) end
  return table.concat(result)
end

local U={version="1.5.20",sha256=S}
local REPO="https://github.com/gurninson-sketch/chimera-paczki"
local MANIFEST=REPO.."/releases/latest/download/update.json"
local FILES={"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua","scope.lua",
    "road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua","postal.lua",
    "checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}
local ALLOWED={};for _,name in ipairs(FILES) do ALLOWED[name]=true end
local MAX_BUNDLE,MAX_FILE,MAX_SOURCE=2*1024*1024,1024*1024,2*1024*1024
U.files=FILES;U.manifestUrl=MANIFEST
local function version(value)
    if type(value)~="string" or #value>32 then return nil end
    local a,b,c=value:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a or #a>5 or #b>5 or #c>5 then return nil end
    a,b,c=tonumber(a),tonumber(b),tonumber(c)
    if value~=string.format("%d.%d.%d",a,b,c) then return nil end
    return a,b,c
end
local function newer(a,b)
    local x,y,z=version(a);local p,q,r=version(b)
    return x and p and (x>p or x==p and (y>q or y==q and z>r)) or false
end
function U.validateManifest(data)
    if type(data)~="table" or data.schema~=1 or not version(data.version) or type(data.bundle)~="table" then return nil,"niepoprawny manifest" end
    if data.min_mudlet~=nil and not version(data.min_mudlet) then return nil,"niepoprawna wersja Mudleta" end
    local b=data.bundle
    if b.url~=REPO.."/releases/download/v"..data.version.."/chimera-paczki-runtime.json" then return nil,"obcy adres wydania" end
    if type(b.bytes)~="number" or b.bytes%1~=0 or b.bytes<1 or b.bytes>MAX_BUNDLE then return nil,"niepoprawny rozmiar wydania" end
    if type(b.sha256)~="string" or #b.sha256~=64 or not b.sha256:match("^[0-9a-f]+$") then return nil,"niepoprawna suma SHA-256" end
    return {version=data.version,url=b.url,bytes=b.bytes,sha256=b.sha256,minMudlet=data.min_mudlet or "4.20.0"}
end
function U.validateBundle(data,expected)
    if type(data)~="table" or data.schema~=1 or data.version~=expected or type(data.files)~="table" then return nil,"niepoprawny zestaw plikow" end
    local count,total=0,0
    for name,source in pairs(data.files) do
        if not ALLOWED[name] or type(source)~="string" or #source<1 or #source>MAX_FILE or source:find("%z") or source:byte(1)==27 then return nil,"niepoprawny plik wydania" end
        count=count+1;total=total+#source
    end
    if count~=#FILES or total>MAX_SOURCE then return nil,"niepelny zestaw plikow" end
    return data.files
end
local function defaultFs()
    local fs=require("chimera.core.fs")
    return {read=function(path,limit)
            local file=io.open(path,"rb");if not file then return nil end
            local body=file:read(limit and limit+1 or "*a");file:close();return body
        end,list=fs.list,mkdir=fs.mkdir,isDir=fs.is_dir,exists=fs.exists,rename=os.rename,remove=os.remove,
        write=function(path,content)
            local file,why=io.open(path,"wb");if not file then return false,why end
            local ok,err=file:write(content);local closed,closeerr=file:close()
            return ok~=nil and closed~=nil,err or closeerr
        end,
        isLink=function(path)
            return type(lfs)=="table" and type(lfs.symlinkattributes)=="function" and lfs.symlinkattributes(path,"mode")=="link"
        end}
end
local function normalizedHome(value)
    if type(value)~="string" or value=="" or value:find("[%z\1-\31\127]") then return nil end
    value=value:gsub("\\","/"):gsub("/+$","")
    if not (value:sub(1,1)=="/" or value:match("^[A-Za-z]:/")) then return nil end
    for part in value:gmatch("[^/]+") do if part=="." or part==".." then return nil end end
    return value
end

function U.create(ctx,opts)
    opts=opts or {}
    local json=opts.json or require("chimera.core.json")
    local fs=opts.fs or defaultFs()
    local current=opts.version or U.version
    local now=opts.now or function() return type(getEpoch)=="function" and getEpoch() or os.time() end
    local saved=ctx:saved("aktualizacje",{})
    local enabled=type(saved)~="table" or saved.enabled~=false
    local api={version=U.version}
    local disposed,busy,serial,waiting=false,false,0,nil
    local requestNumber,retired=0,{}
    local instance=tostring({}):gsub("[^%w]","").."-"..tostring(math.floor(now()*1000000))
    local pending,reason,lastVersion,lastCheck,stage=false,nil,nil,nil,nil
    local timer,checkTimer,startTimer,httpTimer,workTimer
    local home=normalizedHome(opts.home or ctx.app and ctx.app.paths and ctx.app.paths.home)
    local live=home and home.."/chimera_wtyczki/chimera_paczki"
    local work=home and home.."/chimera_paczki_updates"
    local function log(message) ctx.log.info("Aktualizacja Paczek: "..message) end
    local function clear(name)
        local handle
        if name=="http" then handle=httpTimer;httpTimer=nil
        elseif name=="work" then handle=workTimer;workTimer=nil
        elseif name=="retry" then handle=timer;timer=nil end
        if handle then ctx:cancel(handle) end
    end
    local function removeDownload(req)
        if req and req.path and fs.remove then pcall(fs.remove,req.path) end
    end
    local function finish(message)
        if waiting then retired[waiting.path]=true;removeDownload(waiting) end
        busy=false;waiting=nil;clear("http");clear("work")
        if message then reason=message;log(message) end
    end
    local function after(delay,fn)
        workTimer=ctx:timer(delay,function() workTimer=nil;if not disposed then fn() end end)
    end
    local function goodPath()
        if not live or not work or not fs.isDir(live) or fs.isLink(live) or fs.isLink(work) or fs.isLink(home.."/chimera_wtyczki") then return false end
        local plugins=ctx.app and ctx.app.paths and normalizedHome(ctx.app.paths.plugins)
        return plugins==home.."/chimera_wtyczki"
    end
    local function safe()
        if disposed or not goodPath() then return false,"nieprawidlowy katalog kodu" end
        if type(opts.safe)~="function" then return false,"brak kontroli bezczynnosci" end
        local ok,result,why=pcall(opts.safe)
        if not ok or result~=true then return false,why or "czekam na bezczynny i potwierdzony stan postaci" end
        return true
    end
    local function decode(body)
        local ok,data=pcall(json.decode,body)
        return ok and data or nil
    end
    local function request(url,limit,done)
        if not goodPath() or not fs.mkdir(work) or fs.isLink(work) then
            finish("nie mozna przygotowac katalogu pobierania; zachowano obecny kod");return
        end
        requestNumber=requestNumber+1
        local path=work.."/download-"..instance.."-"..requestNumber..".tmp"
        if fs.exists(path) or fs.isLink(path) then
            finish("plik pobierania juz istnieje; zachowano obecny kod");return
        end
        local label=url==MANIFEST and "opis wydania" or "kod wydania"
        waiting={url=url,path=path,limit=limit,done=done,serial=serial,label=label}
        log("pobieram "..label.."; limit 60 s")
        httpTimer=ctx:timer(60,function()
            httpTimer=nil
            if waiting then finish("timeout pobierania: "..waiting.label.." (60 s); zachowano obecny kod") end
        end)
        -- getHTTP events report the final redirected URL; some client
        -- versions also limit bodies returned through HTTP events. File completion is correlated with our unique
        -- local path, including GitHub's redirects to its asset host.
        local ok,result=pcall(opts.downloadFile or downloadFile,path,url)
        if not ok or result==false then finish("nie mozna rozpoczac pobierania "..label) end
    end
    local function pathKey(path)
        return type(path)=="string" and path:gsub("\\","/") or nil
    end
    ctx:on("sysDownloadDone",function(_,path,size)
        path=pathKey(path)
        if path and retired[path] then retired[path]=nil;removeDownload({path=path});return end
        local req=waiting
        if not req or req.path~=path or req.serial~=serial then return end
        waiting=nil;clear("http")
        if fs.isLink(path) or fs.isDir(path) or not fs.exists(path) then
            removeDownload(req);finish("niepoprawny pobrany plik; zachowano obecny kod");return
        end
        if type(size)=="number" and size>req.limit then
            removeDownload(req);finish("odpowiedz serwera przekracza limit");return
        end
        local ok,body=pcall(fs.read,path,req.limit)
        removeDownload(req)
        if not ok or type(body)~="string" or #body>req.limit then finish("nie mozna odczytac pliku lub odpowiedz przekracza limit");return end
        req.done(body)
    end)
    ctx:on("sysDownloadError",function(_,message,path)
        path=pathKey(path)
        if path and retired[path] then retired[path]=nil;removeDownload({path=path});return end
        if waiting and waiting.path==path then
            finish("blad pobierania "..waiting.label..": "..tostring(message).."; zachowano obecny kod")
        end
    end)
    local apply
    local function retry()
        clear("retry")
        if pending and not disposed then timer=ctx:timer(15,function() timer=nil;apply() end) end
    end
    local function reportReload(expected)
        local ok,result=pcall(opts.reload,expected)
        return ok and result==true
    end
    apply=function()
        if not pending or disposed then return end
        if pending.auto and not enabled then pending=nil;return end
        local ready,why=safe()
        if not ready then reason=why;retry();return end
        local candidate=pending
        if not fs.isDir(stage) or fs.isLink(stage) or #fs.list(stage)~=#FILES then
            pending=nil;finish("zmieniono przygotowany folder; zachowano obecny kod");return
        end
        for _,name in ipairs(FILES) do
            if fs.isLink(stage.."/"..name) or fs.read(stage.."/"..name)~=candidate.files[name] then
                pending=nil;finish("zmieniono przygotowany plik; zachowano obecny kod");return
            end
        end
        local backup=stage.."-previous"
        local failed=stage.."-failed"
        if fs.exists(backup) or fs.exists(failed) then finish("kolizja katalogu kopii; zachowano obecny kod");pending=nil;return end
        -- Both renames are on the same profile filesystem. A failure leaves
        -- the old directory in place or restores it without touching state.
        local moved=fs.rename(live,backup)
        if not moved then finish("nie mozna przygotowac kopii poprzedniej wersji");pending=nil;return end
        local swapped=fs.rename(stage,live)
        if not swapped then
            local restored=fs.rename(backup,live)
            pending=nil;finish(restored and "podmiana nieudana; przywrocono poprzedni kod" or "nie udalo sie przywrocic folderu; kopia: "..backup)
            return
        end
        pending=nil;reason=nil
        -- reload is synchronous and checks the newly started API. Scope
        -- disposal removes this updater's timers; this call stack completes
        -- the rollback even when the new module cannot start.
        if reportReload(candidate.version) then
            disposed=true
            log("zainstalowano "..candidate.version.."; poprzedni kod: "..backup)
        else
            local putAside=fs.rename(live,failed)
            local restored=putAside and fs.rename(backup,live)
            if restored then
                local restarted=reportReload(current)
                log("nowa wersja nie uruchomila sie; przywrocono kod "..current..
                    (restarted and ". " or ", ponowne uruchomienie niepotwierdzone. ").."Wadliwy kod: "..failed)
            else log("nie udalo sie przywrocic folderu; poprzedni kod: "..backup) end
            disposed=true
        end
    end
    local function stageFiles(files,manifest,automatic)
        if not goodPath() or not fs.mkdir(work) then finish("nie mozna przygotowac katalogu pobierania");return end
        local base=work.."/v"..manifest.version.."-"..tostring(math.floor(now()*1000))
        stage=base
        local suffix=0
        while fs.exists(stage) and suffix<100 do suffix=suffix+1;stage=base.."-"..suffix end
        if fs.exists(stage) or not fs.mkdir(stage) or fs.isLink(stage) then finish("nie mozna przygotowac nowego folderu");return end
        local index=1
        local function one()
            local name=FILES[index]
            if not name then
                busy=false;pending={version=manifest.version,auto=automatic,files=files};lastVersion=manifest.version
                reason="wydanie pobrane; czekam na bezpieczna bezczynnosc"
                log(reason.." ("..manifest.version..").")
                apply();return
            end
            local source=files[name]
            -- Compilation validates syntax; the returned chunk is NEVER run.
            local compiler=loadstring or load
            local ok,chunk=pcall(compiler,source,"@paczki-update/"..name)
            if not ok or type(chunk)~="function" then finish("blad skladni pliku "..name.."; zachowano obecny kod");return end
            local wrote=fs.write(stage.."/"..name,source)
            if not wrote or fs.read(stage.."/"..name)~=source then finish("nie potwierdzono zapisu pliku "..name);return end
            index=index+1;after(0.001,one)
        end
        one()
    end
    local function bundle(manifest,automatic)
        request(manifest.url,manifest.bytes,function(body)
            if #body~=manifest.bytes then finish("rozmiar wydania nie zgadza sie z manifestem");return end
            local state=S.new(body)
            local function hash()
                if S.step(state,16) then
                    if S.finish(state)~=manifest.sha256 then finish("suma SHA-256 nie zgadza sie z manifestem");return end
                    local files,why=U.validateBundle(decode(body),manifest.version)
                    if not files then finish(why);return end
                    stageFiles(files,manifest,automatic)
                else after(0.001,hash) end
            end
            after(0.001,hash)
        end)
    end
    function api.check(automatic)
        if disposed then return false end
        if automatic and not enabled then return false end
        if busy or pending then if not automatic then log("pobieranie lub oczekiwanie juz trwa") end;return false end
        serial=serial+1;busy=true;reason=nil;lastCheck=now()
        request(MANIFEST,32768,function(body)
            local manifest,why=U.validateManifest(decode(body))
            if not manifest then finish(why);return end
            local getter=opts.mudletVersion or getMudletVersion
            local ok,mudlet=pcall(getter,"string")
            mudlet=ok and tostring(mudlet):match("^(%d+%.%d+%.%d+)") or nil
            if not version(mudlet) or newer(manifest.minMudlet,mudlet) then
                finish("wydanie wymaga Mudleta "..manifest.minMudlet.." lub nowszego");return
            end
            lastVersion=manifest.version
            if not newer(manifest.version,current) then finish(not automatic and "masz najnowsza wersje "..current or nil);return end
            bundle(manifest,automatic)
        end)
        return true
    end
    function api.setEnabled(value)
        value=value==true
        local ok,result=pcall(ctx.save,ctx,"aktualizacje",{schema=1,enabled=value})
        if not ok or result==false then log("nie zapisano ustawienia");return false end
        enabled=value
        if not enabled then
            if pending and pending.auto then pending=nil;clear("retry") end
            -- Cancellation invalidates all HTTP/hash/staging callbacks owned
            -- by an automatic check, including responses arriving after OFF.
            if busy and api.automatic then serial=serial+1;finish(nil) end
        end
        log("automatyczne aktualizacje "..(enabled and "wlaczone" or "wylaczone"))
        return true
    end
    function api.status()
        return {enabled=enabled,busy=busy,pending=pending and pending.version or nil,
            current=current,available=lastVersion,lastCheck=lastCheck,reason=reason,manifest=MANIFEST,
            download=waiting and waiting.label or nil}
    end
    function api.show()
        local s=api.status()
        log("wersja "..current.."; auto: "..(enabled and "on" or "off")..
            (busy and "; pobieranie" or "")..(s.pending and "; oczekuje "..s.pending or "")..
            (reason and "; "..reason or "")..". /paczki aktualizuj | /paczki autoaktualizacja on|off")
    end
    local originalCheck=api.check
    api.check=function(automatic) if not busy and not pending then api.automatic=automatic==true end;return originalCheck(automatic) end
    startTimer=ctx:timer(30,function() startTimer=nil;api.check(true) end)
    checkTimer=ctx:timer(6*60*60,function() api.check(true) end,true)
    ctx:cleanup(function()
        disposed=true;serial=serial+1
        removeDownload(waiting)
        for path in pairs(retired) do removeDownload({path=path}) end
        waiting=nil;pending=nil
        clear("http");clear("work");clear("retry")
        if startTimer then ctx:cancel(startTimer);startTimer=nil end
        if checkTimer then ctx:cancel(checkTimer);checkTimer=nil end
    end)
    return api
end
return U
