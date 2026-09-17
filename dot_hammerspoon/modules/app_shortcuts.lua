local AppShortcuts = {}
AppShortcuts.__index = AppShortcuts

local DEFAULT_BINDINGS = {
	{ key = "g", name = "Google Chrome" },
	{ key = "t", name = "WezTerm" },
	{ key = "s", name = "Slack" },
	{ key = "o", name = "Obsidian" },
	{ key = "f", name = "Finder" },
	{ key = "d", name = "Discord" },
	{ key = "i", name = "Visual Studio Code" },
	{ key = "b", name = "DBeaver" },
	{ key = "c", name = "Claude" },
	{ key = "a", name = "Codex" },
	{ key = "z", name = "zoom.us" },
	{ key = "u", name = "Orca" },
	{ key = "k", name = "Amical" },
}

local function trimmedString(value)
	if type(value) ~= "string" then
		return nil
	end
	local trimmed = value:match("^%s*(.-)%s*$")
	return trimmed ~= "" and trimmed or nil
end

local function sortedKeys(bindings)
	local keys = {}
	for key in pairs(bindings) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function copyBinding(binding)
	return {
		name = binding.name,
		bundleID = binding.bundleID,
		savedAt = binding.savedAt,
	}
end

local function shellQuote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

function AppShortcuts.new(options)
	local self = setmetatable({}, AppShortcuts)
	self.settingsKey = options.settingsKey or "appShortcutBindingsV1"
	self.initializedKey = options.initializedKey or "appShortcutBindingsV1Initialized"
	self.reservedKeys = options.reservedKeys or {}
	self.showHelp = options.showHelp
	self.paletteCallback = nil
	self.activeHotkeys = {}
	self.keyChooser = nil
	self.runningAppsChooser = nil
	self.managerChooser = nil
	self.contextMenu = hs.menubar.new(false)
	self.menubar = nil
	return self
end

function AppShortcuts:isReserved(key)
	return self.reservedKeys[tostring(key):lower()] ~= nil
end

function AppShortcuts:sanitizeBindings(value)
	if type(value) ~= "table" then
		return {}
	end

	local bindings = {}
	for rawKey, rawBinding in pairs(value) do
		local key = type(rawKey) == "string" and rawKey:lower() or ""
		if key:match("^[a-z]$") and not self:isReserved(key) and type(rawBinding) == "table" then
			local name = trimmedString(rawBinding.name)
			local bundleID = trimmedString(rawBinding.bundleID)
			if name or bundleID then
				bindings[key] = {
					name = name,
					bundleID = bundleID,
					savedAt = type(rawBinding.savedAt) == "number" and rawBinding.savedAt or nil,
				}
			end
		end
	end
	return bindings
end

function AppShortcuts:loadBindings()
	local succeeded, stored = pcall(hs.settings.get, self.settingsKey)
	if not succeeded then
		return {}
	end
	return self:sanitizeBindings(stored)
end

function AppShortcuts:saveBindings(bindings)
	local sanitized = self:sanitizeBindings(bindings)
	local succeeded, result = pcall(hs.settings.set, self.settingsKey, sanitized)
	if not succeeded or result == false then
		hs.alert.show("アプリショートカットを保存できませんでした")
		return false
	end
	return true
end

function AppShortcuts:appInfoFromApplication(application)
	if not application then
		return nil
	end

	local nameSucceeded, name = pcall(function()
		return application:name()
	end)
	local bundleSucceeded, bundleID = pcall(function()
		return application:bundleID()
	end)
	name = nameSucceeded and trimmedString(name) or nil
	bundleID = bundleSucceeded and trimmedString(bundleID) or nil
	if name == "Hammerspoon" or bundleID == "org.hammerspoon.Hammerspoon" then
		return nil
	end
	if not name and not bundleID then
		return nil
	end
	return { name = name or bundleID, bundleID = bundleID }
end

function AppShortcuts:captureFrontmostApp()
	return self:appInfoFromApplication(hs.application.frontmostApplication())
end

function AppShortcuts:bindingLabel(binding)
	return binding.name or binding.bundleID or "不明なアプリ"
end

function AppShortcuts:applicationMatches(application, binding)
	local info = self:appInfoFromApplication(application)
	if not info then
		return false
	end
	if binding.bundleID and info.bundleID then
		return binding.bundleID == info.bundleID
	end
	return binding.name and info.name == binding.name
end

function AppShortcuts:moveMouseToFocusedWindow(binding, attempt)
	attempt = attempt or 1
	local frontmost = hs.application.frontmostApplication()
	if frontmost and self:applicationMatches(frontmost, binding) then
		local win = frontmost:focusedWindow() or frontmost:mainWindow()
		if win and win:isVisible() then
			local frame = win:frame()
			hs.mouse.absolutePosition({
				x = frame.x + frame.w / 2,
				y = frame.y + frame.h / 2,
			})
			return
		end
	end

	if attempt < 6 then
		hs.timer.doAfter(0.2, function()
			self:moveMouseToFocusedWindow(binding, attempt + 1)
		end)
	end
end

function AppShortcuts:launch(binding)
	if type(binding) ~= "table" then
		return false
	end

	local launched = false
	if binding.bundleID then
		local succeeded, result = pcall(hs.application.launchOrFocusByBundleID, binding.bundleID)
		launched = succeeded and result ~= false
	end
	if not launched and binding.name then
		local succeeded, result = pcall(hs.application.launchOrFocus, binding.name)
		launched = succeeded and result ~= false
	end
	if not launched then
		hs.alert.show(self:bindingLabel(binding) .. "を開けませんでした")
		return false
	end

	hs.timer.doAfter(0.15, function()
		self:moveMouseToFocusedWindow(binding, 1)
	end)
	return true
end

function AppShortcuts:rebuildHotkeys()
	for _, hotkey in ipairs(self.activeHotkeys) do
		pcall(function()
			hotkey:delete()
		end)
	end
	self.activeHotkeys = {}

	local bindings = self:loadBindings()
	for _, key in ipairs(sortedKeys(bindings)) do
		local keyForCallback = key
		local bindingForCallback = copyBinding(bindings[key])
		local succeeded, hotkey = pcall(hs.hotkey.bind, { "alt" }, keyForCallback, function()
			self:launch(bindingForCallback)
		end)
		if succeeded and hotkey then
			table.insert(self.activeHotkeys, hotkey)
		else
			print("Alt + " .. keyForCallback:upper() .. " の登録に失敗しました")
		end
	end
end

function AppShortcuts:bundleInfoForPath(path)
	if hs.fs.attributes(path, "mode") ~= "directory" then
		return nil
	end
	local succeeded, info = pcall(hs.application.infoForBundlePath, path)
	if not succeeded or type(info) ~= "table" then
		return nil
	end
	local bundleID = trimmedString(info.CFBundleIdentifier)
	if not bundleID then
		return nil
	end
	return bundleID
end

-- 初回移行時だけ、実在するアプリからbundle IDを取得する。
function AppShortcuts:resolveInstalledBundleID(name)
	local running = hs.application.find(name)
	local runningInfo = self:appInfoFromApplication(running)
	if runningInfo and runningInfo.name == name and runningInfo.bundleID then
		return runningInfo.bundleID
	end

	local home = os.getenv("HOME")
	local candidates = {
		"/Applications/" .. name .. ".app",
		home .. "/Applications/" .. name .. ".app",
		"/System/Applications/" .. name .. ".app",
		"/System/Library/CoreServices/" .. name .. ".app",
	}
	for _, path in ipairs(candidates) do
		local bundleID = self:bundleInfoForPath(path)
		if bundleID then
			return bundleID
		end
	end

	local output = hs.execute("/usr/bin/mdfind -name " .. shellQuote(name)) or ""
	for path in output:gmatch("[^\r\n]+") do
		if path:match("%.app$") then
			local bundleID = self:bundleInfoForPath(path)
			if bundleID then
				return bundleID
			end
		end
	end
	return nil
end

function AppShortcuts:migrateDefaultsOnce()
	local initializedSucceeded, initialized = pcall(hs.settings.get, self.initializedKey)
	if initializedSucceeded and initialized == true then
		return
	end

	local storedSucceeded, stored = pcall(hs.settings.get, self.settingsKey)
	if not storedSucceeded then
		return
	end

	if stored == nil then
		local bindings = {}
		for _, defaultBinding in ipairs(DEFAULT_BINDINGS) do
			bindings[defaultBinding.key] = {
				name = defaultBinding.name,
				bundleID = self:resolveInstalledBundleID(defaultBinding.name),
				savedAt = os.time(),
			}
		end
		if not self:saveBindings(bindings) then
			return
		end
	end

	local succeeded, result = pcall(hs.settings.set, self.initializedKey, true)
	if not succeeded or result == false then
		hs.alert.show("アプリショートカットの初期化状態を保存できませんでした")
	end
end

function AppShortcuts:list()
	local list = {}
	local bindings = self:loadBindings()
	for _, key in ipairs(sortedKeys(bindings)) do
		local item = copyBinding(bindings[key])
		item.key = key
		table.insert(list, item)
	end
	return list
end

function AppShortcuts:confirm(title, message, confirmTitle)
	local result = hs.dialog.blockAlert(title, message, confirmTitle, "キャンセル", "warning")
	return result == confirmTitle
end

function AppShortcuts:assignKey(appInfo, key, originalKey)
	key = tostring(key):lower()
	if not key:match("^[a-z]$") or self:isReserved(key) then
		hs.alert.show("Alt + " .. key:upper() .. " は使用できません")
		return false
	end

	local bindings = self:loadBindings()
	local existing = bindings[key]
	if existing and key ~= originalKey then
		local message = "Alt + "
			.. key:upper()
			.. " は「"
			.. self:bindingLabel(existing)
			.. "」に割り当て済みです。\n「"
			.. self:bindingLabel(appInfo)
			.. "」で上書きしますか？"
		if not self:confirm("ショートカットを上書きしますか？", message, "上書き") then
			return false
		end
	end

	if originalKey and originalKey ~= key then
		bindings[originalKey] = nil
	end
	bindings[key] = {
		name = trimmedString(appInfo.name),
		bundleID = trimmedString(appInfo.bundleID),
		savedAt = os.time(),
	}
	if not self:saveBindings(bindings) then
		return false
	end

	self:rebuildHotkeys()
	hs.alert.show("Alt + " .. key:upper() .. " に登録: " .. self:bindingLabel(appInfo))
	return true
end

function AppShortcuts:showKeyChooser(appInfo, originalKey, onChanged)
	if type(appInfo) ~= "table" or (not trimmedString(appInfo.name) and not trimmedString(appInfo.bundleID)) then
		hs.alert.show("登録するアプリを取得できませんでした")
		return
	end

	local bindings = self:loadBindings()
	local choices = {}
	for byte = string.byte("a"), string.byte("z") do
		local key = string.char(byte)
		local reservedReason = self.reservedKeys[key]
		local existing = bindings[key]
		local status = "未登録"
		local valid = true
		if reservedReason then
			status = "使用不可: " .. reservedReason
			valid = false
		elseif existing then
			status = "使用中: " .. self:bindingLabel(existing)
		end
		table.insert(choices, {
			text = "Alt + " .. key:upper() .. " — " .. status,
			subText = key == originalKey and "現在の割り当て" or "キーを選択",
			key = key,
			valid = valid,
		})
	end

	self.keyChooser = hs.chooser.new(function(choice)
		if not choice then
			self.keyChooser = nil
			return
		end
		if self:assignKey(appInfo, choice.key, originalKey) and onChanged then
			onChanged()
		end
		self.keyChooser = nil
	end)
	self.keyChooser:placeholderText(self:bindingLabel(appInfo) .. "に割り当てるキーを選択...")
	self.keyChooser:searchSubText(true)
	self.keyChooser:invalidCallback(function(choice)
		if choice and choice.key then
			hs.alert.show("Alt + " .. choice.key:upper() .. " は " .. self.reservedKeys[choice.key] .. " で使用中です")
		end
	end)
	self.keyChooser:choices(choices)
	self.keyChooser:show()
end

function AppShortcuts:showRegisterCurrent(appInfo)
	appInfo = appInfo or self:captureFrontmostApp()
	if not appInfo then
		hs.alert.show("Hammerspoon以外の登録したいアプリを前面に表示してください")
		return
	end
	self:showKeyChooser(appInfo)
end

function AppShortcuts:runningApplicationChoices()
	local choices = {}
	local seenBundleIDs = {}
	for _, application in ipairs(hs.application.runningApplications()) do
		local kindSucceeded, kind = pcall(function()
			return application:kind()
		end)
		local appInfo = self:appInfoFromApplication(application)
		if kindSucceeded and kind == 1 and appInfo then
			local identity = appInfo.bundleID or appInfo.name
			if not seenBundleIDs[identity] then
				seenBundleIDs[identity] = true
				table.insert(choices, {
					text = appInfo.name,
					subText = appInfo.bundleID or "bundle IDなし",
					appInfo = appInfo,
				})
			end
		end
	end
	table.sort(choices, function(left, right)
		return left.text:lower() < right.text:lower()
	end)
	return choices
end

function AppShortcuts:showRunningApps()
	local choices = self:runningApplicationChoices()
	if #choices == 0 then
		hs.alert.show("登録できる起動中アプリがありません")
		return
	end

	self.runningAppsChooser = hs.chooser.new(function(choice)
		if choice and choice.appInfo then
			self:showKeyChooser(choice.appInfo)
		end
		self.runningAppsChooser = nil
	end)
	self.runningAppsChooser:placeholderText("起動中のアプリを検索...")
	self.runningAppsChooser:searchSubText(true)
	self.runningAppsChooser:choices(choices)
	self.runningAppsChooser:show()
end

function AppShortcuts:managerChoices()
	local choices = {}
	for _, binding in ipairs(self:list()) do
		table.insert(choices, {
			text = "Alt + " .. binding.key:upper() .. " — " .. self:bindingLabel(binding),
			subText = binding.bundleID or "アプリ名で起動",
			binding = binding,
		})
	end
	return choices
end

function AppShortcuts:refreshManagerChoices()
	if self.managerChooser then
		self.managerChooser:choices(self:managerChoices())
	end
end

function AppShortcuts:removeBinding(key, binding)
	if not self:confirm(
		"登録を解除しますか？",
		"Alt + " .. key:upper() .. " の「" .. self:bindingLabel(binding) .. "」を解除します。",
		"登録解除"
	) then
		return false
	end

	local bindings = self:loadBindings()
	bindings[key] = nil
	if not self:saveBindings(bindings) then
		return false
	end
	self:rebuildHotkeys()
	hs.alert.show("Alt + " .. key:upper() .. " の登録を解除しました")
	return true
end

function AppShortcuts:showManager()
	local choices = self:managerChoices()
	if #choices == 0 then
		hs.alert.show("登録済みのアプリショートカットはありません")
		return
	end

	if not self.managerChooser then
		self.managerChooser = hs.chooser.new(function(choice)
			if choice and choice.binding then
				self:launch(choice.binding)
			end
		end)
		self.managerChooser:placeholderText("登録済みアプリショートカットを検索...")
		self.managerChooser:searchSubText(true)
		self.managerChooser:rightClickCallback(function(row)
			if row == 0 then
				return
			end
			local choice = self.managerChooser:selectedRowContents(row)
			if type(choice) ~= "table" or type(choice.binding) ~= "table" then
				return
			end
			local binding = choice.binding
			self.contextMenu:setMenu({
				{
					title = "アプリを開く",
					fn = function()
						self:launch(binding)
					end,
				},
				{
					title = "キーを変更…",
					fn = function()
						self.managerChooser:hide()
						hs.timer.doAfter(0.05, function()
							self:showKeyChooser(binding, binding.key, function()
								self:refreshManagerChoices()
								self.managerChooser:show()
							end)
						end)
					end,
				},
				{ title = "-" },
				{
					title = "登録を解除…",
					fn = function()
						if self:removeBinding(binding.key, binding) then
							self:refreshManagerChoices()
							if #self:managerChoices() == 0 then
								self.managerChooser:hide()
							end
						end
					end,
				},
			})
			self.contextMenu:popupMenu(hs.mouse.absolutePosition())
		end)
	end

	self.managerChooser:query("")
	self.managerChooser:choices(choices)
	self.managerChooser:show()
end

function AppShortcuts:setPaletteCallback(callback)
	self.paletteCallback = callback
end

function AppShortcuts:buildMenubarMenu()
	local currentApp = self:captureFrontmostApp()
	local menu = {
		{
			title = currentApp and ("現在のアプリを登録… (" .. self:bindingLabel(currentApp) .. ")")
				or "現在のアプリを登録…",
			disabled = currentApp == nil,
			fn = function()
				self:showRegisterCurrent(currentApp)
			end,
		},
		{
			title = "起動中のアプリから登録…",
			fn = function()
				self:showRunningApps()
			end,
		},
		{
			title = "ショートカットを管理…",
			fn = function()
				self:showManager()
			end,
		},
		{ title = "-" },
	}

	for _, binding in ipairs(self:list()) do
		local bindingForCallback = copyBinding(binding)
		table.insert(menu, {
			title = "Alt + " .. binding.key:upper() .. " — " .. self:bindingLabel(binding),
			fn = function()
				self:launch(bindingForCallback)
			end,
		})
	end

	table.insert(menu, { title = "-" })
	table.insert(menu, {
		title = "Hammerspoon Paletteを開く",
		fn = function()
			if self.paletteCallback then
				self.paletteCallback(currentApp)
			end
		end,
	})
	if self.showHelp then
		table.insert(menu, {
			title = "Hammerspoonショートカット一覧",
			fn = self.showHelp,
		})
	end
	table.insert(menu, {
		title = "Hammerspoon設定を再読み込み",
		fn = hs.reload,
	})
	return menu
end

function AppShortcuts:start()
	self:migrateDefaultsOnce()
	self:rebuildHotkeys()
	self.menubar = hs.menubar.new()
	self.menubar:setTitle("⌨︎")
	self.menubar:setTooltip("Hammerspoonアプリショートカット")
	self.menubar:setMenu(function()
		return self:buildMenubarMenu()
	end)
end

return AppShortcuts
