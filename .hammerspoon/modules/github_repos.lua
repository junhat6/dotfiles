local GitHubRepos = {}
GitHubRepos.__index = GitHubRepos

local function trimmedString(value)
	if type(value) ~= "string" then
		return nil
	end
	local trimmed = value:match("^%s*(.-)%s*$")
	return trimmed ~= "" and trimmed or nil
end

local function repositoryChoices(repositories)
	table.sort(repositories, function(left, right)
		return tostring(left.updatedAt or left.updated_at or "") > tostring(right.updatedAt or right.updated_at or "")
	end)

	local choices = {}
	for _, repository in ipairs(repositories) do
		local name = trimmedString(repository.nameWithOwner or repository.full_name)
		local url = trimmedString(repository.html_url or repository.url)
		if not url and name then
			url = "https://github.com/" .. name
		end
		if name and url then
			local isPrivate = repository.isPrivate
			if isPrivate == nil then
				isPrivate = repository.private
			end
			local attributes = { isPrivate and "Private" or "Public" }
			if repository.isArchived or repository.archived then
				table.insert(attributes, "Archived")
			end

			local description = trimmedString(repository.description)
			local subText = table.concat(attributes, " / ")
			if description then
				subText = subText .. " — " .. description
			end

			table.insert(choices, {
				text = name,
				subText = subText,
				url = url,
			})
		end
	end
	return choices
end

-- A malformed/partial response must never replace a usable cache.
local function decodeRepositoryLines(output)
	local repositories = {}
	for line in tostring(output or ""):gmatch("[^\r\n]+") do
		if line:match("%S") then
			local succeeded, repository = pcall(hs.json.decode, line)
			if not succeeded or type(repository) ~= "table"
				or not trimmedString(repository.nameWithOwner or repository.full_name) then
				return nil
			end
			table.insert(repositories, repository)
		end
	end
	return repositories
end

function GitHubRepos.new(options)
	local self = setmetatable({}, GitHubRepos)
	self.ghPath = options.ghPath or os.getenv("HOME") .. "/.local/share/mise/shims/gh"
	self.openURL = options.openURL or hs.urlevent.openURL
	self.cacheSeconds = options.cacheSeconds or 300
	self.timeoutSeconds = options.timeoutSeconds or 25
	self.maxVisibleChoices = options.maxVisibleChoices or 100
	self.cacheKey = options.cacheKey or "githubReposCacheV1"
	self.requestID = 0
	self.searchIndex = {}

	-- Keep the last successful list across config reloads, which other modules may trigger.
	local ok, stored = pcall(hs.settings.get, self.cacheKey)
	if ok and type(stored) == "table" and type(stored.repositories) == "table"
		and type(stored.updatedAt) == "number" then
		local valid = true
		for _, repo in ipairs(stored.repositories) do
			if type(repo) ~= "table" or not trimmedString(repo.nameWithOwner) then
				valid = false
				break
			end
		end
		if valid then
			self.cachedChoices = repositoryChoices(stored.repositories)
			self.cacheUpdatedAt = stored.updatedAt
			self:buildSearchIndex()
		end
	end

	self.chooser = hs.chooser.new(function(choice)
		if choice and choice.retry then
			self:show(true)
		elseif choice and choice.url then
			self.openURL(choice.url)
		end
	end)
	self.chooser:placeholderText("GitHubリポジトリを検索...")
	-- A query callback takes over filtering from hs.chooser. Status rows must remain
	-- visible even when the query does not contain their Japanese status text.
	self.chooser:queryChangedCallback(function(query)
		self:updateChoices(query)
	end)
	return self
end

function GitHubRepos:buildSearchIndex()
	self.searchIndex = {}
	for i, choice in ipairs(self.cachedChoices or {}) do
		self.searchIndex[i] = (choice.text .. " " .. choice.subText):lower()
	end
end

function GitHubRepos:cacheIsFresh()
	return self.cachedChoices ~= nil and self.cacheUpdatedAt
		and os.difftime(os.time(), self.cacheUpdatedAt) >= 0
		and os.difftime(os.time(), self.cacheUpdatedAt) < self.cacheSeconds
end

function GitHubRepos:updateChoices(query)
	query = query or self.chooser:query() or ""
	local words, choices, matched = {}, {}, 0
	for word in query:lower():gmatch("%S+") do
		table.insert(words, word)
	end
	for i, choice in ipairs(self.cachedChoices or {}) do
		local matches = true
		for _, word in ipairs(words) do
			if not self.searchIndex[i]:find(word, 1, true) then
				matches = false
				break
			end
		end
		if matches then
			matched = matched + 1
			if #choices < self.maxVisibleChoices then
				table.insert(choices, choice)
			end
		end
	end
	if matched == 0 and self.cachedChoices ~= nil then
		table.insert(choices, {
			text = #self.cachedChoices == 0 and "アクセス可能なリポジトリがありません" or "検索結果は0件です",
			subText = "取得済み " .. #self.cachedChoices .. "件 — キーワードを変更してください",
			valid = false,
		})
	elseif matched > self.maxVisibleChoices then
		table.insert(choices, {
			text = matched .. "件中 " .. self.maxVisibleChoices .. "件を表示",
			subText = "キーワードを追加すると、取得済みの全リポジトリから絞り込めます",
			valid = false,
		})
	end
	if self.loading then
		table.insert(choices, {
			text = self.cachedChoices and "GitHubの一覧を更新中..." or "GitHubリポジトリを取得中...",
			subText = "最大" .. self.timeoutSeconds .. "秒で結果を表示します。取得済みの一覧は検索できます",
			valid = false,
		})
	elseif self.errorMessage then
		table.insert(choices, {
			text = "取得に失敗しました — Enterで再試行",
			subText = self.errorMessage .. (self.cachedChoices and " — 保存済みの一覧を表示中" or ""),
			retry = true,
		})
	end
	if #choices == 0 then
		table.insert(choices, { text = "Enterでリポジトリを取得", retry = true })
	end
	self.chooser:choices(choices)
end

function GitHubRepos:finishRequest(errorMessage)
	self.task = nil
	self.loading = false
	if self.timeoutTimer then
		self.timeoutTimer:stop()
		self.timeoutTimer = nil
	end
	self.errorMessage = errorMessage
	if errorMessage then
		print("GitHubリポジトリ検索: " .. errorMessage)
	end
	self:updateChoices()
end

function GitHubRepos:refresh()
	if self.loading then
		return
	end
	self.requestID = self.requestID + 1
	local requestID = self.requestID
	self.loading = true
	self.errorMessage = nil
	self:updateChoices()
	local output, errors = {}, {}
	self.task = hs.task.new(self.ghPath, function(exitCode, stdOut, stdErr)
		-- A terminated task may complete after a retry has already started.
		if requestID ~= self.requestID then
			return
		end
		table.insert(output, stdOut or "")
		table.insert(errors, stdErr or "")
		if exitCode ~= 0 then
			local detail = trimmedString(table.concat(errors)) or "gh auth statusで認証状態を確認してください"
			self:finishRequest(detail:gsub("%s+", " "):sub(1, 240))
			return
		end
		local repositories = decodeRepositoryLines(table.concat(output))
		if not repositories then
			self:finishRequest("GitHub CLIの出力を読み取れませんでした")
			return
		end
		self.cachedChoices = repositoryChoices(repositories)
		self.cacheUpdatedAt = os.time()
		self:buildSearchIndex()
		local saved, result = pcall(hs.settings.set, self.cacheKey, {
			repositories = repositories,
			updatedAt = self.cacheUpdatedAt,
		})
		if not saved or result == false then
			print("GitHubリポジトリ検索: キャッシュを保存できませんでした")
		end
		self:finishRequest(nil)
	end, function(task, stdOut, stdErr)
		-- Drain both pipes while gh runs: waiting until exit can fill a pipe and
		-- deadlock large repository lists. Completion supplies only the unread tail.
		if task and requestID == self.requestID then
			table.insert(output, stdOut or "")
			table.insert(errors, stdErr or "")
		end
		return true
	end, {
		"api", "--paginate", "--cache", "5m",
		"user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=100",
		"--jq",
		'.[] | {nameWithOwner: .full_name, description, isPrivate: .private, isArchived: .archived, updatedAt: .updated_at} | @json',
	})
	if not self.task or not self.task:start() then
		self:finishRequest("GitHub CLIを起動できませんでした: " .. self.ghPath)
		return
	end
	self.timeoutTimer = hs.timer.doAfter(self.timeoutSeconds, function()
		if requestID ~= self.requestID then
			return
		end
		self.requestID = self.requestID + 1
		local task = self.task
		self:finishRequest("取得がタイムアウトしました。ネットワーク接続を確認してください")
		if task then
			task:terminate()
		end
	end)
end

function GitHubRepos:show(retry)
	if not retry then
		self.chooser:query("")
	end
	if retry or not self:cacheIsFresh() then
		self:refresh()
	else
		self:updateChoices()
	end
	self.chooser:show()
end

function GitHubRepos:stop()
	self.requestID = self.requestID + 1
	self.loading = false
	self.chooser:hide()
	if self.timeoutTimer then
		self.timeoutTimer:stop()
		self.timeoutTimer = nil
	end
	if self.task then
		self.task:terminate()
		self.task = nil
	end
end

return GitHubRepos
