local ChromeTabs = {}
ChromeTabs.__index = ChromeTabs

local APPLESCRIPT = [[
on replaceText(findText, replacementText, sourceText)
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to findText
	set textItems to every text item of sourceText
	set AppleScript's text item delimiters to replacementText
	set replacedText to textItems as text
	set AppleScript's text item delimiters to previousDelimiters
	return replacedText
end replaceText

on escapeField(value)
	set escapedValue to value as text
	set escapedValue to my replaceText("\\", "\\\\", escapedValue)
	set escapedValue to my replaceText(tab, "\\t", escapedValue)
	set escapedValue to my replaceText(return, "\\r", escapedValue)
	set escapedValue to my replaceText(linefeed, "\\n", escapedValue)
	return escapedValue
end escapeField

on joinFields(fields)
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to tab
	set joinedFields to fields as text
	set AppleScript's text item delimiters to previousDelimiters
	return joinedFields
end joinFields

on listTabs()
	set outputLines to {}
	tell application id "com.google.Chrome"
		repeat with windowIndex from 1 to (count of windows)
			set chromeWindow to window windowIndex
			if mode of chromeWindow is "normal" then
				set windowID to id of chromeWindow as text
				set windowName to name of chromeWindow as text
				set activeTabID to id of active tab of chromeWindow as text
				set end of outputLines to my joinFields({"W", my escapeField(windowID), windowIndex as text, my escapeField(activeTabID), my escapeField(windowName)})
				repeat with tabIndex from 1 to (count of tabs of chromeWindow)
					set chromeTab to tab tabIndex of chromeWindow
					set tabID to id of chromeTab as text
					set tabTitle to title of chromeTab as text
					set tabURL to URL of chromeTab as text
					set isActive to "0"
					if tabID is activeTabID then set isActive to "1"
					set end of outputLines to my joinFields({"T", my escapeField(windowID), my escapeField(tabID), tabIndex as text, isActive, my escapeField(tabTitle), my escapeField(tabURL)})
				end repeat
			end if
		end repeat
	end tell

	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to linefeed
	set outputText to outputLines as text
	set AppleScript's text item delimiters to previousDelimiters
	return outputText
end listTabs

on focusTab(expectedWindowID, expectedTabID, expectedURL)
	tell application id "com.google.Chrome"
		-- まず選択時のウィンドウを確認する。タブ移動後は同じタブIDを全ウィンドウから探す。
		repeat with chromeWindow in windows
			if mode of chromeWindow is "normal" and (id of chromeWindow as text) is expectedWindowID then
				repeat with tabIndex from 1 to (count of tabs of chromeWindow)
					set chromeTab to tab tabIndex of chromeWindow
					if (id of chromeTab as text) is expectedTabID then
						if (URL of chromeTab as text) is not expectedURL then return "URL_CHANGED"
						set active tab index of chromeWindow to tabIndex
						set index of chromeWindow to 1
						activate
						return "OK"
					end if
				end repeat
			end if
		end repeat
		repeat with chromeWindow in windows
			if mode of chromeWindow is "normal" and (id of chromeWindow as text) is not expectedWindowID then
				repeat with tabIndex from 1 to (count of tabs of chromeWindow)
					set chromeTab to tab tabIndex of chromeWindow
					if (id of chromeTab as text) is expectedTabID then
						if (URL of chromeTab as text) is not expectedURL then return "URL_CHANGED"
						set active tab index of chromeWindow to tabIndex
						set index of chromeWindow to 1
						activate
						return "OK"
					end if
				end repeat
			end if
		end repeat
	end tell
	return "NOT_FOUND"
end focusTab

on openNewTab(targetURL, preferredWindowID)
	tell application id "com.google.Chrome"
		set targetWindow to missing value
		if preferredWindowID is not "" then
			repeat with chromeWindow in windows
				if mode of chromeWindow is "normal" and (id of chromeWindow as text) is preferredWindowID then
					set targetWindow to chromeWindow
					exit repeat
				end if
			end repeat
		end if

		if targetWindow is missing value then
			repeat with chromeWindow in windows
				if mode of chromeWindow is "normal" then
					set targetWindow to chromeWindow
					exit repeat
				end if
			end repeat
		end if

		if targetWindow is missing value then
			set targetWindow to make new window with properties {mode:"normal"}
			set URL of active tab of targetWindow to targetURL
		else
			tell targetWindow
				make new tab at end of tabs with properties {URL:targetURL}
				set active tab index to count of tabs
			end tell
		end if
		set index of targetWindow to 1
		activate
	end tell
	return "OK"
end openNewTab

on currentTab()
	tell application id "com.google.Chrome"
		if (count of windows) is 0 then return "NO_WINDOW"
		set chromeWindow to front window
		if mode of chromeWindow is not "normal" then return "INCOGNITO"
		set chromeTab to active tab of chromeWindow
		return my joinFields({"C", my escapeField(id of chromeWindow as text), my escapeField(id of chromeTab as text), my escapeField(title of chromeTab as text), my escapeField(URL of chromeTab as text)})
	end tell
end currentTab

on run argv
	set operation to item 1 of argv
	if operation is "list" then
		return my listTabs()
	else if operation is "focus" then
		return my focusTab(item 2 of argv, item 3 of argv, item 4 of argv)
	else if operation is "new" then
		return my openNewTab(item 2 of argv, item 3 of argv)
	else if operation is "current" then
		return my currentTab()
	end if
	error "Unknown operation"
end run
]]

local function decodeField(value)
	return (value:gsub("\\([\\tnr])", function(escaped)
		if escaped == "t" then
			return "\t"
		elseif escaped == "n" then
			return "\n"
		elseif escaped == "r" then
			return "\r"
		end
		return "\\"
	end))
end

local function splitFields(line)
	local fields = {}
	for field in (line .. "\t"):gmatch("(.-)\t") do
		table.insert(fields, decodeField(field))
	end
	return fields
end

local function trimOutput(output)
	return (output or ""):gsub("[%s\r\n]+$", "")
end

local function windowLabel(tab)
	local name = tab.windowName ~= "" and tab.windowName or "Chromeウィンドウ"
	return name .. " (ID " .. tab.windowID .. ")"
end

function ChromeTabs.new(options)
	options = options or {}
	local self = setmetatable({}, ChromeTabs)
	self.bundleID = options.bundleID or "com.google.Chrome"
	self.timeoutSeconds = options.timeoutSeconds or 5
	self.tasks = {}
	self.matchChooser = nil
	return self
end

function ChromeTabs:isRunning()
	local applications = hs.application.applicationsForBundleID(self.bundleID)
	return type(applications) == "table" and #applications > 0
end

function ChromeTabs:_run(arguments, callback)
	local finished = false
	local task
	local timeoutTimer

	local function finish(result, errorMessage)
		if finished then
			return
		end
		finished = true
		if timeoutTimer then
			timeoutTimer:stop()
			timeoutTimer = nil
		end
		if task then
			self.tasks[task] = nil
		end
		callback(result, errorMessage)
	end

	local taskArguments = { "-e", APPLESCRIPT, "--" }
	for _, argument in ipairs(arguments) do
		table.insert(taskArguments, tostring(argument))
	end

	task = hs.task.new("/usr/bin/osascript", function(exitCode, standardOutput, standardError)
		if exitCode == 0 then
			finish(trimOutput(standardOutput), nil)
		else
			local detail = trimOutput(standardError)
			finish(nil, detail ~= "" and detail or "AppleScriptの実行に失敗しました")
		end
	end, taskArguments)

	if not task then
		finish(nil, "AppleScriptタスクを作成できませんでした")
		return
	end

	self.tasks[task] = true
	timeoutTimer = hs.timer.doAfter(self.timeoutSeconds, function()
		pcall(function()
			task:terminate()
		end)
		finish(nil, "Chromeの応答がタイムアウトしました")
	end)

	if not task:start() then
		finish(nil, "AppleScriptタスクを開始できませんでした")
	end
end

function ChromeTabs:_parseTabs(output)
	local snapshot = {
		running = true,
		windows = {},
		tabs = {},
		preferredWindowID = nil,
	}
	local windowsByID = {}

	for line in (output .. "\n"):gmatch("([^\n]*)\n") do
		if line ~= "" then
			local fields = splitFields(line)
			if fields[1] == "W" and fields[2] and fields[3] and fields[4] and fields[5] then
				local window = {
					id = fields[2],
					index = tonumber(fields[3]),
					activeTabID = fields[4],
					name = fields[5],
				}
				windowsByID[window.id] = window
				table.insert(snapshot.windows, window)
			elseif fields[1] == "T" and fields[2] and fields[3] and fields[4] and fields[5] and fields[6] and fields[7] then
				table.insert(snapshot.tabs, {
					windowID = fields[2],
					tabID = fields[3],
					tabIndex = tonumber(fields[4]),
					active = fields[5] == "1",
					title = fields[6],
					url = fields[7],
				})
			end
		end
	end

	table.sort(snapshot.windows, function(left, right)
		return (left.index or math.huge) < (right.index or math.huge)
	end)
	if snapshot.windows[1] then
		snapshot.preferredWindowID = snapshot.windows[1].id
	end
	for _, tab in ipairs(snapshot.tabs) do
		local window = windowsByID[tab.windowID]
		tab.windowIndex = window and window.index or nil
		tab.windowName = window and window.name or ""
	end
	return snapshot
end

function ChromeTabs:listTabs(callback)
	if not self:isRunning() then
		callback({ running = false, windows = {}, tabs = {}, preferredWindowID = nil }, nil)
		return
	end

	self:_run({ "list" }, function(output, errorMessage)
		if errorMessage then
			callback(nil, errorMessage)
			return
		end
		local succeeded, snapshot = pcall(function()
			return self:_parseTabs(output)
		end)
		if not succeeded then
			callback(nil, "Chromeのタブ一覧を解釈できませんでした")
			return
		end
		callback(snapshot, nil)
	end)
end

function ChromeTabs:focusTab(tab, callback)
	if type(tab) ~= "table" or not tab.windowID or not tab.tabID or type(tab.url) ~= "string" then
		if callback then
			callback(false, "タブ情報が不正です")
		end
		return
	end

	self:_run({ "focus", tab.windowID, tab.tabID, tab.url }, function(output, errorMessage)
		local status = trimOutput(output)
		if errorMessage then
			if callback then
				callback(false, errorMessage)
			end
		elseif status == "OK" then
			if callback then
				callback(true, nil)
			end
		elseif status == "URL_CHANGED" then
			if callback then
				callback(false, "選択後にタブのURLが変わったため、切り替えを中止しました")
			end
		else
			if callback then
				callback(false, "選択したタブはすでに閉じられています")
			end
		end
	end)
end

function ChromeTabs:openNewTab(url, preferredWindowID, callback)
	self:_run({ "new", url, preferredWindowID or "" }, function(output, errorMessage)
		local succeeded = not errorMessage and trimOutput(output) == "OK"
		if callback then
			callback(succeeded, errorMessage or (succeeded and nil or "新しいタブを開けませんでした"))
		end
	end)
end

function ChromeTabs:_showOtherWindowMatches(url, matches, preferredWindowID)
	local choices = {}
	for _, tab in ipairs(matches) do
		table.insert(choices, {
			text = tab.title ~= "" and tab.title or tab.url,
			subText = "開いている — " .. windowLabel(tab) .. " — " .. tab.url,
			tab = tab,
		})
	end
	table.insert(choices, {
		text = "新しいタブで開く",
		subText = url,
		openNew = true,
	})

	self.matchChooser = hs.chooser.new(function(choice)
		if not choice then
			return
		end
		if choice.openNew then
			self:openNewTab(url, preferredWindowID, function(succeeded, errorMessage)
				if not succeeded then
					hs.alert.show(errorMessage)
				end
			end)
		elseif choice.tab then
			self:focusTab(choice.tab, function(succeeded, errorMessage)
				if not succeeded then
					hs.alert.show(errorMessage)
				end
			end)
		end
	end)
	self.matchChooser:placeholderText("開いている同じURLのタブを選択...")
	self.matchChooser:searchSubText(true)
	self.matchChooser:choices(choices)
	self.matchChooser:show()
end

function ChromeTabs:openURL(url, preferredWindowID)
	self:listTabs(function(snapshot, errorMessage)
		if errorMessage then
			hs.alert.show("Chromeのタブを確認できませんでした")
			print("Chromeタブ一覧の取得に失敗: " .. tostring(errorMessage))
			return
		end

		local preferredID = preferredWindowID or snapshot.preferredWindowID
		local preferredMatches = {}
		local otherMatches = {}
		for _, tab in ipairs(snapshot.tabs) do
			if tab.url == url then
				if tab.windowID == preferredID then
					table.insert(preferredMatches, tab)
				else
					table.insert(otherMatches, tab)
				end
			end
		end

		table.sort(preferredMatches, function(left, right)
			if left.active ~= right.active then
				return left.active
			end
			return (left.tabIndex or math.huge) < (right.tabIndex or math.huge)
		end)
		table.sort(otherMatches, function(left, right)
			if left.windowIndex ~= right.windowIndex then
				return (left.windowIndex or math.huge) < (right.windowIndex or math.huge)
			end
			if left.active ~= right.active then
				return left.active
			end
			return (left.tabIndex or math.huge) < (right.tabIndex or math.huge)
		end)

		if preferredMatches[1] then
			self:focusTab(preferredMatches[1], function(succeeded, focusError)
				if not succeeded then
					hs.alert.show(focusError)
				end
			end)
		elseif #otherMatches > 0 then
			self:_showOtherWindowMatches(url, otherMatches, preferredID)
		else
			self:openNewTab(url, preferredID, function(succeeded, openError)
				if not succeeded then
					hs.alert.show(openError)
				end
			end)
		end
	end)
end

function ChromeTabs:currentTab(callback)
	local frontmost = hs.application.frontmostApplication()
	if not frontmost or frontmost:bundleID() ~= self.bundleID then
		callback(nil, "Chromeで登録したいページを表示してから実行してください")
		return
	end

	self:_run({ "current" }, function(output, errorMessage)
		if errorMessage then
			callback(nil, "Chromeの現在のタブを取得できませんでした")
			return
		end
		local status = trimOutput(output)
		if status == "INCOGNITO" then
			callback(nil, "シークレットウィンドウのタブは登録できません")
			return
		elseif status == "NO_WINDOW" then
			callback(nil, "Chromeに登録できるタブがありません")
			return
		end
		local fields = splitFields(status)
		if fields[1] ~= "C" or not fields[2] or not fields[3] or not fields[4] or not fields[5] then
			callback(nil, "Chromeの現在のタブを取得できませんでした")
			return
		end
		callback({ windowID = fields[2], tabID = fields[3], title = fields[4], url = fields[5] }, nil)
	end)
end

function ChromeTabs:stop()
	for task in pairs(self.tasks) do
		pcall(function()
			task:terminate()
		end)
	end
	self.tasks = {}
	if self.matchChooser then
		self.matchChooser:delete()
		self.matchChooser = nil
	end
end

return ChromeTabs
