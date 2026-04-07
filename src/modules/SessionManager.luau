--!strict
-- SessionManager: 장시간 게임 제작을 위한 세션/빌드 히스토리 관리
-- 대화가 끊기거나 컨텍스트가 압축되어도 빌드 상태를 복원할 수 있게 함

local SessionManager = {}

local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local ENGINE_FOLDER = "_RobloxEngine"
local SESSION_LOG = "_SessionLog"
local BUILD_MANIFEST = "_BuildManifest"
local DESIGN_DOC = "_DesignDoc"

--------------------------------------------------------------------------------
-- 내부 유틸리티
--------------------------------------------------------------------------------

local function getEngineFolder(): Folder
	local folder = ServerStorage:FindFirstChild(ENGINE_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ENGINE_FOLDER
		folder.Parent = ServerStorage
	end
	return folder
end

local function getOrCreateStringValue(parent: Instance, name: string): StringValue
	local obj = parent:FindFirstChild(name)
	if not obj then
		obj = Instance.new("StringValue")
		obj.Name = name
		obj.Value = ""
		obj.Parent = parent
	end
	return obj :: StringValue
end

local function decodeJSON(str: string): any
	if str == "" then return {} end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	if ok then return data end
	return {}
end

local function encodeJSON(data: any): string
	local ok, str = pcall(function()
		return HttpService:JSONEncode(data)
	end)
	if ok then return str end
	return "{}"
end

--------------------------------------------------------------------------------
-- 세션 로그: 모든 빌드 작업을 시간순으로 기록
--------------------------------------------------------------------------------

--- 작업 기록 추가
function SessionManager.logAction(action: string, details: string?)
	local folder = getEngineFolder()
	local logObj = getOrCreateStringValue(folder, SESSION_LOG)

	local log = decodeJSON(logObj.Value)
	if type(log) ~= "table" then log = {} end

	table.insert(log, {
		time = os.time(),
		timeStr = os.date("%Y-%m-%d %H:%M:%S"),
		action = action,
		details = details or "",
	})

	-- 최대 200개 로그 유지 (오래된 것 제거)
	while #log > 200 do
		table.remove(log, 1)
	end

	logObj.Value = encodeJSON(log)
end

--- 최근 N개 로그 출력
function SessionManager.getRecentLog(count: number?): string
	count = count or 20
	local folder = ServerStorage:FindFirstChild(ENGINE_FOLDER)
	if not folder then return "No session log found." end

	local logObj = folder:FindFirstChild(SESSION_LOG)
	if not logObj then return "No session log found." end

	local log = decodeJSON(logObj.Value)
	local lines = {"=== SESSION LOG (recent " .. count .. ") ==="}

	local start = math.max(1, #log - count + 1)
	for i = start, #log do
		local entry = log[i]
		table.insert(lines, string.format("[%s] %s%s",
			entry.timeStr or "?",
			entry.action or "?",
			entry.details and entry.details ~= "" and (" | " .. entry.details) or ""
		))
	end

	if #log == 0 then
		table.insert(lines, "  (empty)")
	end

	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- 빌드 매니페스트: 무엇이 만들어졌는지 구조적으로 추적
--------------------------------------------------------------------------------

--- 빌드 항목 등록 (방, NPC, 시스템 등)
function SessionManager.registerBuild(category: string, name: string, data: {[string]: any})
	local folder = getEngineFolder()
	local manifestObj = getOrCreateStringValue(folder, BUILD_MANIFEST)

	local manifest = decodeJSON(manifestObj.Value)
	if not manifest[category] then
		manifest[category] = {}
	end

	data._registeredAt = os.date("%Y-%m-%d %H:%M:%S")
	manifest[category][name] = data

	manifestObj.Value = encodeJSON(manifest)

	SessionManager.logAction("BUILD_REGISTERED", category .. "/" .. name)
end

--- 빌드 매니페스트 전체 조회
function SessionManager.getBuildManifest(): string
	local folder = ServerStorage:FindFirstChild(ENGINE_FOLDER)
	if not folder then return "No build manifest." end

	local manifestObj = folder:FindFirstChild(BUILD_MANIFEST)
	if not manifestObj then return "No build manifest." end

	local manifest = decodeJSON(manifestObj.Value)
	local lines = {"=== BUILD MANIFEST ==="}

	for category, items in manifest do
		table.insert(lines, "\n[" .. category .. "]")
		for name, data in items do
			local info = "  " .. name
			if data.position then
				info = info .. string.format(" @ (%.0f, %.0f, %.0f)",
					data.position[1] or 0, data.position[2] or 0, data.position[3] or 0)
			end
			if data.status then
				info = info .. " [" .. data.status .. "]"
			end
			if data.description then
				info = info .. " - " .. data.description
			end
			table.insert(lines, info)
		end
	end

	return table.concat(lines, "\n")
end

--- 특정 카테고리의 빌드 목록
function SessionManager.getBuilds(category: string): {[string]: any}
	local folder = ServerStorage:FindFirstChild(ENGINE_FOLDER)
	if not folder then return {} end

	local manifestObj = folder:FindFirstChild(BUILD_MANIFEST)
	if not manifestObj then return {} end

	local manifest = decodeJSON(manifestObj.Value)
	return manifest[category] or {}
end

--------------------------------------------------------------------------------
-- 디자인 문서: 게임 설계 의도를 기록
--------------------------------------------------------------------------------

--- 디자인 문서 업데이트 (게임 장르, 분위기, 핵심 시스템 등)
function SessionManager.updateDesignDoc(section: string, content: string)
	local folder = getEngineFolder()
	local docObj = getOrCreateStringValue(folder, DESIGN_DOC)

	local doc = decodeJSON(docObj.Value)
	doc[section] = {
		content = content,
		updatedAt = os.date("%Y-%m-%d %H:%M:%S"),
	}

	docObj.Value = encodeJSON(doc)

	SessionManager.logAction("DESIGN_UPDATED", section)
end

--- 디자인 문서 전체 출력
function SessionManager.getDesignDoc(): string
	local folder = ServerStorage:FindFirstChild(ENGINE_FOLDER)
	if not folder then return "No design document." end

	local docObj = folder:FindFirstChild(DESIGN_DOC)
	if not docObj then return "No design document." end

	local doc = decodeJSON(docObj.Value)
	local lines = {"=== GAME DESIGN DOCUMENT ==="}

	for section, data in doc do
		table.insert(lines, string.format("\n## %s (updated: %s)", section, data.updatedAt or "?"))
		table.insert(lines, data.content or "")
	end

	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- 세션 복원: 새 대화 시작 시 전체 상태 요약
--------------------------------------------------------------------------------

--- 컨텍스트 복원 보고서 (새 세션에서 가장 먼저 실행)
function SessionManager.getRestorationReport(): string
	local lines = {
		"╔══════════════════════════════════════════╗",
		"║     ROBLOX ENGINE - SESSION RESTORE      ║",
		"╚══════════════════════════════════════════╝",
		"",
	}

	-- 1. 디자인 문서
	table.insert(lines, SessionManager.getDesignDoc())
	table.insert(lines, "")

	-- 2. 빌드 매니페스트
	table.insert(lines, SessionManager.getBuildManifest())
	table.insert(lines, "")

	-- 3. 최근 로그
	table.insert(lines, SessionManager.getRecentLog(10))
	table.insert(lines, "")

	-- 4. 워크스페이스 요약
	local partCount, modelCount, scriptCount = 0, 0, 0
	local function count(inst)
		if inst.Name:sub(1, 13) == "_RobloxEngine" then return end
		if inst:IsA("BasePart") then partCount += 1
		elseif inst:IsA("Model") then modelCount += 1
		elseif inst:IsA("BaseScript") then scriptCount += 1
		end
		for _, child in inst:GetChildren() do count(child) end
	end
	for _, child in workspace:GetChildren() do
		if child.Name ~= "Camera" and child.Name ~= "Terrain" then
			count(child)
		end
	end

	table.insert(lines, string.format("=== WORKSPACE: %d parts, %d models, %d scripts ===",
		partCount, modelCount, scriptCount))

	-- 5. 앵커 목록
	local anchorsFolder = workspace:FindFirstChild("_RobloxEngine_Anchors")
	if anchorsFolder then
		local anchorCount = 0
		for _, a in anchorsFolder:GetChildren() do
			if a:IsA("BasePart") then anchorCount += 1 end
		end
		if anchorCount > 0 then
			table.insert(lines, string.format("=== ANCHORS: %d reference points ===", anchorCount))
		end
	end

	return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- 체크포인트: 현재 상태를 스냅샷으로 저장
--------------------------------------------------------------------------------

--- 체크포인트 생성
function SessionManager.createCheckpoint(name: string, description: string?)
	local folder = getEngineFolder()
	local checkpointsObj = getOrCreateStringValue(folder, "_Checkpoints")
	local checkpoints = decodeJSON(checkpointsObj.Value)

	-- 현재 워크스페이스 파트 목록 스냅샷
	local parts = {}
	local function scan(inst, path)
		if inst.Name:sub(1, 13) == "_RobloxEngine" then return end
		if inst:IsA("BasePart") then
			table.insert(parts, {
				path = path .. "." .. inst.Name,
				pos = {inst.Position.X, inst.Position.Y, inst.Position.Z},
				size = {inst.Size.X, inst.Size.Y, inst.Size.Z},
			})
		end
		for _, child in inst:GetChildren() do
			scan(child, path .. "." .. inst.Name)
		end
	end
	for _, child in workspace:GetChildren() do
		if child.Name ~= "Camera" and child.Name ~= "Terrain" then
			scan(child, "workspace")
		end
	end

	checkpoints[name] = {
		description = description or "",
		createdAt = os.date("%Y-%m-%d %H:%M:%S"),
		partCount = #parts,
		parts = parts,
	}

	checkpointsObj.Value = encodeJSON(checkpoints)

	SessionManager.logAction("CHECKPOINT", name .. " (" .. #parts .. " parts)")
	return #parts
end

--- 체크포인트 목록
function SessionManager.listCheckpoints(): string
	local folder = ServerStorage:FindFirstChild(ENGINE_FOLDER)
	if not folder then return "No checkpoints." end

	local obj = folder:FindFirstChild("_Checkpoints")
	if not obj then return "No checkpoints." end

	local checkpoints = decodeJSON(obj.Value)
	local lines = {"=== CHECKPOINTS ==="}

	for name, data in checkpoints do
		table.insert(lines, string.format("  [%s] %s - %d parts (%s)",
			data.createdAt or "?",
			name,
			data.partCount or 0,
			data.description or ""
		))
	end

	return table.concat(lines, "\n")
end

return SessionManager
