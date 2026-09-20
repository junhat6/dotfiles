local HoldToQuit = {}
HoldToQuit.__index = HoldToQuit

local DEFAULT_EXCLUDED_BUNDLE_IDS = {
	["com.apple.finder"] = true,
}

local function copySet(source)
	local result = {}
	for key, value in pairs(source or {}) do
		result[key] = value
	end
	return result
end

local function exactCommandOnly(modifiers)
	return modifiers.cmd == true
		and not modifiers.alt
		and not modifiers.ctrl
		and not modifiers.shift
		and not modifiers.fn
end

function HoldToQuit.new(options)
	options = options or {}
	local self = setmetatable({}, HoldToQuit)
	self.duration = options.duration or 1
	self.quitAction = options.quitAction or function(application)
		application:kill()
	end
	self.excludedBundleIDs = copySet(DEFAULT_EXCLUDED_BUNDLE_IDS)
	for bundleID, excluded in pairs(options.excludedBundleIDs or {}) do
		self.excludedBundleIDs[bundleID] = excluded
	end
	self.hotkey = nil
	self.eventTap = nil
	self.appWatcher = nil
	self.timer = nil
	self.hold = nil
	return self
end

function HoldToQuit:_stopTimer()
	if self.timer then
		self.timer:stop()
		self.timer = nil
	end
end

function HoldToQuit:_cancel(showHint)
	local hold = self.hold
	if not hold then
		return
	end
	self.hold = nil
	self:_stopTimer()
	if showHint and not hold.completed and not hold.excluded then
		hs.alert.show("終了するには⌘Qを長押し")
	end
end

function HoldToQuit:_sameFrontmostApplication(hold)
	local current = hs.application.frontmostApplication()
	return current and current:pid() == hold.pid
end

function HoldToQuit:_completeHold()
	local hold = self.hold
	if not hold or hold.completed or hold.excluded then
		return
	end
	if not exactCommandOnly(hs.eventtap.checkKeyboardModifiers()) or not self:_sameFrontmostApplication(hold) then
		self:_cancel(false)
		return
	end

	hold.completed = true
	self:_stopTimer()
	local succeeded, errorMessage = pcall(self.quitAction, hold.application)
	if not succeeded then
		print("アプリの終了要求に失敗: " .. tostring(errorMessage))
		hs.alert.show("アプリに終了を要求できませんでした")
	end
end

function HoldToQuit:_pressed()
	if self.hold then
		return
	end
	if not exactCommandOnly(hs.eventtap.checkKeyboardModifiers()) then
		return
	end

	local application = hs.application.frontmostApplication()
	if not application then
		return
	end
	local bundleID = application:bundleID()
	local excluded = bundleID and self.excludedBundleIDs[bundleID] == true
	self.hold = {
		application = application,
		pid = application:pid(),
		bundleID = bundleID,
		excluded = excluded,
		completed = false,
	}
	if excluded then
		return
	end

	self.timer = hs.timer.doAfter(self.duration, function()
		self:_completeHold()
	end)
end

function HoldToQuit:_released()
	self:_cancel(true)
end

function HoldToQuit:start()
	if self.hotkey then
		return self
	end

	self.hotkey = hs.hotkey.bind({ "cmd" }, "q", function()
		self:_pressed()
	end, function()
		self:_released()
	end, function()
		-- キーリピートではタイマーを作り直さない。
	end)

	self.eventTap = hs.eventtap.new({ hs.eventtap.event.types.keyUp, hs.eventtap.event.types.flagsChanged }, function(event)
		if not self.hold then
			return false
		end
		if event:getType() == hs.eventtap.event.types.keyUp and event:getKeyCode() == hs.keycodes.map.q then
			self:_cancel(true)
		elseif event:getType() == hs.eventtap.event.types.flagsChanged then
			local modifiers = event:getFlags()
			if not exactCommandOnly(modifiers) then
				self:_cancel(true)
			end
		end
		return false
	end)
	self.eventTap:start()

	self.appWatcher = hs.application.watcher.new(function(_, eventType)
		if self.hold and eventType == hs.application.watcher.activated and not self:_sameFrontmostApplication(self.hold) then
			self:_cancel(false)
		end
	end)
	self.appWatcher:start()
	return self
end

function HoldToQuit:stop()
	self:_cancel(false)
	if self.hotkey then
		self.hotkey:delete()
		self.hotkey = nil
	end
	if self.eventTap then
		self.eventTap:stop()
		self.eventTap = nil
	end
	if self.appWatcher then
		self.appWatcher:stop()
		self.appWatcher = nil
	end
	return self
end

return HoldToQuit
