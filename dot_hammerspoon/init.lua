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

configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig)
configWatcher:start()
hs.alert.show("Hammerspoon loaded")

-- =============================================================================
-- ショートカット登録とヘルプ
-- =============================================================================
local hotkeyCatalog = {}
local registeredHotkeys = {}

local modifierAliases = {
	cmd = "cmd",
	command = "cmd",
	ctrl = "ctrl",
	control = "ctrl",
	alt = "alt",
	option = "alt",
	shift = "shift",
}

local modifierDisplayOrder = {
	{ name = "cmd", symbol = "⌘" },
	{ name = "ctrl", symbol = "⌃" },
	{ name = "alt", symbol = "⌥" },
	{ name = "shift", symbol = "⇧" },
}

local keySymbols = {
	left = "←",
	right = "→",
	up = "↑",
	down = "↓",
	["return"] = "↩",
	space = "Space",
}

local function normalizedModifiers(mods)
	local normalized = {}
	for _, modifier in ipairs(mods) do
		local canonicalName = modifierAliases[modifier:lower()]
		if canonicalName then
			normalized[canonicalName] = true
		end
	end
	return normalized
end

local function formatHotkey(mods, key)
	local modifiers = normalizedModifiers(mods)
	local parts = {}
	for _, modifier in ipairs(modifierDisplayOrder) do
		if modifiers[modifier.name] then
			table.insert(parts, modifier.symbol)
		end
	end

	local normalizedKey = tostring(key):lower()
	table.insert(parts, keySymbols[normalizedKey] or tostring(key):upper())
	return table.concat(parts)
end

local function hotkeyIdentifier(mods, key)
	return formatHotkey(mods, key) .. ":" .. tostring(key):lower()
end

local function addHelpEntry(mods, key, category, description, action, options)
	table.insert(hotkeyCatalog, {
		mods = mods,
		key = key,
		category = category,
		description = description,
		action = action,
		searchTerms = options and options.searchTerms or nil,
	})
end

local function bindWithHelp(mods, key, category, description, action, options)
	local identifier = hotkeyIdentifier(mods, key)
	if registeredHotkeys[identifier] then
		error("Duplicate hotkey registration: " .. formatHotkey(mods, key))
	end

	registeredHotkeys[identifier] = true
	hs.hotkey.bind(mods, key, action)
	addHelpEntry(mods, key, category, description, action, options)
end

local function resolveHelpValue(value, fallback)
	if type(value) ~= "function" then
		return tostring(value or fallback or "")
	end

	local succeeded, result = pcall(value)
	if succeeded and result ~= nil then
		return tostring(result)
	end
	return fallback or ""
end

local function helpSearchTerms(entry)
	local value = entry.searchTerms
	if type(value) == "function" then
		local succeeded, result = pcall(value)
		value = succeeded and result or nil
	end
	if type(value) == "table" then
		return table.concat(value, " ")
	end
	return type(value) == "string" and value or ""
end

local function buildHotkeyHelpChoices()
	local choices = {}
	for catalogIndex, entry in ipairs(hotkeyCatalog) do
		local description = resolveHelpValue(entry.description, "説明を取得できませんでした")
		local searchTerms = helpSearchTerms(entry)
		local subText = entry.category
		if searchTerms ~= "" then
			subText = subText .. " — " .. searchTerms
		end
		table.insert(choices, {
			text = formatHotkey(entry.mods, entry.key) .. "  " .. description,
			subText = subText,
			catalogIndex = catalogIndex,
		})
	end
	return choices
end

local hotkeyHelpContext = nil
local hotkeyHelpActionTimer = nil

local function runHelpAction(action)
	local context = hotkeyHelpContext
	hotkeyHelpContext = nil
	if not context then
		action()
		return
	end

	local restoredWindow = false
	if context.window then
		local succeeded, windowID = pcall(function()
			return context.window:id()
		end)
		if succeeded and windowID then
			local currentWindow = hs.window.get(windowID)
			if currentWindow then
				currentWindow:focus()
				restoredWindow = true
			end
		end
	end
	if not restoredWindow and context.application then
		pcall(function()
			context.application:activate(true)
		end)
	end

	hotkeyHelpActionTimer = hs.timer.doAfter(0.15, function()
		hotkeyHelpActionTimer = nil
		action()
	end)
end

local hotkeyHelpChooser = hs.chooser.new(function(choice)
	local entry = choice and hotkeyCatalog[choice.catalogIndex]
	if entry then
		runHelpAction(entry.action)
	else
		hotkeyHelpContext = nil
	end
end)

hotkeyHelpChooser:placeholderText("ショートカットを検索...")
hotkeyHelpChooser:searchSubText(true)

local function showHotkeyHelp()
	hotkeyHelpContext = {
		window = hs.window.focusedWindow(),
		application = hs.application.frontmostApplication(),
	}
	hotkeyHelpChooser:query("")
	hotkeyHelpChooser:choices(buildHotkeyHelpChoices())
	hotkeyHelpChooser:show()
end

-- =============================================================================
-- Capsomnia: 蓋を閉じている間のスリープ防止 (ctrl + alt + S)
-- =============================================================================
-- 蓋閉じ・バッテリー時の制御はCapsomniaに任せ、同アプリが監視するCaps Lockを操作する。
-- hs.caffeinateやpmsetを別途操作すると、Capsomniaの状態と食い違うため使わない。
local capsomniaCheckTimer = nil
local capsomniaCheckTask = nil
local capsomniaRequest = 0

local function stopCapsomniaCheck()
	capsomniaRequest = capsomniaRequest + 1
	if capsomniaCheckTimer then
		capsomniaCheckTimer:stop()
		capsomniaCheckTimer = nil
	end
	if capsomniaCheckTask then
		capsomniaCheckTask:terminate()
		capsomniaCheckTask = nil
	end
end

local function toggleCapsomnia()
	if #hs.application.applicationsForBundleID("com.github.fuji-mak.capsomnia") == 0 then
		hs.alert.show("Capsomniaを起動してから、もう一度切り替えてください")
		return
	end

	stopCapsomniaCheck()
	local request = capsomniaRequest
	local enabled = not hs.hid.capslock.get()
	if hs.hid.capslock.set(enabled) ~= enabled then
		hs.alert.show("Caps Lockの状態を変更できませんでした")
		return
	end

	-- Capsomniaの監視間隔は250ms。実際のスリープ設定を確認してから結果を表示する。
	capsomniaCheckTimer = hs.timer.doAfter(1, function()
		capsomniaCheckTimer = nil
		capsomniaCheckTask = hs.task.new("/usr/bin/pmset", function(exitCode, stdout)
			if request ~= capsomniaRequest then
				return
			end
			capsomniaCheckTask = nil
			local state = stdout:match("SleepDisabled%s+(%d+)")
			if exitCode == 0 and state == (enabled and "1" or "0") then
				hs.alert.show(enabled and "Capsomnia ON：蓋を閉じても処理を継続" or "Capsomnia OFF：通常のスリープに戻しました")
			else
				hs.alert.show("Capsomniaの切り替えを確認できません。メニューバーの状態を確認してください")
			end
		end, { "-g" })
		if not capsomniaCheckTask or not capsomniaCheckTask:start() then
			capsomniaCheckTask = nil
			hs.alert.show("スリープ設定を確認できませんでした")
		end
	end)
end

bindWithHelp({ "ctrl", "alt" }, "S", "電源", "蓋閉じ時のスリープ防止を切り替え（Capsomnia）", toggleCapsomnia, {
	searchTerms = { "移動", "スリープ", "Capsomnia", "Caps Lock", "keep awake" },
})

-- =============================================================================
-- ウィンドウ管理 (ctrl + alt + 矢印/Enter, ctrl + alt + M)
-- =============================================================================
-- 次のモニターへ移動
bindWithHelp({ "ctrl", "alt" }, "M", "ウィンドウ", "次のモニターへ移動", function()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end

	if #hs.screen.allScreens() < 2 then
		hs.alert.show("移動先のモニターがありません")
		return
	end

	win:moveToScreen(win:screen():next(), true, true)
end)

-- 左半分
bindWithHelp({ "ctrl", "alt" }, "Left", "ウィンドウ", "左半分に配置", function()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	win:moveToUnit(hs.layout.left50)
end)

-- 右半分
bindWithHelp({ "ctrl", "alt" }, "Right", "ウィンドウ", "右半分に配置", function()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	win:moveToUnit(hs.layout.right50)
end)

-- 最大化
bindWithHelp({ "ctrl", "alt" }, "Return", "ウィンドウ", "最大化", function()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	win:moveToUnit({ 0, 0, 1, 1 })
end)

-- 中央配置 (70%サイズ)
bindWithHelp({ "ctrl", "alt" }, "C", "ウィンドウ", "中央に70%サイズで配置", function()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	win:moveToUnit({ 0.15, 0.15, 0.7, 0.7 })
end)

-- フルスクリーン用Spaceを除き、Mission Control上のデスクトップ順で返す。
local function userSpacesForScreen(screen)
	local screenSpaces, errorMessage = hs.spaces.spacesForScreen(screen)
	if not screenSpaces then
		return nil, errorMessage
	end

	local userSpaces = {}
	for _, spaceID in ipairs(screenSpaces) do
		local spaceType = hs.spaces.spaceType(spaceID)
		if spaceType == "user" then
			table.insert(userSpaces, spaceID)
		end
	end
	return userSpaces
end

local windowSpaceMoveInProgress = false

local function desktopShortcutKey(desktopNumber)
	if desktopNumber == 10 then
		return "0"
	end
	return tostring(desktopNumber)
end

local function desktopNumberForWindow(win, userSpaces)
	local currentSpaces = hs.spaces.windowSpaces(win)
	if not currentSpaces then
		return nil
	end

	for desktopNumber, userSpaceID in ipairs(userSpaces) do
		for _, currentSpaceID in ipairs(currentSpaces) do
			if currentSpaceID == userSpaceID then
				return desktopNumber
			end
		end
	end
	return nil
end

local function windowDragPoint(win)
	local zoomButton = win:zoomButtonRect()
	if zoomButton and zoomButton.w > 0 and zoomButton.h > 0 then
		return {
			x = zoomButton.x + zoomButton.w + 10,
			y = zoomButton.y + zoomButton.h / 2,
		}
	end

	local frame = win:frame()
	return {
		x = frame.x + math.min(100, frame.w / 2),
		y = frame.y + 12,
	}
end

local function waitForMoveHotkeyRelease(action, attempts)
	attempts = attempts or 0
	local modifiers = hs.eventtap.checkKeyboardModifiers()
	if not modifiers.ctrl and not modifiers.shift then
		action()
		return
	end
	if attempts >= 100 then
		windowSpaceMoveInProgress = false
		hs.alert.show("キーを離してからもう一度実行してください")
		return
	end

	hs.timer.doAfter(0.03, function()
		waitForMoveHotkeyRelease(action, attempts + 1)
	end)
end

-- macOS 15ではmoveWindowToSpaceが成功を返しても移動しないため、
-- タイトルバーを掴んだままmacOS標準のデスクトップ切替を送って移動する。
local function dragWindowToDesktop(win, targetDesktopNumber, targetSpaceID)
	local targetShortcutKey = desktopShortcutKey(targetDesktopNumber)
	local targetShortcut = hs.hotkey.systemAssigned({ "ctrl" }, targetShortcutKey)
	if not targetShortcut or not targetShortcut.enabled then
		windowSpaceMoveInProgress = false
		hs.alert.show("システム設定でControl + " .. targetShortcutKey .. "のデスクトップ切替を有効にしてください")
		return
	end

	local originalMousePosition = hs.mouse.absolutePosition()
	local dragPoint = windowDragPoint(win)
	local draggedPoint = { x = dragPoint.x + 1, y = dragPoint.y }

	hs.mouse.absolutePosition(dragPoint)
	hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, dragPoint):post()
	hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDragged, draggedPoint):post()

	hs.timer.doAfter(0.1, function()
		hs.eventtap.keyStroke({ "ctrl" }, targetShortcutKey, 0)

		-- デスクトップ切替アニメーションが終わるまでタイトルバーを掴み続ける。
		hs.timer.doAfter(0.8, function()
			local releasePoint = hs.mouse.absolutePosition()
			hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, releasePoint):post()
			hs.mouse.absolutePosition(originalMousePosition)

			hs.timer.doAfter(0.15, function()
				local moved = false
				local currentSpaces = hs.spaces.windowSpaces(win)
				for _, currentSpaceID in ipairs(currentSpaces or {}) do
					if currentSpaceID == targetSpaceID then
						moved = true
						break
					end
				end

				windowSpaceMoveInProgress = false
				if moved then
					hs.alert.show("デスクトップ" .. targetDesktopNumber .. "へ移動しました")
				else
					hs.alert.show("デスクトップ" .. targetDesktopNumber .. "へ移動できませんでした")
				end
			end)
		end)
	end)
end

local function moveFocusedWindowToDesktop(desktopNumber)
	if windowSpaceMoveInProgress then
		hs.alert.show("別のウィンドウを移動中です")
		return
	end

	local win = hs.window.focusedWindow()
	if not win then
		hs.alert.show("移動するウィンドウがありません")
		return
	end
	if win:isFullScreen() then
		hs.alert.show("フルスクリーンのウィンドウは移動できません")
		return
	end

	local screen = win:screen()
	local userSpaces, errorMessage = userSpacesForScreen(screen)
	if not userSpaces then
		hs.alert.show("デスクトップの一覧を取得できませんでした")
		print("デスクトップ一覧の取得に失敗: " .. tostring(errorMessage))
		return
	end

	local targetSpaceID = userSpaces[desktopNumber]
	if not targetSpaceID then
		hs.alert.show("デスクトップ" .. desktopNumber .. "がありません")
		return
	end

	local sourceDesktopNumber = desktopNumberForWindow(win, userSpaces)
	if not sourceDesktopNumber then
		hs.alert.show("現在のデスクトップを特定できませんでした")
		return
	end
	if sourceDesktopNumber == desktopNumber then
		hs.alert.show("すでにデスクトップ" .. desktopNumber .. "にあります")
		return
	end

	windowSpaceMoveInProgress = true
	waitForMoveHotkeyRelease(function()
		dragWindowToDesktop(win, desktopNumber, targetSpaceID)
	end)
end

-- Ctrl + Shift + 数字で、フォーカス中のウィンドウを同じ画面のデスクトップへ移動する。
for desktopNumber = 1, 9 do
	local targetDesktopNumber = desktopNumber
	bindWithHelp(
		{ "ctrl", "shift" },
		tostring(targetDesktopNumber),
		"ウィンドウ",
		"デスクトップ" .. targetDesktopNumber .. "へ移動",
		function()
			moveFocusedWindowToDesktop(targetDesktopNumber)
		end,
		{ searchTerms = { "Mission Control", "Space", "デスクトップ移動" } }
	)
end

-- =============================================================================
-- URLランチャー (alt + 数字, alt + L)
-- =============================================================================
local pinnedLinks = {
	{
		key = "1",
		title = "Idea Boost: Open PRs",
		url = "https://github.com/engineer-first/idea-boost/pulls?q=sort%3Aupdated-desc+is%3Apr+state%3Aopen",
	},
}

local chromeBundleID = "com.google.Chrome"
local maxChromeHistoryChoices = 50
local dynamicSlotsSettingsKey = "urlLauncherDynamicSlotsV1"
local chromeEpochOffsetSeconds = 11644473600
local ChromeTabs = require("modules.chrome_tabs")
local chromeTabs = ChromeTabs.new({ bundleID = chromeBundleID, timeoutSeconds = 5 })
local urlLauncherPreferredWindowID = nil
local urlLauncherSnapshot = nil
local urlLauncherTabsLoading = false
local urlLauncherRequestID = 0

local function isWebURL(url)
	return type(url) == "string" and (url:match("^http://") or url:match("^https://"))
end

-- hs.settingsの値を検証し、文字列キーのスロットだけを返す。
local function loadDynamicSlots()
	local succeeded, storedSlots = pcall(hs.settings.get, dynamicSlotsSettingsKey)
	if not succeeded or type(storedSlots) ~= "table" then
		return {}
	end

	local slots = {}
	for slotNumber = 2, 9 do
		local slotKey = tostring(slotNumber)
		local storedSlot = storedSlots[slotKey]
		if type(storedSlot) == "table" and isWebURL(storedSlot.url) then
			slots[slotKey] = {
				title = type(storedSlot.title) == "string" and storedSlot.title ~= "" and storedSlot.title
					or storedSlot.url,
				url = storedSlot.url,
				savedAt = type(storedSlot.savedAt) == "number" and storedSlot.savedAt or nil,
			}
		end
	end
	return slots
end

local function saveDynamicSlot(slotKey, title, url)
	slotKey = tostring(slotKey)
	if not slotKey:match("^[2-9]$") or not isWebURL(url) then
		return false
	end

	local slots = loadDynamicSlots()
	slots[slotKey] = {
		title = type(title) == "string" and title ~= "" and title or url,
		url = url,
		savedAt = os.time(),
	}

	local succeeded = pcall(hs.settings.set, dynamicSlotsSettingsKey, slots)
	if not succeeded then
		hs.alert.show("Alt + " .. slotKey .. " への登録に失敗しました")
		return false
	end

	hs.alert.show("Alt + " .. slotKey .. " に登録: " .. slots[slotKey].title)
	return true
end

local function clearDynamicSlot(slotKey)
	slotKey = tostring(slotKey)
	if not slotKey:match("^[2-9]$") then
		return false
	end

	local slots = loadDynamicSlots()
	if not slots[slotKey] then
		return false
	end

	slots[slotKey] = nil
	local succeeded = pcall(hs.settings.set, dynamicSlotsSettingsKey, slots)
	if not succeeded then
		hs.alert.show("Alt + " .. slotKey .. " の登録解除に失敗しました")
		return false
	end

	hs.alert.show("Alt + " .. slotKey .. " の登録を解除しました")
	return true
end

local function openURLInChrome(url, preferredWindowID)
	chromeTabs:openURL(url, preferredWindowID)
end

for _, link in ipairs(pinnedLinks) do
	bindWithHelp({ "alt" }, link.key, "URL", link.title .. "を開く", function()
		openURLInChrome(link.url)
	end, { searchTerms = { link.title, link.url, "固定URL" } })
end

local function registerCurrentChromeTab(slotKey)
	chromeTabs:currentTab(function(tab, errorMessage)
		if not tab then
			hs.alert.show(errorMessage)
			return
		end
		if not isWebURL(tab.url) then
			hs.alert.show("http:// または https:// のページだけ登録できます")
			return
		end
		saveDynamicSlot(slotKey, tab.title, tab.url)
	end)
end

-- 動的スロットのホットキーは初期化時に一度だけ登録する。
for slotNumber = 2, 9 do
	local slotKey = tostring(slotNumber)
	bindWithHelp({ "alt" }, slotKey, "URL", function()
		local slot = loadDynamicSlots()[slotKey]
		if slot then
			return "「" .. slot.title .. "」を開く"
		end
		return "URLスロット" .. slotKey .. "は未登録"
	end, function()
		local slot = loadDynamicSlots()[slotKey]
		if not slot then
			hs.alert.show(
				"Alt + " .. slotKey .. " は未登録です。Alt + Shift + " .. slotKey .. "で現在のChromeタブを登録できます"
			)
			return
		end
		openURLInChrome(slot.url)
	end, {
		searchTerms = function()
			local slot = loadDynamicSlots()[slotKey]
			return slot and { "URLスロット" .. slotKey, slot.title, slot.url } or { "URLスロット" .. slotKey, "未登録" }
		end,
	})

	bindWithHelp({ "alt", "shift" }, slotKey, "URL", "現在のChromeタブをURLスロット" .. slotKey .. "へ登録", function()
		registerCurrentChromeTab(slotKey)
	end, { searchTerms = { "Chrome", "URLスロット" .. slotKey, "登録", "上書き" } })
end

local function shellQuote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

-- ChromeのLocal Stateから最後に使ったプロファイルを取得する。
local function chromeHistoryPath()
	local chromeDataDirectory = os.getenv("HOME") .. "/Library/Application Support/Google/Chrome"
	local profileDirectory = "Default"
	local localState = hs.json.read(chromeDataDirectory .. "/Local State")
	if
		localState
		and localState.profile
		and type(localState.profile.last_used) == "string"
		and localState.profile.last_used:match("^[%w _-]+$")
	then
		profileDirectory = localState.profile.last_used
	end

	return chromeDataDirectory .. "/" .. profileDirectory .. "/History"
end

local function formatChromeVisitTime(chromeVisitTime)
	local visitTime = tonumber(chromeVisitTime)
	if not visitTime then
		return "日時不明"
	end

	local unixTimestamp = math.floor(visitTime / 1000000 - chromeEpochOffsetSeconds)
	local succeeded, formatted = pcall(os.date, "%m/%d %H:%M", unixTimestamp)
	if not succeeded or type(formatted) ~= "string" then
		return "日時不明"
	end
	return formatted
end

-- Chrome起動中は履歴DBがロックされるため、一時コピーをSQLiteで読み込む。
local function chromeHistoryChoices(excludedURLs)
	local historyPath = chromeHistoryPath()
	if hs.fs.attributes(historyPath, "mode") ~= "file" then
		return {}, "Chrome履歴が見つかりません"
	end

	local snapshotPath = os.tmpname()
	local _, copied = hs.execute("/bin/cp " .. shellQuote(historyPath) .. " " .. shellQuote(snapshotPath))
	if not copied then
		os.remove(snapshotPath)
		return {}, "Chrome履歴を読み込めませんでした"
	end

	local choices = {}
	local hiddenURLs = {}
	for _, link in ipairs(pinnedLinks) do
		hiddenURLs[link.url] = true
	end
	for url in pairs(excludedURLs or {}) do
		hiddenURLs[url] = true
	end

	local database = hs.sqlite3.open(snapshotPath)
	if not database then
		os.remove(snapshotPath)
		return {}, "Chrome履歴を読み込めませんでした"
	end

	local querySucceeded = pcall(function()
		local now = os.time()
		local visitsSince30Days = math.floor((now - 30 * 24 * 60 * 60 + chromeEpochOffsetSeconds) * 1000000)
		local visitsSince7Days = math.floor((now - 7 * 24 * 60 * 60 + chromeEpochOffsetSeconds) * 1000000)
		local query = string.format([[
SELECT
	u.url,
	u.title,
	COUNT(*) AS visits_30d,
	SUM(CASE WHEN v.visit_time >= %.0f THEN 1 ELSE 0 END) AS visits_7d,
	MAX(v.visit_time) AS last_visit_time
FROM visits AS v
JOIN urls AS u ON u.id = v.url
WHERE u.hidden = 0
	AND v.visit_time >= %.0f
	AND (u.url LIKE 'http://%%' OR u.url LIKE 'https://%%')
GROUP BY u.id, u.url, u.title
ORDER BY visits_30d DESC, visits_7d DESC, last_visit_time DESC
LIMIT 100;
]], visitsSince7Days, visitsSince30Days)

		for row in database:nrows(query) do
			if not hiddenURLs[row.url] then
				table.insert(choices, {
					text = row.title and row.title ~= "" and row.title or row.url,
					subText = "履歴 — 30日 "
						.. row.visits_30d
						.. "回・7日 "
						.. row.visits_7d
						.. "回・最終 "
						.. formatChromeVisitTime(row.last_visit_time)
						.. " — "
						.. row.url,
					title = row.title and row.title ~= "" and row.title or row.url,
					url = row.url,
					source = "history",
				})
			end
			if #choices >= maxChromeHistoryChoices then
				break
			end
		end
	end)

	database:close()
	os.remove(snapshotPath)

	if not querySucceeded then
		return {}, "Chrome履歴を読み込めませんでした"
	end
	return choices
end

local function chromeWindowLabel(tab)
	local name = tab.windowName ~= "" and tab.windowName or "Chromeウィンドウ"
	return name .. " (ID " .. tab.windowID .. ")"
end

local function urlLauncherChoices(snapshot, tabsLoading)
	local choices = {}
	local visibleURLs = {}
	if snapshot then
		for _, tab in ipairs(snapshot.tabs) do
			if type(tab.url) == "string" and tab.url ~= "" then
				table.insert(choices, {
					text = tab.title ~= "" and tab.title or tab.url,
					subText = "開いている — " .. chromeWindowLabel(tab) .. " — " .. tab.url,
					title = tab.title ~= "" and tab.title or tab.url,
					url = tab.url,
					source = "open",
					tab = tab,
				})
				visibleURLs[tab.url] = true
			end
		end
	elseif tabsLoading then
		table.insert(choices, {
			text = "開いているタブを取得中...",
			subText = "Chromeが応答しなくても登録済みURLと履歴は利用できます",
			valid = false,
		})
	end

	for _, link in ipairs(pinnedLinks) do
		table.insert(choices, {
			text = "⌥" .. link.key .. "  " .. link.title,
			subText = "登録済み・固定 (Alt + " .. link.key .. ") — " .. link.url,
			title = link.title,
			url = link.url,
			source = "pinned",
		})
		visibleURLs[link.url] = true
	end

	local slots = loadDynamicSlots()
	for slotNumber = 2, 9 do
		local slotKey = tostring(slotNumber)
		local slot = slots[slotKey]
		if slot then
			local savedAt = slot.savedAt and os.date("%Y-%m-%d %H:%M", slot.savedAt) or "日時不明"
			table.insert(choices, {
				text = "⌥" .. slotKey .. "  " .. slot.title,
				subText = "登録済み (Alt + " .. slotKey .. ") — " .. slot.url .. " — 登録: " .. savedAt,
				title = slot.title,
				url = slot.url,
				source = "dynamic",
				slotKey = slotKey,
				registered = true,
			})
			visibleURLs[slot.url] = true
		else
			table.insert(choices, {
				text = "⌥" .. slotKey .. "  未登録",
				subText = "Alt + Shift + " .. slotKey .. "で現在のChromeタブを登録",
				source = "dynamic",
				slotKey = slotKey,
				registered = false,
				valid = false,
			})
		end
	end

	local historyChoices, historyError = chromeHistoryChoices(visibleURLs)
	for _, choice in ipairs(historyChoices) do
		table.insert(choices, choice)
	end
	return choices, historyError
end

local urlLauncher = hs.chooser.new(function(choice)
	if choice and choice.tab then
		chromeTabs:focusTab(choice.tab, function(succeeded, errorMessage)
			if not succeeded then
				hs.alert.show(errorMessage)
			end
		end)
	elseif choice and choice.url then
		openURLInChrome(choice.url, urlLauncherPreferredWindowID)
	end
end)

urlLauncher:placeholderText("URLを検索...")
urlLauncher:searchSubText(true)
urlLauncher:invalidCallback(function(choice)
	if choice and choice.slotKey then
		hs.alert.show(
			"Alt + " .. choice.slotKey .. " は未登録です。Alt + Shift + " .. choice.slotKey .. "で現在のChromeタブを登録できます"
		)
	end
end)

local function refreshURLLauncherChoices()
	local choices, historyError = urlLauncherChoices(urlLauncherSnapshot, urlLauncherTabsLoading)
	urlLauncher:choices(choices)
	return historyError
end

-- 右クリックしたURLを動的スロットへ登録し、登録済みスロットは解除できる。
local urlLauncherContextMenu = hs.menubar.new(false)
urlLauncher:rightClickCallback(function(row)
	if row == 0 then
		return
	end

	local choice = urlLauncher:selectedRowContents(row)
	if type(choice) ~= "table" then
		return
	end

	local menuItems = {}
	if type(choice.url) == "string" and choice.url ~= "" then
		table.insert(menuItems, {
			title = "新しいタブで開く",
			fn = function()
				chromeTabs:openNewTab(choice.url, urlLauncherPreferredWindowID, function(succeeded, errorMessage)
					if not succeeded then
						hs.alert.show(errorMessage)
					end
				end)
			end,
		})
	end

	if isWebURL(choice.url) then
		table.insert(menuItems, { title = "-" })
		for slotNumber = 2, 9 do
			local slotKey = tostring(slotNumber)
			table.insert(menuItems, {
				title = "Alt + " .. slotKey .. "に登録",
				fn = function()
					if saveDynamicSlot(slotKey, choice.title, choice.url) then
						refreshURLLauncherChoices()
					end
				end,
			})
		end
	end

	if choice.source == "dynamic" and choice.registered and choice.slotKey then
		table.insert(menuItems, { title = "-" })
		table.insert(menuItems, {
			title = "この登録を解除",
			fn = function()
				if clearDynamicSlot(choice.slotKey) then
					refreshURLLauncherChoices()
				end
			end,
		})
	end

	if #menuItems > 0 then
		urlLauncherContextMenu:setMenu(menuItems)
		urlLauncherContextMenu:popupMenu(hs.mouse.absolutePosition())
	end
end)

local function showURLLauncher()
	urlLauncherRequestID = urlLauncherRequestID + 1
	local requestID = urlLauncherRequestID
	urlLauncherSnapshot = nil
	urlLauncherPreferredWindowID = nil
	urlLauncherTabsLoading = chromeTabs:isRunning()
	urlLauncher:query("")
	local historyError = refreshURLLauncherChoices()
	urlLauncher:show()
	if historyError then
		hs.alert.show(historyError)
	end

	chromeTabs:listTabs(function(snapshot, errorMessage)
		if requestID ~= urlLauncherRequestID then
			return
		end
		urlLauncherTabsLoading = false
		if snapshot then
			urlLauncherSnapshot = snapshot
			urlLauncherPreferredWindowID = snapshot.preferredWindowID
		else
			print("Chromeタブ一覧の取得に失敗: " .. tostring(errorMessage))
			hs.alert.show("開いているChromeタブを取得できませんでした")
		end
		if urlLauncher:isVisible() then
			refreshURLLauncherChoices()
		end
	end)
end

bindWithHelp({ "alt" }, "L", "URL", "URLランチャーを開く", showURLLauncher)

-- =============================================================================
-- ウィンドウ選択 (alt + W/,/.)
-- =============================================================================
local function windowLabel(win)
	local app = win:application()
	local appName = app and app:name() or "不明なアプリ"
	local title = win:title() or ""
	if title == "" then
		return appName
	end
	return appName .. " — " .. title
end

-- 開いているウィンドウをタイトルまたはアプリ名で検索してフォーカスする
local function buildWindowChoices()
	local choices = {}
	for _, win in ipairs(hs.window.filter.default:getWindows()) do
		local app = win:application()
		local appName = app and app:name() or "不明なアプリ"
		local title = win:title() or ""
		table.insert(choices, {
			text = title ~= "" and title or appName,
			subText = appName,
			window = win,
		})
	end
	return choices
end

local windowChooser = hs.chooser.new(function(choice)
	if choice and choice.window then
		choice.window:focus()
	end
end)

windowChooser:placeholderText("ウィンドウを検索...")
windowChooser:searchSubText(true)

local function showWindowSwitcher()
	local choices = buildWindowChoices()
	if #choices == 0 then
		hs.alert.show("切り替え可能なウィンドウがありません")
		return
	end
	windowChooser:query("")
	windowChooser:choices(choices)
	windowChooser:show()
end

bindWithHelp({ "alt" }, "W", "ウィンドウ切り替え", "ウィンドウ検索を開く", showWindowSwitcher)

-- よく戻るウィンドウを記憶し、任意のアプリから復帰する
local markedWindowID = nil

bindWithHelp({ "alt" }, ",", "ウィンドウ切り替え", "現在のウィンドウを記憶", function()
	local win = hs.window.focusedWindow()
	if not win then
		return
	end
	markedWindowID = win:id()
	hs.alert.show("記憶しました: " .. windowLabel(win))
end)

bindWithHelp({ "alt" }, ".", "ウィンドウ切り替え", "記憶したウィンドウへ戻る", function()
	local markedWindow = markedWindowID and hs.window.get(markedWindowID)
	if not markedWindow then
		markedWindowID = nil
		hs.alert.show("記憶したウィンドウがありません")
		return
	end
	markedWindow:focus()
end)

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
				fullText = item.text,
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
				subText = os.date("%Y-%m-%d %H:%M:%S"),
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
		hs.eventtap.keyStroke({ "cmd" }, "v")
	end
end)

clipboardChooser:placeholderText("クリップボード履歴を検索...")
clipboardChooser:searchSubText(true)
clipboardChooser:queryChangedCallback(function(query)
	clipboardChooser:choices(buildChoices(query))
end)

-- 履歴を表示
bindWithHelp({ "cmd", "shift" }, "V", "クリップボード", "クリップボード履歴を開く", function()
	clipboardChooser:choices(buildChoices(""))
	clipboardChooser:show()
end)

-- =============================================================================
-- Cmd + Q 長押し終了保護
-- =============================================================================
local HoldToQuit = require("modules.hold_to_quit")
local holdToQuitDuration = 0.8
local holdToQuit = HoldToQuit.new({ duration = holdToQuitDuration }):start()

-- ヘルプから選択しても終了せず、操作方法だけを表示する。
addHelpEntry({ "cmd" }, "Q", "アプリ終了", "0.8秒長押しでアプリを終了", function()
	hs.alert.show("終了するには⌘Qを0.8秒長押し")
end, { searchTerms = { "長押し", "誤操作防止", "HoldToQuit" } })

-- Alt + H自体を忘れても開けるよう、メニューバーにも入口を置く。
bindWithHelp({ "alt" }, "H", "ヘルプ", "Hammerspoonショートカット一覧を開く", showHotkeyHelp, {
	searchTerms = { "ヘルプ", "一覧", "検索" },
})

-- =============================================================================
-- アプリショートカットと統合パレット
-- =============================================================================
local AppShortcuts = require("modules.app_shortcuts")
local CommandPalette = require("modules.command_palette")
local GitHubRepos = require("modules.github_repos")

local githubRepos = GitHubRepos.new({
	ghPath = "/opt/homebrew/bin/gh",
	cacheSeconds = 300,
	openURL = function(url)
		openURLInChrome(url)
	end,
})

bindWithHelp({ "ctrl", "alt" }, "G", "GitHub", "GitHubリポジトリを検索", function()
	githubRepos:show()
end, { searchTerms = { "repository", "repo", "リポジトリ", "GitHub検索" } })

local appShortcutManager = AppShortcuts.new({
	settingsKey = "appShortcutBindingsV1",
	initializedKey = "appShortcutBindingsV1Initialized",
	reservedKeys = {
		p = "Hammerspoon Palette",
		w = "ウィンドウ検索",
		l = "URLランチャー",
		h = "ショートカット一覧",
	},
	showHelp = showHotkeyHelp,
})

local commandPalette = CommandPalette.new({
	appShortcuts = appShortcutManager,
	showWindowSwitcher = showWindowSwitcher,
	showURLLauncher = showURLLauncher,
	showGitHubRepos = function()
		githubRepos:show()
	end,
})

appShortcutManager:setPaletteCallback(function(currentApp)
	commandPalette:show(currentApp)
end)

bindWithHelp({ "alt" }, "P", "パレット", "Hammerspoon Paletteを開く", function()
	-- chooserを開く前に、現在前面にいるアプリを退避する。
	local currentApp = appShortcutManager:captureFrontmostApp()
	commandPalette:show(currentApp)
end, { searchTerms = { "アプリ登録", "ウィンドウ", "URL", "管理" } })

appShortcutManager:start()

hs.shutdownCallback = function()
	stopCapsomniaCheck()
	holdToQuit:stop()
	chromeTabs:stop()
	githubRepos:stop()
end
