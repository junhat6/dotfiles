-- Run: /opt/homebrew/opt/luajit/bin/luajit ~/.config/dotfiles/tests/test_github_repos.lua
-- Exercises chooser/task lifecycle without network requests or live settings writes.
local tasks, timers, stored, startOK = {}, {}, nil, true
local function repo(name)
 return {nameWithOwner=name, description='description', updatedAt='2026-10-31'}
end
hs = {
 urlevent={openURL=function() end},
 settings={get=function() return stored end, set=function(_, value) stored=value; return true end},
 json={decode=function(line)
  if line=='alpha' then return repo('owner/alpha') end
  if line=='beta' then return repo('org/beta') end
  error('invalid JSON')
 end},
 chooser={new=function(callback)
  local c={q='', callback=callback}
  function c:query(q) if q==nil then return self.q end; self.q=q; if self.changed then self.changed(q) end; return self end
  function c:placeholderText() return self end
  function c:queryChangedCallback(fn) self.changed=fn; return self end
  function c:choices(rows) self.rows=rows; return self end
  function c:show() self.visible=true; return self end
  function c:hide() self.visible=false; return self end
  return c
 end},
 task={new=function(path, done, stream, args)
  assert(type(stream)=='function', 'must drain output while process is running')
  local t={done=done, stream=stream, args=args}
  function t:start() return startOK end
  function t:terminate() self.terminated=true end
  tasks[#tasks+1]=t; return t
 end},
 timer={doAfter=function(_, callback)
  local t={fire=callback}; function t:stop() self.stopped=true end
  timers[#timers+1]=t; return t
 end},
}
local GitHubRepos=dofile(os.getenv('HOME')..'/.hammerspoon/modules/github_repos.lua')
local function has(c, text)
 for _, row in ipairs(c.chooser.rows) do
  if row.text:find(text, 1, true) then return row end
 end
 error('missing row: '..text)
end
local c=GitHubRepos.new({})
c:show(); c.chooser:query('alpha')
has(c, '取得中')
assert(#tasks==1)
c:show(); assert(#tasks==1, 'repeated opening must not start duplicate requests')
c.chooser:query('alpha')
local first=tasks[1]
first.stream(first, 'al', '')
first.stream(first, 'pha\n', '')
first.done(0, 'beta\n', '')
has(c, 'owner/alpha'); assert(#c.chooser.rows==1, 'query survives async completion')
first.stream(nil, 'beta\n', '') -- final streaming notification must not duplicate tail
assert(#c.cachedChoices==2 and timers[1].stopped)
c.chooser:query('missing'); has(c, '0件')
c.chooser:query('OWNER ALPHA'); has(c, 'owner/alpha')
c.chooser:query('['); has(c, '0件') -- literal matching, no Lua pattern errors
local reused=GitHubRepos.new({})
reused:show(); assert(#tasks==1 and #reused.cachedChoices==2, 'reload reuses disk cache')
c.cacheUpdatedAt=0; c:show(); assert(#tasks==2)
c.chooser:query('alpha'); has(c, 'owner/alpha'); has(c, '更新中')
local timedOut=tasks[2]
timers[2].fire()
has(c, '取得に失敗'); assert(timedOut.terminated and not c.loading)
local retry=has(c, '再試行'); c.chooser.callback(retry)
assert(#tasks==3 and c.chooser.q=='alpha')
timedOut.done(0, 'beta\n', '')
assert(c.task==tasks[3] and c.loading, 'late completion cannot overwrite new task')
tasks[3].done(1, '', 'HTTP 429 rate limited')
assert(has(c, '再試行').subText:find('429', 1, true))
has(c, 'owner/alpha')
c:refresh(); tasks[4].done(0, 'alpha\nbad\n', '')
has(c, '再試行'); assert(#c.cachedChoices==2, 'malformed output must preserve cache')
c:refresh(); tasks[5].done(0, '', '')
has(c, 'アクセス可能'); assert(#c.cachedChoices==0, 'valid empty list is cached')
c:show(); assert(#tasks==5, 'fresh empty list does not repeatedly fetch')
startOK=false; c:refresh(); has(c, '再試行'); assert(not c.loading and c.task==nil)
startOK=true; c:refresh(); local last=tasks[#tasks]; c:stop()
assert(last.terminated and timers[#timers].stopped)
last.done(0, 'beta\n', ''); assert(#c.cachedChoices==0)
-- Limit rendering, but search all entries, including those outside the visible page.
stored={repositories={},updatedAt=os.time()}
for i=1,10000 do stored.repositories[i]=repo('owner/repository-'..i) end
local large=GitHubRepos.new({})
local started=os.clock()
large:show(); assert(#large.chooser.rows==101)
large.chooser:query('repository-9999'); has(large, 'repository-9999')
print(string.format('PASS: lifecycle, filtering, persistence, streaming, errors, timeout/retry; 10,000 repos %.1fms', (os.clock()-started)*1000))
