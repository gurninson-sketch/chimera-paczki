-- Shared address downloads/imports: synthetic filesystem and event loop.
package.path="chimera_wtyczki/?.lua;../chimera-501/src/?.lua;"..package.path
local create=dofile("chimera_wtyczki/chimera_paczki/memory.lua")
local json=require("chimera.core.json")
local cases,checks=0,0
local function ok(value,why) checks=checks+1;assert(value,why or "check failed") end
local function eq(a,b) ok(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn();cases=cases+1;print("PASS "..name) end
local function row(name,room,last) return {recipient=name,roomHashes={room},count=1,last=last or 10,postal=false} end
local function pack(records) return {format="chimera_paczki_baza",version=1,memory={schema=1,records=records or {}}} end
local function fixture(opts)
 opts=opts or {}
 local e={time=0,seq=0,timers={},events={},files={},dirs={["/profile"]=true},links={},requests={},logs={},safe=true,settings={},commits=0}
 if opts.enabled==false then e.settings.baza_synchronizacja={enabled=false} end
 local ctx={app={paths={home=opts.home or "/profile"}},log={info=function(s) e.logs[#e.logs+1]=s end}}
 function ctx:saved(k,d) return e.settings[k] or d end
 function ctx:save(k,v) if opts.settingFail then return false end;e.settings[k]=v;return true end
 function ctx:on(n,fn) e.events[n]=fn end
 function ctx:timer(delay,fn,repeated) e.seq=e.seq+1;e.timers[e.seq]={at=e.time+delay,fn=fn,repeatDelay=repeated and delay};return e.seq end
 function ctx:cancel(id) e.timers[id]=nil end
 function ctx:cleanup(fn) e.cleanup=fn end
 local fs={}
 function fs.exists(p) return e.files[p]~=nil or e.dirs[p]==true end
 function fs.isDir(p) return e.dirs[p]==true end
 function fs.isLink(p) return e.links[p]==true end
 function fs.mkdir(p) if opts.mkdirFail then return false end;e.dirs[p]=true;return true end
 function fs.read(p,limit) local b=e.files[p];return b and (limit and b:sub(1,limit+1) or b) end
 function fs.write(p,b) if opts.writeFail then return false end;e.files[p]=b;return true end
 function fs.remove(p) e.files[p]=nil;return true end
 e.memory=create({schema=1,records=opts.localRecords or {}},{now=function() return e.time end,save=function(value)
  if opts.commitFail then return false end;e.commits=e.commits+1;e.persisted=value;return true
 end})
 e.controller=e.memory.createSharedSync(ctx,{json=json,fs=fs,now=function() return e.time end,safe=function() return e.safe,"kurier pracuje" end,
  downloadFile=function(path,url) e.requests[#e.requests+1]={path=path,url=url};return opts.downloadResult end})
 function e:advance(seconds)
  local untilTime=self.time+seconds
  for _=1,10000 do
   local index,at
   for id,t in pairs(self.timers) do if t.at<=untilTime and (not at or t.at<at or t.at==at and id<index) then index,at=id,t.at end end
   if not index then self.time=untilTime;return end
   local t=self.timers[index];self.timers[index]=nil;self.time=at
   if t.repeatDelay then self.timers[index]={at=at+t.repeatDelay,fn=t.fn,repeatDelay=t.repeatDelay} end
   t.fn()
  end
  error("timer storm")
 end
 function e:reply(value,request,windows)
  request=request or self.requests[#self.requests];self.files[request.path]=type(value)=="string" and value or json.encode(value)
  self.events.sysDownloadDone("sysDownloadDone",windows and request.path:gsub("/","\\") or request.path,#self.files[request.path],{url="https://redirect.example/asset"})
 end
 return e
end

test("fixed catalogue URL matches completion by owned path despite redirects",function()
 local e=fixture();ok(e.controller.check(false));eq(e.requests[1].url,"https://raw.githubusercontent.com/gurninson-sketch/chimera-paczki/main/data/addresses.json")
 e:reply(pack({bruno=row("Bruno","b")}));eq(e.memory.count(),1);eq(e.controller.status().busy,false);eq(e.files[e.requests[1].path],nil)
 local backup=e.controller.status().backup;ok(backup);local data=json.decode(e.files[backup]);eq(data.format,"chimera_paczki_baza");eq(next(data.memory.records),nil)
end)
test("merge preserves local discoveries and mobile locations; repeated import is idempotent",function()
 local e=fixture({localRecords={torquato=row("Torquato","old",20),localonly=row("Localonly","mine",30)}})
 local data=pack({torquato=row("Torquato","new",40),bruno=row("Bruno","b")})
 e.controller.check(false);e:reply(data);eq(e.memory.count(),3)
 local r=e.memory.find("Torquato");eq(#r.roomHashes,2);eq(r.roomHashes[1],"new");eq(r.roomHashes[2],"old")
 e.controller.check(false);e:reply(data);eq(e.commits,1);eq(e.memory.find("Torquato").count,1)
end)
test("active courier can download but backup and merge defer until safe",function()
 local e=fixture();e.safe=false;e.controller.check(false);e:reply(pack({bruno=row("Bruno","b")}))
 eq(e.memory.count(),0);eq(e.controller.status().pending,true);eq(e.controller.status().backup,nil)
 e:advance(30);eq(e.memory.count(),0);e.safe=true;e:advance(15);eq(e.memory.count(),1);eq(e.controller.status().pending,false)
end)
test("bad JSON format records and conflicting postal type preserve local data",function()
 local invalid={"not-json",pack({bruno={recipient="Wrong",roomHashes={"b"},last=10,count=1}}),{format="other",version=1,memory={schema=1,records={}}},pack({bruno={recipient="Bruno",roomHashes={"b"},last=10,count=1,postal=true}})}
 for _,data in ipairs(invalid) do local e=fixture({localRecords={bruno=row("Bruno","mine")}});e.controller.check(false);e:reply(data)
  eq(e.memory.find("Bruno").roomHashes[1],"mine");eq(e.commits,0);eq(e.controller.status().backup,nil);ok(e.controller.status().reason)
 end
end)
test("missing linked directory or oversized file cannot be imported",function()
 for _,kind in ipairs({"missing","link","directory","large"}) do
  local e=fixture();e.controller.check(false);local p=e.requests[1].path
  if kind=="link" then e.links[p]=true elseif kind=="directory" then e.dirs[p]=true elseif kind=="large" then e.files[p]=string.rep("x",4*1024*1024+1) end
  e.events.sysDownloadDone("sysDownloadDone",p,kind=="large" and 4*1024*1024+1 or 0)
  eq(e.commits,0);eq(e.controller.status().busy,false);ok(e.controller.status().reason)
 end
end)
test("backup and persistence failures preserve original records and allow retry",function()
 for _,kind in ipairs({"writeFail","commitFail"}) do
  local options={[kind]=true};local e=fixture(options);e.controller.check(false);e:reply(pack({bruno=row("Bruno","b")}))
  eq(e.memory.count(),0);ok(e.controller.status().reason);options[kind]=false
  e.controller.check(false);e:reply(pack({bruno=row("Bruno","b")}));eq(e.memory.count(),1)
 end
end)
test("timeout cleans partial file; late old completion cannot finish a newer request",function()
 local e=fixture();e.controller.check(false);local old=e.requests[1];e.files[old.path]="partial";e:advance(60)
 eq(e.files[old.path],nil);eq(e.controller.status().busy,false);ok(e.controller.status().reason:find("timeout",1,true))
 e.controller.check(false);local latest=e.requests[2];ok(latest.path~=old.path)
 e:reply(pack({old=row("Old","old")}),old);eq(e.memory.count(),0);eq(e.files[old.path],nil);eq(e.controller.status().busy,true)
 e:reply(pack({bruno=row("Bruno","b")}),latest);eq(e.memory.count(),1)
end)
test("default automatic check starts45s repeats6h and disabled setting prevents checks",function()
 local e=fixture();e:advance(44);eq(#e.requests,0);e:advance(1);eq(#e.requests,1);e:reply(pack());e:advance(21600-45);eq(#e.requests,2)
 local off=fixture({enabled=false});off:advance(21600);eq(#off.requests,0)
end)
test("OFF cancels automatic download and queued merge but manual check works when disabled",function()
 local e=fixture();e.safe=false;e.controller.check(true);local old=e.requests[1];e.controller.setEnabled(false)
 e:reply(pack({bruno=row("Bruno","b")}),old);eq(e.memory.count(),0);eq(e.files[old.path],nil)
 e.controller.check(false);e:reply(pack({bruno=row("Bruno","b")}));eq(e.controller.status().pending,true)
 e.controller.setEnabled(false);e.safe=true;e:advance(15);eq(e.memory.count(),1)
 local q=fixture();q.safe=false;q.controller.check(true);q:reply(pack({bruno=row("Bruno","b")}));q.controller.setEnabled(false);q.safe=true;q:advance(100);eq(q.memory.count(),0)
end)
test("Windows paths match success and errors while unrelated events are ignored",function()
 local e=fixture();e.controller.check(false);e.events.sysDownloadError("sysDownloadError","other","/elsewhere");eq(e.controller.status().busy,true)
 e:reply(pack({bruno=row("Bruno","b")}),nil,true);eq(e.memory.count(),1)
 e.controller.check(false);local p=e.requests[2].path;e.files[p]="partial";e.events.sysDownloadError("sysDownloadError","network",p:gsub("/","\\"))
 eq(e.controller.status().busy,false);eq(e.files[p],nil);ok(e.controller.status().reason:find("network",1,true))
end)
test("cleanup removes partial file all timers and pending import",function()
 local e=fixture();e.controller.check(false);local old=e.requests[1];e.files[old.path]="partial";e.cleanup()
 eq(next(e.timers),nil);eq(e.files[old.path],nil);eq(e.controller.check(false),false);e:reply(pack({bruno=row("Bruno","b")}),old);eq(e.memory.count(),0)
 local q=fixture();q.safe=false;q.controller.check(false);q:reply(pack({bruno=row("Bruno","b")}));q.cleanup();q.safe=true;q:advance(500);eq(q.memory.count(),0)
end)
test("unsafe directory and failed setting save prevent changes",function()
 local e=fixture();e.links["/profile/chimera_paczki_updates"]=true;eq(e.controller.check(false),false);eq(#e.requests,0)
 local s=fixture({enabled=false,settingFail=true});eq(s.controller.setEnabled(true),false);eq(s.controller.status().enabled,false)
end)
print(string.format("SHARED_BASE: %d scenarios, %d assertions passed",cases,checks))
