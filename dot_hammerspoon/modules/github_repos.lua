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

local function decodeRepositoryLines(output)
	local repositories = {}
	for line in tostring(output):gmatch("[^\r\n]+") do
		local succeeded, repository = pcall(hs.json.decode, line)
		if succeeded and type(repository) == "table" then
			table.insert(repositories, repository)
		end
	end
	return repositories
end

function GitHubRepos.new(options)
	local self = setmetatable({}, GitHubRepos)
	self.ghPath = options.ghPath or "/opt/homebrew/bin/gh"
	self.openURL = options.openURL or hs.urlevent.openURL
	self.cacheSeconds = options.cacheSeconds or 300
	self.cachedChoices = nil
	self.cacheUpdatedAt = nil
	self.task = nil
	self.requestID = 0

	self.chooser = hs.chooser.new(function(choice)
		if choice and choice.url then
			self.openURL(choice.url)
		end
	end)
	self.chooser:placeholderText("GitHubリポジトリを検索...")
	self.chooser:searchSubText(true)
	return self
end

function GitHubRepos:cacheIsFresh()
	return self.cachedChoices
		and self.cacheUpdatedAt
		and os.difftime(os.time(), self.cacheUpdatedAt) < self.cacheSeconds
end

function GitHubRepos:setStatus(text, subText)
	self.chooser:choices({
		{
			text = text,
			subText = subText,
			valid = false,
		},
	})
end

function GitHubRepos:refresh()
	if self.task then
		return
	end

	self.requestID = self.requestID + 1
	local requestID = self.requestID
	self.task = hs.task.new(self.ghPath, function(exitCode, stdOut, stdErr)
		self.task = nil
		if requestID ~= self.requestID then
			return
		end

		if exitCode ~= 0 then
			if not self.cachedChoices or #self.cachedChoices == 0 then
				self:setStatus("リポジトリを取得できませんでした", trimmedString(stdErr) or "gh auth statusを確認してください")
			end
			return
		end

		local repositories = decodeRepositoryLines(stdOut)
		if #repositories == 0 then
			if not self.cachedChoices or #self.cachedChoices == 0 then
				self:setStatus("リポジトリ一覧を読み取れませんでした", "GitHub CLIの出力を確認してください")
			end
			return
		end

		local choices = repositoryChoices(repositories)
		self.cachedChoices = choices
		self.cacheUpdatedAt = os.time()
		if #choices == 0 then
			self:setStatus("リポジトリが見つかりませんでした", "ログイン中のGitHubアカウントを確認してください")
		else
			self.chooser:choices(choices)
		end
	end, {
		-- ログイン中のユーザーが所有・共同編集・Organization所属によってアクセスできる
		-- GitHub上のリポジトリを、ローカルへのclone有無に関係なくすべて検索対象にする。
		"api",
		"--paginate",
		"--cache",
		"5m",
		"user/repos?affiliation=owner,collaborator,organization_member&sort=updated&per_page=100",
		-- 大量のAPIレスポンスでhs.taskが待機しないよう、Chooserに必要な項目だけを出力する。
		"--jq",
		'.[] | {nameWithOwner: .full_name, description, isPrivate: .private, isArchived: .archived, updatedAt: .updated_at} | @json',
	})

	if not self.task then
		self:setStatus("GitHub CLIを起動できませんでした", self.ghPath)
		return
	end
	if not self.task:start() then
		self.task = nil
		self:setStatus("GitHub CLIを起動できませんでした", self.ghPath)
	end
end

function GitHubRepos:show()
	self.chooser:query("")
	if self.cachedChoices and #self.cachedChoices > 0 then
		self.chooser:choices(self.cachedChoices)
	else
		self:setStatus("GitHubリポジトリを取得中...", "取得後、この一覧が自動で更新されます")
	end
	self.chooser:show()

	if not self:cacheIsFresh() then
		self:refresh()
	end
end

function GitHubRepos:stop()
	self.requestID = self.requestID + 1
	self.chooser:hide()
	if self.task then
		self.task:terminate()
		self.task = nil
	end
end

return GitHubRepos
