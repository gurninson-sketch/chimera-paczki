package.path="chimera_wtyczki/?.lua;"..package.path
local create=require("chimera_paczki.planner")
local cases,checks=0,0
local function ok(v,why) checks=checks+1;assert(v,why or "assertion failed") end
local function eq(want,got,why) ok(want==got,(why or "value")..": expected "..tostring(want)..", got "..tostring(got)) end
local function test(name,fn) fn();cases=cases+1;print("PASS "..name) end
local function fixture(options)
 local e={timers={},seq=0,time=0,cpu=0,maxTimers=0}
 local ctx={}
 function ctx:timer(delay,fn)
  e.seq=e.seq+1;e.timers[e.seq]={at=e.time+delay,fn=fn}
  local n=0;for _ in pairs(e.timers) do n=n+1 end;e.maxTimers=math.max(e.maxTimers,n)
  return e.seq
 end
 function ctx:cancel(id) e.timers[id]=nil end
 function ctx:cleanup(fn) e.cleanup=fn end
 local opts={clock=function() return e.cpu end,quantum=4,budget=0.005,delay=0.001}
 for k,v in pairs(options or {}) do opts[k]=v end
 e.p=create(ctx,opts)
 function e:step()
  local id,at
  for k,t in pairs(self.timers) do if not at or t.at<at or (t.at==at and k<id) then id,at=k,t.at end end
  if not id then return false end
  local t=self.timers[id];self.timers[id]=nil;self.time=at;t.fn();return true
 end
 function e:drain() for _=1,10000 do if not self:step() then return end end;error("timer loop") end
 return e
end
test("deferred work preserves multiple values and nil holes",function()
 local e=fixture();local called,done=false,0
 e.p.run(function() called=true;return 7,nil,"tail" end,function(good,a,b,c) done=done+1;eq(true,good);eq(7,a);eq(nil,b);eq("tail",c) end)
 eq(false,called);eq(1,e.p.status().active);e:drain();eq(true,called);eq(1,done);eq(0,e.p.status().active);eq(1,e.maxTimers)
end)
test("bounded work quanta yield to unrelated events",function()
 local e=fixture();local progress,done=0,0
 e.p.run(function() for i=1,100 do progress=i;e.p.checkpoint() end;return progress end,function(good,n) eq(true,good);eq(100,n);done=done+1 end)
 e:step();eq(4,progress);eq(0,done);eq(false,e.p.active());eq(nil,e.p.cache());eq(false,e.p.checkpoint())
 local beats=0;while e:step() do beats=beats+1;eq(false,e.p.active());eq(nil,e.p.cache()) end
 ok(beats>=24);eq(1,done);eq(25,e.p.status().yields);eq(1,e.maxTimers)
end)
test("suspended worker cache is isolated from main callbacks and other workers",function()
 local e=fixture();local first
 e.p.run(function() first=e.p.cache();first.example=9;for _=1,5 do e.p.checkpoint() end;eq(9,e.p.cache().example) end,function(good) eq(true,good) end)
 e:step();eq(nil,e.p.cache())
 e.p.run(function() local second=e.p.cache();eq(nil,second.example);ok(first~=second) end,function(good) eq(true,good) end)
 e:drain();eq(0,e.p.status().active)
end)
test("cancellation retires timer and suppresses completion",function()
 local e=fixture();local done=0
 local cancel=e.p.run(function() for _=1,100 do e.p.checkpoint() end end,function() done=done+1 end)
 e:step();cancel();cancel();e:drain();eq(0,done);eq(0,e.p.status().active);eq(1,e.p.status().cancelled);eq(nil,next(e.timers))
end)
test("invalidated input stops before another slice",function()
 local e=fixture();local valid,progress,done=true,0,0
 e.p.run(function() for i=1,100 do progress=i;e.p.checkpoint() end end,function(good,a,why) done=done+1;eq(false,good);eq(nil,a);eq("changed",why) end,function() return valid,"changed" end)
 e:step();eq(4,progress);valid=false;e:drain();eq(4,progress);eq(1,done);eq(0,e.p.status().active)
end)
test("worker errors report once and release state",function()
 local e=fixture();local done=0
 e.p.run(function() error("test failure") end,function(good,a,why) done=done+1;eq(false,good);ok(why:find("test failure",1,true)) end)
 e:drain();eq(1,done);eq(0,e.p.status().active);eq(nil,next(e.timers))
end)
test("clock budget yields before unit limit",function()
 local e=fixture({quantum=10000});local progress=0
 e.p.run(function() for i=1,10 do progress=i;e.cpu=e.cpu+0.004;e.p.checkpoint() end end,function(good) eq(true,good) end)
 e:step();eq(2,progress);ok(e.p.status().yields>0);e:drain();eq(10,progress);ok(e.p.status().maxSliceMs<=8.001)
end)
test("disposal cancels all jobs and rejects new work",function()
 local e=fixture();local done=0
 for _=1,3 do e.p.run(function() for _=1,100 do e.p.checkpoint() end end,function() done=done+1 end) end
 e:step();e.cleanup();e.p.dispose();e:drain();eq(0,done);eq(0,e.p.status().active);eq(3,e.p.status().cancelled)
 e.p.run(function() error("disposed worker ran") end,function() done=done+1 end);e:drain();eq(0,done)
end)
test("completion may queue a fresh worker",function()
 local e=fixture();local done=0
 e.p.run(function() return 1 end,function(good,n) eq(true,good);eq(1,n);done=done+1;e.p.run(function() return 2 end,function(good2,n2) eq(true,good2);eq(2,n2);done=done+1 end) end)
 e:drain();eq(2,done);eq(2,e.p.status().completed);eq(0,e.p.status().active)
end)
test("repeated completed jobs retain no pending timers or cache",function()
 local e=fixture()
 for _=1,100 do e.p.run(function() for _=1,13 do e.p.checkpoint() end;return true end,function(good) eq(true,good) end);e:drain();eq(0,e.p.status().active);eq(nil,e.p.cache());eq(nil,next(e.timers)) end
 eq(100,e.p.status().completed);eq(1,e.maxTimers)
end)
print(string.format("PLANNER: %d scenarios, %d assertions passed",cases,checks))
