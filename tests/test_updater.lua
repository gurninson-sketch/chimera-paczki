-- Deterministic HTTP/filesystem fixtures. No network, game or source execution.
package.path="chimera_wtyczki/?.lua;../chimera-501/src/?.lua;"..package.path
local U=require("chimera_paczki.updater")
local json=require("chimera.core.json")
local cases,checks=0,0
local function ok(v,why) checks=checks+1;assert(v,why or "assertion failed") end
local function eq(a,b,why) ok(a==b,(why or "value")..": expected "..tostring(a)..", got "..tostring(b)) end
local function test(name,fn) fn();cases=cases+1;print("PASS "..name) end
local function digest(s) local h=U.sha256.new(s);while not U.sha256.step(h,16) do end;return U.sha256.finish(h) end
local LIVE="/profile/chimera_wtyczki/chimera_paczki"
local function fixture(options)
 options=options or {}
 local e={time=0,seq=0,timers={},events={},requests={},files={[LIVE.."/init.lua"]="old init"},
  dirs={["/profile"]=true,["/profile/chimera_wtyczki"]=true,[LIVE]=true},links={},moves={},reloads={},logs={},safe=true,saved={}}
 if options.enabled==false then e.saved.aktualizacje={schema=1,enabled=false} end
 local ctx={app={paths={home=options.home or "/profile",plugins="/profile/chimera_wtyczki"}},log={}}
 function ctx.log.info(s) e.logs[#e.logs+1]=s end
 function ctx:saved(k,d) return e.saved[k] or d end
 function ctx:save(k,v) e.saved[k]=v;return true end
 function ctx:on(name,fn) e.events[name]=fn end
 function ctx:timer(delay,fn,repeatable) e.seq=e.seq+1;e.timers[e.seq]={at=e.time+delay,fn=fn,delay=repeatable and delay};return e.seq end
 function ctx:cancel(id) e.timers[id]=nil end
 function ctx:cleanup(fn) e.cleanup=fn end
 local fs={}
 function fs.isDir(p) return e.dirs[p]==true end
 function fs.exists(p) return e.files[p]~=nil or e.dirs[p]==true end
 function fs.isLink(p) return e.links[p]==true end
 function fs.mkdir(p) if options.mkdirFail then return false end;e.dirs[p]=true;return true end
 function fs.read(p) return e.files[p] end
 function fs.write(p,s) if options.writeFail then return false end;e.files[p]=s;return true end
 function fs.list(p) local out={};for name in pairs(e.files) do local head=name:match("^(.*)/[^/]+$");if head==p then out[#out+1]=name:match("([^/]+)$") end end;return out end
 function fs.rename(a,b)
  e.moves[#e.moves+1]={a,b}
  if options.renameFail==#e.moves then return nil end
  if not fs.exists(a) or fs.exists(b) then return nil end
  local files,dirs={},{}
  for p,s in pairs(e.files) do if p==a or p:sub(1,#a+1)==a.."/" then files[b..p:sub(#a+1)]=s;e.files[p]=nil end end
  for p,s in pairs(e.dirs) do if p==a or p:sub(1,#a+1)==a.."/" then dirs[b..p:sub(#a+1)]=s;e.dirs[p]=nil end end
  for p,s in pairs(files) do e.files[p]=s end;for p,s in pairs(dirs) do e.dirs[p]=s end
  return true
 end
 e.api=U.create(ctx,{json=json,fs=fs,version="1.5.12",now=function() return e.time end,
  getHTTP=function(url) e.requests[#e.requests+1]=url;return options.httpResult end,
  mudletVersion=function() return options.mudlet or "4.20.0" end,
  safe=function() return e.safe,"busy fixture" end,
  reload=function(v) e.reloads[#e.reloads+1]=v;return not options.reloadFail or v=="1.5.12" end})
 function e:advance(dt)
  local limit=self.time+dt
  for _=1,100000 do
   local id,at
   for k,t in pairs(self.timers) do if t.at<=limit and (not at or t.at<at or t.at==at and k<id) then id,at=k,t.at end end
   if not id then self.time=limit;return end
   local t=self.timers[id];self.timers[id]=nil;self.time=at
   if t.delay then self.timers[id]={at=at+t.delay,fn=t.fn,delay=t.delay} end
   t.fn()
  end
  error("timer storm")
 end
 function e:reply(url,body) self.events.sysGetHttpDone("sysGetHttpDone",url,body) end
 function e:release(mutator)
  local files={};for _,name in ipairs(U.files) do files[name]="return {} -- "..name end
  local data={schema=1,version="1.5.13",files=files}
  if mutator then mutator(data) end
  local payload=json.encode(data)
  local manifest={schema=1,version=data.version,min_mudlet=options.minimum or "4.20.0",bundle={url="https://github.com/gurninson-sketch/chimera-paczki/releases/download/v"..data.version.."/chimera-paczki-runtime.json",bytes=#payload,sha256=digest(payload)}}
  return manifest,payload
 end
 function e:download(auto,mutator)
  local m,p=self:release(mutator)
  self.api.check(auto);self:reply(U.manifestUrl,json.encode(m));self:reply(m.bundle.url,p);self:advance(0.5)
  return m,p
 end
 return e
end

test("SHA-256 standard vectors and bounded stepping",function()
 eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",digest(""))
 eq("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",digest("abc"))
 eq("41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3",digest(string.rep("a",1000)))
 local h=U.sha256.new(string.rep("x",10000));eq(false,U.sha256.step(h,16));eq(1025,h.offset)
end)
test("fixed manifest and bundle URLs reject another host or tag",function()
 local e=fixture();local m=e:release();ok(U.validateManifest(m));m.bundle.url=m.bundle.url:gsub("v1.5.13","v1.5.14");eq(nil,U.validateManifest(m))
 m=e:release();m.version="01.5.13";eq(nil,U.validateManifest(m));m=e:release();m.bundle.sha256="x";eq(nil,U.validateManifest(m))
end)
test("exact flat allowlist rejects omissions traversal extras and bytecode",function()
 local e=fixture();local _,p=e:release();local b=json.decode(p);ok(U.validateBundle(b,"1.5.13"))
 b.files["init.lua"]=nil;eq(nil,U.validateBundle(b,"1.5.13"));b=json.decode(p);b.files["../state.json"]="return {}";eq(nil,U.validateBundle(b,"1.5.13"))
 b=json.decode(p);b.files["init.lua"]="\27Lua";eq(nil,U.validateBundle(b,"1.5.13"));b=json.decode(p);b.files["init.lua"]="a\0b";eq(nil,U.validateBundle(b,"1.5.13"))
end)
test("verified release replaces folder and retains previous code and profile state",function()
 local e=fixture();e.files["/profile/Database_npcs.db"]="NPC STATE";e.files[LIVE.."/my-note.txt"]="USER NOTE";e:download(false)
 eq(2,#e.moves);eq("1.5.13",e.reloads[1]);eq("return {} -- init.lua",e.files[LIVE.."/init.lua"])
 eq("NPC STATE",e.files["/profile/Database_npcs.db"]);eq("old init",e.files[e.moves[1][2].."/init.lua"]);eq("USER NOTE",e.files[e.moves[1][2].."/my-note.txt"])
end)
test("syntax compiler never executes source during validation",function()
 local e=fixture();_G.paczkiUpdaterShouldNotExecute=nil;e.safe=false
 e:download(false,function(d) d.files["routes.lua"]="_G.paczkiUpdaterShouldNotExecute=true; return {}" end)
 eq(nil,_G.paczkiUpdaterShouldNotExecute);eq("1.5.13",e.api.status().pending);eq(0,#e.moves)
end)
test("update waits while busy and applies after readiness",function()
 local e=fixture();e.safe=false;e:download(false);e:advance(120);eq(0,#e.moves);eq("1.5.13",e.api.status().pending)
 e.safe=true;e:advance(15);eq(2,#e.moves);eq("1.5.13",e.reloads[1])
end)
test("default auto starts at thirty seconds and repeats every six hours",function()
 local e=fixture();eq(true,e.api.status().enabled);e:advance(29);eq(0,#e.requests);e:advance(1);eq(1,#e.requests)
 e:advance(6*3600-30);eq(2,#e.requests)
end)
test("OFF cancels pending automatic application without renaming",function()
 local e=fixture();e.safe=false;e:download(true);eq("1.5.13",e.api.status().pending);e.api.setEnabled(false);e.safe=true;e:advance(60)
 eq(nil,e.api.status().pending);eq(0,#e.moves);eq(false,e.saved.aktualizacje.enabled)
end)
test("OFF cancels automatic download and ignores late response",function()
 local e=fixture();local m,p=e:release();e.api.check(true);e:reply(U.manifestUrl,json.encode(m));e.api.setEnabled(false);e:reply(m.bundle.url,p);e:advance(60)
 eq(false,e.api.status().busy);eq(0,#e.moves);eq(nil,e.api.status().pending)
end)
test("manual update works when automatic checks are disabled",function()
 local e=fixture({enabled=false});e:advance(60);eq(0,#e.requests);e:download(false);eq(2,#e.moves)
end)
test("checksum mismatch rejects release before staging",function()
 local e=fixture();local m,p=e:release();m.bundle.sha256=string.rep("0",64);e.api.check(false);e:reply(U.manifestUrl,json.encode(m));e:reply(m.bundle.url,p);e:advance(1)
 eq(0,#e.moves);eq("old init",e.files[LIVE.."/init.lua"]);eq(false,e.api.status().busy)
end)
test("truncation oversize and unrelated HTTP responses cannot install",function()
 local e=fixture();local m,p=e:release();e.api.check(false);e:reply("https://unrelated.example/","{}");eq(true,e.api.status().busy)
 e:reply(U.manifestUrl,json.encode(m));e:reply(m.bundle.url,p:sub(2));e:advance(1);eq(0,#e.moves);eq(false,e.api.status().busy)
 e=fixture();e.api.check(false);e:reply(U.manifestUrl,string.rep("x",32769));eq(false,e.api.status().busy)
end)
test("HTTP timeout ignores late completion and explicit refusal fails promptly",function()
 local e=fixture();local m=e:release();e.api.check(false);e:advance(30);e:reply(U.manifestUrl,json.encode(m));eq(1,#e.requests);eq(false,e.api.status().busy)
 e=fixture({httpResult=false});e.api.check(false);eq(false,e.api.status().busy);eq(0,#e.moves)
end)
test("minimum Mudlet and unknown client version block bundle download",function()
 for _,opts in ipairs({{minimum="4.21.0"},{mudlet="4.19.1"},{mudlet="unknown"}}) do
  local e=fixture(opts);local m=e:release();e.api.check(false);e:reply(U.manifestUrl,json.encode(m));eq(1,#e.requests);eq(false,e.api.status().busy);eq(0,#e.moves)
 end
end)
test("older release never replaces current code",function()
 local e=fixture();local m=e:release();m.version="1.5.11";m.bundle.url=m.bundle.url:gsub("v1.5.13","v1.5.11");e.api.check(false);e:reply(U.manifestUrl,json.encode(m));eq(1,#e.requests);eq(0,#e.moves)
end)
test("syntax and write failures retain live folder",function()
 local e=fixture();e:download(false,function(d) d.files["city.lua"]="local =" end);eq(0,#e.moves);eq("old init",e.files[LIVE.."/init.lua"])
 e=fixture({writeFail=true});e:download(false);eq(0,#e.moves);eq("old init",e.files[LIVE.."/init.lua"])
end)
test("symlinks and invalid profile paths fail closed",function()
 local e=fixture();e.links[LIVE]=true;e:download(false);eq(0,#e.moves)
 e=fixture({home="/profile/../elsewhere"});e:download(false);eq(0,#e.moves)
 e=fixture();e.links["/profile/chimera_wtyczki"]=true;e:download(false);eq(0,#e.moves)
end)
test("staged file mutation before idle is rejected",function()
 local e=fixture();e.safe=false;e:download(false)
 for p in pairs(e.files) do if p:find("/chimera_paczki_updates/",1,true) and p:match("/core.lua$") then e.files[p]="return {changed=true}" end end
 e.safe=true;e:advance(15);eq(0,#e.moves);eq(nil,e.api.status().pending);eq("old init",e.files[LIVE.."/init.lua"])
end)
test("failed second rename restores previous directory",function()
 local e=fixture({renameFail=2});e:download(false);eq(3,#e.moves);eq("old init",e.files[LIVE.."/init.lua"]);eq(0,#e.reloads)
end)
test("runtime failure restores code and invokes old handshake",function()
 local e=fixture({reloadFail=true});e:download(false);eq(4,#e.moves);eq("1.5.13",e.reloads[1]);eq("1.5.12",e.reloads[2]);eq("old init",e.files[LIVE.."/init.lua"])
end)
test("disposal cancels hashing staging and all timers",function()
 local e=fixture();local m,p=e:release();e.api.check(false);e:reply(U.manifestUrl,json.encode(m));e:reply(m.bundle.url,p);e.cleanup();e:advance(40000)
 eq(0,#e.moves);eq(nil,next(e.timers));eq(2,#e.requests)
end)
print(string.format("UPDATER: %d scenarios, %d assertions passed",cases,checks))
