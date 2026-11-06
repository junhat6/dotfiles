"""Exercise registration callbacks with a fake Hammerspoon host; never edit live settings."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
LUA = shutil.which('lua') or shutil.which('luajit')


@unittest.skipUnless(LUA, 'Lua runtime is not installed')
class OverwriteConfirmation(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / '.hammerspoon/init.lua').read_text()
        self.host = '''
local stored, writes, prompts, alerts = {}, 0, {}, {}
local answer = "キャンセル"
local dynamicSlotsSettingsKey = "test-slots"
hs = {
 settings = {
  get = function() return stored end,
  set = function(_, value) stored = value; writes = writes + 1; return true end,
 },
 dialog = {blockAlert = function(title, message, first, second)
  assert(first == "キャンセル" and second == "上書き")
  table.insert(prompts, message); return answer
 end},
 alert = {show = function(message) table.insert(alerts, message) end},
}
'''

    def run_lua(self, code):
        result = subprocess.run([LUA, '-'], input=code, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_url_registration_preserves_existing_values_until_confirmed(self):
        start = self.source.index('local function isWebURL(')
        end = self.source.index('local function clearDynamicSlot(')
        self.run_lua(self.host + self.source[start:end] + '''
assert(saveDynamicSlot("1", "First", "https://example.com/first"))
assert(writes == 1 and #prompts == 0, "empty slots need no confirmation")
local previous = stored["1"]
assert(not saveDynamicSlot("1", "Second", "https://example.com/second"))
assert(writes == 1 and stored["1"] == previous, "cancel must preserve the old slot")
assert(prompts[1]:find("First", 1, true) and prompts[1]:find("Second", 1, true))
assert(prompts[1]:find("https://example.com/first", 1, true))
assert(prompts[1]:find("https://example.com/second", 1, true))
answer = "上書き"
assert(saveDynamicSlot("1", "Second", "https://example.com/second"))
assert(writes == 2 and stored["1"].title == "Second")
answer = "キャンセル"
assert(not saveDynamicSlot("1", "Second", "https://example.com/second"))
assert(writes == 2 and #prompts == 3, "occupied slots always require confirmation")
assert(not saveDynamicSlot("0", "Invalid", "https://example.com"))
assert(not saveDynamicSlot("2", "Invalid", "file:///tmp/example"))
assert(writes == 2 and #prompts == 3)
hs.settings.set = function() return false end
assert(not saveDynamicSlot("2", "Failure", "https://example.com"))
assert(alerts[#alerts]:find("失敗", 1, true), "save failures must be visible")
''')

    def test_window_bookmark_cancel_keeps_previous_target(self):
        helper = self.source[self.source.index('local function confirmOverwrite('):
                             self.source.index('local function saveDynamicSlot(')]
        callbacks = self.source[self.source.index('local markedWindowID = nil'):
                                self.source.index('local clipboardHistory = {}')]
        self.run_lua(self.host + helper + '''
local actions, focused, windows, nextID = {}, nil, {}, 1
local function newWindow()
 local id = nextID; nextID = nextID + 1
 local win = {id = function() return id end, focus = function() focused = id end}
 windows[id] = win; return win
end
local active = newWindow()
hs.window = {focusedWindow = function() return active end, get = function(id) return windows[id] end}
local function windowLabel(win) return "Window " .. win:id() end
local function bindWithHelp(_, key, _, _, action) actions[key] = action end
''' + callbacks + '''
actions[","]()
assert(#prompts == 0)
active = newWindow()
actions[","]()
actions["."]()
assert(focused == 1 and #prompts == 1, "cancel must retain the first window")
answer = "上書き"
actions[","]()
actions["."]()
assert(focused == 2 and #prompts == 2)
''')
