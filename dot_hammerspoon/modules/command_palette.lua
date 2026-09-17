local CommandPalette = {}
CommandPalette.__index = CommandPalette

function CommandPalette.new(options)
	local self = setmetatable({}, CommandPalette)
	self.appShortcuts = options.appShortcuts
	self.showWindowSwitcher = options.showWindowSwitcher
	self.showURLLauncher = options.showURLLauncher
	self.currentApp = nil
	self.chooser = hs.chooser.new(function(choice)
		if not choice then
			return
		end
		if choice.actionID == "registerCurrent" then
			self.appShortcuts:showRegisterCurrent(self.currentApp)
		elseif choice.actionID == "registerRunning" then
			self.appShortcuts:showRunningApps()
		elseif choice.actionID == "manage" then
			self.appShortcuts:showManager()
		elseif choice.actionID == "windowSwitcher" then
			self.showWindowSwitcher()
		elseif choice.actionID == "urlLauncher" then
			self.showURLLauncher()
		elseif choice.actionID == "launch" and choice.key then
			local binding = self.appShortcuts:loadBindings()[choice.key]
			if binding then
				self.appShortcuts:launch(binding)
			end
		end
	end)
	self.chooser:placeholderText("Hammerspoon Paletteを検索...")
	self.chooser:searchSubText(true)
	return self
end

function CommandPalette:buildChoices(currentApp)
	local choices = {
		{
			text = "現在のアプリをショートカットに登録",
			subText = currentApp and self.appShortcuts:bindingLabel(currentApp)
				or "Hammerspoon以外のアプリを前面に表示してください",
			actionID = "registerCurrent",
		},
		{
			text = "起動中のアプリから選んで登録",
			subText = "通常のGUIアプリを検索",
			actionID = "registerRunning",
		},
		{
			text = "登録済みアプリショートカットを管理",
			subText = "開く・キー変更・登録解除",
			actionID = "manage",
		},
		{
			text = "ウィンドウを検索",
			subText = "Alt + W",
			actionID = "windowSwitcher",
		},
		{
			text = "URLを検索",
			subText = "Alt + L",
			actionID = "urlLauncher",
		},
		{
			text = "登録済みアプリの一覧",
			subText = "下の項目を選ぶとアプリを開きます",
			valid = false,
		},
	}

	for _, binding in ipairs(self.appShortcuts:list()) do
		table.insert(choices, {
			text = "Alt + " .. binding.key:upper() .. " — " .. self.appShortcuts:bindingLabel(binding),
			subText = binding.bundleID or "アプリ名で起動",
			actionID = "launch",
			key = binding.key,
		})
	end
	return choices
end

function CommandPalette:show(currentApp)
	self.currentApp = currentApp
	self.chooser:query("")
	self.chooser:choices(self:buildChoices(currentApp))
	self.chooser:show()
end

return CommandPalette
