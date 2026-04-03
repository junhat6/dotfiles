-- =============================================================================
-- Hammerspoon configuration
-- =============================================================================

-- =============================================================================
-- 設定自動リロード
-- =============================================================================
local function reloadConfig(files)
  local doReload = false
  for _, file in pairs(files) do
    if file:sub(-4) == ".lua" then
      doReload = true
    end
  end
  if doReload then
    hs.reload()
  end
end

hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()
hs.alert.show("Hammerspoon loaded")

-- =============================================================================
-- ウィンドウ管理 (ctrl + alt + 矢印/Enter)
-- =============================================================================
-- 左半分
hs.hotkey.bind({"ctrl", "alt"}, "Left", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit(hs.layout.left50)
end)

-- 右半分
hs.hotkey.bind({"ctrl", "alt"}, "Right", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit(hs.layout.right50)
end)

-- 上半分
hs.hotkey.bind({"ctrl", "alt"}, "Up", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit({0, 0, 1, 0.5})
end)

-- 下半分
hs.hotkey.bind({"ctrl", "alt"}, "Down", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit({0, 0.5, 1, 0.5})
end)

-- 最大化
hs.hotkey.bind({"ctrl", "alt"}, "Return", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit({0, 0, 1, 1})
end)

-- 中央配置 (70%サイズ)
hs.hotkey.bind({"ctrl", "alt"}, "C", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit({0.15, 0.15, 0.7, 0.7})
end)

-- =============================================================================
-- 四隅配置 (ctrl + alt + shift + 矢印)
-- =============================================================================
-- 左上
hs.hotkey.bind({"ctrl", "alt", "shift"}, "Left", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit({0, 0, 0.5, 0.5})
end)

-- 右上
hs.hotkey.bind({"ctrl", "alt", "shift"}, "Right", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit({0.5, 0, 0.5, 0.5})
end)

-- 左下
hs.hotkey.bind({"ctrl", "alt", "shift"}, "Down", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit({0, 0.5, 0.5, 0.5})
end)

-- 右下
hs.hotkey.bind({"ctrl", "alt", "shift"}, "Up", function()
  local win = hs.window.focusedWindow()
  if not win then return end
  win:moveToUnit({0.5, 0.5, 0.5, 0.5})
end)

-- =============================================================================
-- アプリ切り替え (alt + キー)
-- =============================================================================
local appShortcuts = {
  { key = "g", app = "Google Chrome" },
  { key = "t", app = "Ghostty" },
  { key = "s", app = "Slack" },
  { key = "o", app = "Obsidian" },
  { key = "f", app = "Finder" },
  { key = "d", app = "Discord" },
}

for _, shortcut in ipairs(appShortcuts) do
  hs.hotkey.bind({"alt"}, shortcut.key, function()
    hs.application.launchOrFocus(shortcut.app)
  end)
end

-- =============================================================================
-- クリップボード履歴 (cmd + shift + V)
-- =============================================================================
local clipboardHistory = {}
local maxHistorySize = 50
local lastChangeCount = hs.pasteboard.changeCount()

-- 履歴からchoices形式に変換
local function buildChoices(filterQuery)
  local choices = {}
  local lowerQuery = (filterQuery or ""):lower()
  for _, item in ipairs(clipboardHistory) do
    if lowerQuery == "" or item.text:lower():find(lowerQuery, 1, true) then
      local displayText = item.text:gsub("\n", "↵ "):sub(1, 80)
      if #item.text > 80 then
        displayText = displayText .. "..."
      end
      table.insert(choices, {
        text = displayText,
        subText = item.subText .. " (" .. #item.text .. " chars)",
        fullText = item.text
      })
    end
  end
  return choices
end

-- クリップボード監視
local function checkClipboard()
  local currentChangeCount = hs.pasteboard.changeCount()
  if currentChangeCount ~= lastChangeCount then
    lastChangeCount = currentChangeCount
    local content = hs.pasteboard.getContents()
    if content and content ~= "" then
      -- 重複を削除
      for i, item in ipairs(clipboardHistory) do
        if item.text == content then
          table.remove(clipboardHistory, i)
          break
        end
      end
      -- 先頭に追加
      table.insert(clipboardHistory, 1, {
        text = content,
        subText = os.date("%Y-%m-%d %H:%M:%S")
      })
      -- 最大サイズを超えたら古いものを削除
      while #clipboardHistory > maxHistorySize do
        table.remove(clipboardHistory)
      end
    end
  end
end

clipboardTimer = hs.timer.new(0.5, checkClipboard)
clipboardTimer:start()

-- 履歴表示用のchooser
local clipboardChooser = hs.chooser.new(function(choice)
  if choice then
    hs.pasteboard.setContents(choice.fullText)
    hs.eventtap.keyStroke({"cmd"}, "v")
  end
end)

clipboardChooser:placeholderText("クリップボード履歴を検索...")
clipboardChooser:searchSubText(true)
clipboardChooser:queryChangedCallback(function(query)
  clipboardChooser:choices(buildChoices(query))
end)

-- 履歴を表示
hs.hotkey.bind({"cmd", "shift"}, "V", function()
  clipboardChooser:choices(buildChoices(""))
  clipboardChooser:show()
end)
