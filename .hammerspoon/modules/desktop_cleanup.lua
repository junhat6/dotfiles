local DesktopCleanup = {}
DesktopCleanup.__index = DesktopCleanup

-- Dockに表示される常駐ツールも、ウィンドウの有無にかかわらず保護する。
local protectedBundleIDs = {
	["com.apple.finder"] = true,
	["org.hammerspoon.Hammerspoon"] = true,
	["ai.amical.desktop"] = true,
	["com.docker.docker"] = true,
	["dev.kdrag0n.OrbStack"] = true,
	["com.github.fuji-mak.capsomnia"] = true,
}

function DesktopCleanup.new(appShortcuts)
	return setmetatable({ appShortcuts = appShortcuts }, DesktopCleanup)
end

function DesktopCleanup:isProtected(app, bindings)
	if app:kind() ~= 1 or protectedBundleIDs[app:bundleID()] then
		return true
	end
	local name = (app:name() or ""):lower()
	if name:find("colima", 1, true) then
		return true
	end
	for _, binding in pairs(bindings) do
		if self.appShortcuts:applicationMatches(app, binding) then
			return true
		end
	end
	return false
end

function DesktopCleanup:candidates()
	local currentSpace = hs.spaces.focusedSpace()
	local currentWindowIDs = currentSpace and hs.spaces.windowsForSpace(currentSpace)
	local windowData = hs.window.list(true)
	if not currentWindowIDs or type(windowData) ~= "table" then
		return nil, "現在のデスクトップを取得できませんでした"
	end
	local bindings = self.appShortcuts:loadBindings()
	-- 設定の読み取り失敗などで登録アプリまで終了しないよう、空なら停止する。
	if next(bindings) == nil then
		return nil, "保護する登録済みアプリがありません。アプリ登録を確認してください"
	end

	local currentIDs = {}
	for _, id in ipairs(currentWindowIDs) do currentIDs[id] = true end
	local candidates, blockedPIDs = {}, {}
	for _, win in ipairs(hs.window.allWindows()) do
		local app = win:application()
		if currentIDs[win:id()] and app and win:isStandard() and win:isVisible() and not self:isProtected(app, bindings) then
			candidates[app:pid()] = app
		end
	end

	-- Accessibilityで見えない別SpaceのウィンドウもCGWindowListから調べる。
	-- 通常終了はアプリ全体に及ぶので、別Spaceにもある場合は終了しない。
	for _, data in ipairs(windowData) do
		local pid = data.kCGWindowOwnerPID
		if candidates[pid] and data.kCGWindowLayer == 0 then
			local spaces = hs.spaces.windowSpaces(data.kCGWindowNumber)
			if not spaces or #spaces == 0 then
				blockedPIDs[pid] = true
			else
				for _, space in ipairs(spaces) do
					if space ~= currentSpace then
						blockedPIDs[pid] = true
					end
				end
			end
		end
	end

	local result = {}
	for pid, app in pairs(candidates) do
		if not blockedPIDs[pid] then
			table.insert(result, app)
		end
	end
	table.sort(result, function(a, b) return a:name() < b:name() end)
	return result
end

function DesktopCleanup:quit()
	local apps, errorMessage = self:candidates()
	if not apps then
		hs.alert.show(errorMessage)
		return
	end
	if #apps == 0 then
		hs.alert.show("終了対象のアプリはありません")
		return
	end
	local requested, failed = {}, {}
	for _, app in ipairs(apps) do
		local name = app:name()
		-- kill()はNSRunningApplicationのterminate（通常終了）。強制終了しない。
		local succeeded = pcall(function() app:kill() end)
		table.insert(succeeded and requested or failed, name)
	end
	if #requested > 0 then
		hs.alert.show("通常終了を要求: " .. table.concat(requested, "、"))
	end
	if #failed > 0 then
		hs.alert.show("終了を要求できませんでした: " .. table.concat(failed, "、"))
	end
end

return DesktopCleanup
